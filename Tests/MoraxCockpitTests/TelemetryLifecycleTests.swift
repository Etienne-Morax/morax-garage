import AppKit
import Foundation
import Testing
@testable import MoraxCockpitKit

@MainActor
private final class CountingFeedControl: TelemetryFeedControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var isRunning: Bool { startCount > stopCount }

    func startMonitoring() { startCount += 1 }
    func stopMonitoring() { stopCount += 1 }
}

@MainActor
private func makeCountingCoordinator(
    stopGracePeriod: TimeInterval = 0
) -> (TelemetryCoordinator, [TelemetryFeed: CountingFeedControl]) {
    let spies = Dictionary(uniqueKeysWithValues: TelemetryFeed.allCases.map { ($0, CountingFeedControl()) })
    return (TelemetryCoordinator(controls: spies, stopGracePeriod: stopGracePeriod), spies)
}

@Suite("Dashboard telemetry ownership")
@MainActor
struct DashboardTelemetryOwnershipTests {
    @Test("dashboard demand adds usage and Higgsfield only when their cards are shown")
    func demandFollowsCardSettings() {
        #expect(DashboardTelemetryDemand.feeds(showUsageQuotas: false, showHiggsfield: false)
            == [.system, .network, .process])
        #expect(DashboardTelemetryDemand.feeds(showUsageQuotas: true, showHiggsfield: false)
            == [.system, .network, .process, .usage, .openAICosts])
        #expect(DashboardTelemetryDemand.feeds(showUsageQuotas: true, showHiggsfield: true)
            == [.system, .network, .process, .usage, .openAICosts, .higgsfield])
    }

    @Test("a second acquire under the dashboard id replaces the first, so a narrower writer stops usage")
    func sameConsumerReplacesDemand() {
        // Documents why the dashboard id must have exactly one writer: before the fix,
        // RootView re-acquired the base set after DashboardView had acquired the full
        // one, which silently stopped usage and Higgsfield polling.
        let (coordinator, spies) = makeCountingCoordinator()
        let fullSet = DashboardTelemetryDemand.feeds(showUsageQuotas: true, showHiggsfield: true)

        coordinator.acquire(TelemetryConsumer.dashboard, feeds: fullSet)
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: DashboardTelemetryDemand.baseFeeds)

        #expect(coordinator.runningFeeds == DashboardTelemetryDemand.baseFeeds)
        #expect(spies[.usage]?.stopCount == 1)
        #expect(spies[.higgsfield]?.stopCount == 1)
    }

    @Test("toggling a card re-acquires with the new set and release on disappear stops everything")
    func singleOwnerLifecycle() {
        let (coordinator, spies) = makeCountingCoordinator()

        coordinator.acquire(
            TelemetryConsumer.dashboard,
            feeds: DashboardTelemetryDemand.feeds(showUsageQuotas: false, showHiggsfield: true)
        )
        #expect(spies[.usage]?.startCount == 0)

        coordinator.acquire(
            TelemetryConsumer.dashboard,
            feeds: DashboardTelemetryDemand.feeds(showUsageQuotas: true, showHiggsfield: true)
        )
        #expect(spies[.usage]?.isRunning == true)
        #expect(spies[.system]?.startCount == 1)

        coordinator.release(TelemetryConsumer.dashboard)
        #expect(coordinator.runningFeeds.isEmpty)
    }

    @Test("a rebuilt dashboard whose old instance disappears last keeps the feeds running")
    func leaseSurvivesViewSwap() {
        let (coordinator, _) = makeCountingCoordinator()
        let lease = DashboardTelemetryLease(coordinator: coordinator)
        let feeds = DashboardTelemetryDemand.baseFeeds

        lease.hold(feeds: feeds)   // first instance appears
        lease.hold(feeds: feeds)   // rebuilt instance appears
        lease.drop()               // old instance disappears afterwards

        #expect(coordinator.requestedFeeds == feeds)
        lease.drop()               // tab left
        #expect(coordinator.requestedFeeds.isEmpty)
    }
}

@MainActor
private final class VisibilityBox {
    var isVisible = true
}

@Suite("Window visibility pauses the dashboard")
@MainActor
struct WindowVisibilityTelemetryGateTests {
    @Test("pausing a consumer stops only its own feeds and keeps its demand")
    func pauseKeepsOtherConsumers() {
        let (coordinator, spies) = makeCountingCoordinator()
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])

        coordinator.setPaused(true, consumer: TelemetryConsumer.dashboard)

        #expect(coordinator.runningFeeds == [.system])
        #expect(spies[.network]?.stopCount == 1)
        #expect(spies[.process]?.stopCount == 1)
        #expect(spies[.system]?.stopCount == 0)

        coordinator.setPaused(false, consumer: TelemetryConsumer.dashboard)

        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.network]?.startCount == 2)
        #expect(spies[.system]?.startCount == 1)
    }

    @Test("a consumer that acquires while paused starts nothing until resumed")
    func acquireWhilePaused() {
        let (coordinator, spies) = makeCountingCoordinator()
        coordinator.setPaused(true, consumer: TelemetryConsumer.dashboard)

        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.network])
        #expect(spies[.network]?.startCount == 0)

        coordinator.setPaused(false, consumer: TelemetryConsumer.dashboard)
        #expect(spies[.network]?.startCount == 1)
    }

    @Test("occlusion and miniaturize signals pause, then resume, the dashboard feeds")
    func occlusionSignalPausesAndResumes() {
        let (coordinator, spies) = makeCountingCoordinator()
        let center = NotificationCenter()
        let gate = WindowVisibilityTelemetryGate(
            consumer: TelemetryConsumer.dashboard,
            coordinator: coordinator,
            notificationCenter: center
        )
        let window = NSObject()
        let visibility = VisibilityBox()
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        coordinator.acquire(TelemetryConsumer.miniCockpit, feeds: [.system])
        gate.track(window) { visibility.isVisible }
        #expect(gate.isPaused == false)

        visibility.isVisible = false
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)

        #expect(gate.isPaused)
        #expect(coordinator.runningFeeds == [.system])
        #expect(spies[.network]?.isRunning == false)

        visibility.isVisible = true
        center.post(name: NSWindow.didDeminiaturizeNotification, object: window)

        #expect(gate.isPaused == false)
        #expect(coordinator.runningFeeds == [.system, .network, .process])
    }

    @Test("signals from another window are ignored, and closing the window lifts the pause")
    func otherWindowsAndCloseAreHandled() {
        let (coordinator, _) = makeCountingCoordinator()
        let center = NotificationCenter()
        let gate = WindowVisibilityTelemetryGate(
            consumer: TelemetryConsumer.dashboard,
            coordinator: coordinator,
            notificationCenter: center
        )
        let window = NSObject()
        let visibility = VisibilityBox()
        gate.track(window) { visibility.isVisible }

        visibility.isVisible = false
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: NSObject())
        #expect(gate.isPaused == false)

        center.post(name: NSWindow.didMiniaturizeNotification, object: window)
        #expect(coordinator.isPaused(TelemetryConsumer.dashboard))

        center.post(name: NSWindow.willCloseNotification, object: window)
        #expect(gate.isPaused == false)
        #expect(coordinator.isPaused(TelemetryConsumer.dashboard) == false)
    }

    @Test("the dashboard stays active while at least one of its windows is visible")
    func anyVisibleWindowKeepsDashboardRunning() {
        let (coordinator, _) = makeCountingCoordinator()
        let center = NotificationCenter()
        let gate = WindowVisibilityTelemetryGate(
            consumer: TelemetryConsumer.dashboard,
            coordinator: coordinator,
            notificationCenter: center
        )
        let first = NSObject()
        let second = NSObject()
        let firstVisibility = VisibilityBox()
        let secondVisibility = VisibilityBox()
        gate.track(first) { firstVisibility.isVisible }
        gate.track(second) { secondVisibility.isVisible }

        firstVisibility.isVisible = false
        center.post(name: NSWindow.didMiniaturizeNotification, object: first)
        #expect(gate.isPaused == false)

        secondVisibility.isVisible = false
        center.post(name: NSApplication.didHideNotification, object: nil)
        #expect(gate.isPaused)
    }
}

@Suite("Sleep and wake suspend every feed")
@MainActor
struct TelemetrySleepWakeTests {
    private func makeObservedCoordinator(
        stopGracePeriod: TimeInterval = 0
    ) -> (TelemetryCoordinator, [TelemetryFeed: CountingFeedControl], NotificationCenter) {
        let spies = Dictionary(uniqueKeysWithValues: TelemetryFeed.allCases.map { ($0, CountingFeedControl()) })
        let center = NotificationCenter()
        let coordinator = TelemetryCoordinator(
            controls: spies,
            stopGracePeriod: stopGracePeriod,
            powerNotificationCenter: center
        )
        return (coordinator, spies, center)
    }

    @Test("system sleep stops every feed at once, even with a grace period, and wake restarts them")
    func systemSleepStopsAndWakeRestarts() {
        let (coordinator, spies, center) = makeObservedCoordinator(stopGracePeriod: 5.0)
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])
        coordinator.acquire(TelemetryConsumer.miniCockpit, feeds: [.system, .process, .usage])

        center.post(name: NSWorkspace.willSleepNotification, object: nil)

        #expect(coordinator.isSuspended)
        #expect(coordinator.runningFeeds.isEmpty)
        #expect(coordinator.feedsPendingStop.isEmpty)
        #expect(spies[.system]?.stopCount == 1)
        #expect(spies[.usage]?.stopCount == 1)

        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(coordinator.isSuspended == false)
        #expect(coordinator.runningFeeds == [.system, .process, .usage])
        #expect(spies[.system]?.startCount == 2)
    }

    @Test("display sleep suspends, and demand changes while asleep apply on display wake")
    func displaySleepKeepsDemandForWake() {
        let (coordinator, spies, center) = makeObservedCoordinator()
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        coordinator.acquire(TelemetryConsumer.menuBarPopover, feeds: [.network])

        #expect(spies[.network]?.startCount == 0)
        #expect(coordinator.runningFeeds.isEmpty)

        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        #expect(coordinator.runningFeeds == [.system, .network])
    }

    @Test("feeds stay off until every suspension reason has cleared")
    func overlappingReasons() {
        let (coordinator, spies, center) = makeObservedCoordinator()
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])

        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        #expect(coordinator.isSuspended)
        #expect(spies[.system]?.isRunning == false)

        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        #expect(spies[.system]?.isRunning == true)
        #expect(spies[.system]?.startCount == 2)
        #expect(spies[.system]?.stopCount == 1)
    }

    @Test("a wake without a matching display wake still resumes telemetry")
    func systemWakeClearsDisplaySleep() {
        let (coordinator, _, center) = makeObservedCoordinator()
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(coordinator.isSuspended == false)
        #expect(coordinator.runningFeeds == [.system])
    }

    @Test("a coordinator without a power notification center ignores workspace notifications")
    func noCenterNoSuspension() {
        let (coordinator, _) = makeCountingCoordinator()
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])

        NotificationCenter().post(name: NSWorkspace.willSleepNotification, object: nil)

        #expect(coordinator.isSuspended == false)
        #expect(coordinator.runningFeeds == [.system])
    }
}

@Suite("macmon stall watchdog")
struct MacmonStallWatchdogTests {
    private let launch = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("a stream that spoke within the timeout is healthy")
    func recentLineIsHealthy() {
        #expect(!SystemMetricsService.isMacmonStreamStalled(
            lastLineAt: launch, now: launch.addingTimeInterval(14), updateInterval: 1.5
        ))
    }

    @Test("a stream silent past the minimum timeout is stalled")
    func silentStreamIsStalled() {
        #expect(SystemMetricsService.isMacmonStreamStalled(
            lastLineAt: launch, now: launch.addingTimeInterval(16), updateInterval: 1.5
        ))
    }

    @Test("long sample intervals widen the timeout so slow streams are not killed")
    func timeoutScalesWithInterval() {
        #expect(!SystemMetricsService.isMacmonStreamStalled(
            lastLineAt: launch, now: launch.addingTimeInterval(30), updateInterval: 5
        ))
        #expect(SystemMetricsService.isMacmonStreamStalled(
            lastLineAt: launch, now: launch.addingTimeInterval(41), updateInterval: 5
        ))
    }
}
