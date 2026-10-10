import Foundation
import Testing
@testable import MoraxCockpitKit

@MainActor
private final class SpyFeedControl: TelemetryFeedControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var isRunning: Bool { startCount > stopCount }

    func startMonitoring() { startCount += 1 }
    func stopMonitoring() { stopCount += 1 }
}

@MainActor
private func makeCoordinator() -> (TelemetryCoordinator, [TelemetryFeed: SpyFeedControl]) {
    let spies: [TelemetryFeed: SpyFeedControl] = [
        .system: SpyFeedControl(),
        .network: SpyFeedControl(),
        .process: SpyFeedControl(),
        .usage: SpyFeedControl(),
        .higgsfield: SpyFeedControl(),
        .metaMuse: SpyFeedControl(),
        .openAICosts: SpyFeedControl()
    ]
    // Zero grace period keeps these tests synchronous; the grace behaviour has its
    // own suite below.
    return (TelemetryCoordinator(controls: spies, stopGracePeriod: 0), spies)
}

@MainActor
private func makeGracefulCoordinator(
    stopGracePeriod: TimeInterval
) -> (TelemetryCoordinator, [TelemetryFeed: SpyFeedControl]) {
    let spies: [TelemetryFeed: SpyFeedControl] = [
        .system: SpyFeedControl(),
        .network: SpyFeedControl(),
        .process: SpyFeedControl(),
        .usage: SpyFeedControl(),
        .higgsfield: SpyFeedControl(),
        .metaMuse: SpyFeedControl(),
        .openAICosts: SpyFeedControl()
    ]
    return (TelemetryCoordinator(controls: spies, stopGracePeriod: stopGracePeriod), spies)
}

@Suite("TelemetryCoordinator")
@MainActor
struct TelemetryCoordinatorTests {
    @Test("Acquiring a feed starts it once")
    func acquiringStartsFeed() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("dashboard", feeds: [.system, .process])

        #expect(coordinator.runningFeeds == [.system, .process])
        #expect(spies[.system]?.startCount == 1)
        #expect(spies[.process]?.startCount == 1)
        #expect(spies[.network]?.startCount == 0)
    }

    @Test("A feed keeps running while another consumer still wants it")
    func feedSurvivesPartialRelease() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("dashboard", feeds: [.system, .network])
        coordinator.acquire("menuBarLabel", feeds: [.system])

        coordinator.release("dashboard")

        #expect(coordinator.runningFeeds == [.system])
        #expect(spies[.system]?.stopCount == 0)
        #expect(spies[.network]?.stopCount == 1)
    }

    @Test("Releasing the last consumer stops every feed")
    func releasingLastConsumerStopsFeeds() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("dashboard", feeds: [.system, .network, .process])
        coordinator.release("dashboard")

        #expect(coordinator.runningFeeds.isEmpty)
        for feed in TelemetryFeed.allCases {
            #expect(spies[feed]?.isRunning == false)
        }
    }

    @Test("Re-acquiring an unchanged demand does not restart the feed")
    func repeatedAcquireIsIdempotent() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("dashboard", feeds: [.system])
        coordinator.acquire("dashboard", feeds: [.system])
        coordinator.acquire("dashboard", feeds: [.system])

        #expect(spies[.system]?.startCount == 1)
        #expect(spies[.system]?.stopCount == 0)
    }

    @Test("Narrowing a demand stops only the feeds that were dropped")
    func narrowingDemandStopsDroppedFeeds() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("menuBarLabel", feeds: [.system, .network])
        coordinator.acquire("menuBarLabel", feeds: [.system])

        #expect(coordinator.runningFeeds == [.system])
        #expect(spies[.system]?.startCount == 1)
        #expect(spies[.network]?.stopCount == 1)
    }

    @Test("Acquiring an empty set releases the consumer")
    func emptyDemandReleasesConsumer() {
        let (coordinator, _) = makeCoordinator()

        coordinator.acquire("menuBarLabel", feeds: [.system])
        coordinator.acquire("menuBarLabel", feeds: [])

        #expect(coordinator.runningFeeds.isEmpty)
        #expect(coordinator.requestedFeeds.isEmpty)
    }

    @Test("Releasing everything stops feeds held by several consumers")
    func releaseAllStopsEverything() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("dashboard", feeds: [.system, .process])
        coordinator.acquire("menuBarPopover", feeds: [.network])

        coordinator.releaseAll()

        #expect(coordinator.runningFeeds.isEmpty)
        #expect(spies[.system]?.stopCount == 1)
        #expect(spies[.network]?.stopCount == 1)
        #expect(spies[.process]?.stopCount == 1)
    }

    @Test("Releasing an unknown consumer changes nothing")
    func releasingUnknownConsumerIsInert() {
        let (coordinator, spies) = makeCoordinator()

        coordinator.acquire("dashboard", feeds: [.system])
        coordinator.release("nobody")

        #expect(coordinator.runningFeeds == [.system])
        #expect(spies[.system]?.stopCount == 0)
    }
}


@Suite("TelemetryCoordinator stop grace period")
@MainActor
struct TelemetryCoordinatorGracePeriodTests {
    @Test("A release followed by a re-acquire never stops the feed")
    func viewChurnDoesNotStopFeed() async {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 5.0)

        coordinator.acquire("dashboard", feeds: [.system])
        coordinator.release("dashboard")
        coordinator.acquire("dashboard", feeds: [.system])

        #expect(spies[.system]?.stopCount == 0)
        #expect(spies[.system]?.startCount == 1)
        #expect(coordinator.runningFeeds == [.system])
        #expect(coordinator.feedsPendingStop.isEmpty)
    }

    @Test("A feed keeps running until the grace period elapses")
    func feedStopsOnceGracePeriodElapses() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 0.1)

        coordinator.acquire("dashboard", feeds: [.system])
        coordinator.release("dashboard")

        #expect(coordinator.runningFeeds == [.system])
        #expect(coordinator.feedsPendingStop == [.system])
        #expect(spies[.system]?.stopCount == 0)

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(coordinator.runningFeeds.isEmpty)
        #expect(coordinator.feedsPendingStop.isEmpty)
        #expect(spies[.system]?.stopCount == 1)
    }

    @Test("releaseAll stops feeds immediately, without waiting out the grace period")
    func releaseAllBypassesGracePeriod() {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 5.0)

        coordinator.acquire("dashboard", feeds: [.system, .network])
        coordinator.releaseAll()

        #expect(coordinator.runningFeeds.isEmpty)
        #expect(coordinator.feedsPendingStop.isEmpty)
        #expect(spies[.system]?.stopCount == 1)
        #expect(spies[.network]?.stopCount == 1)
    }

    @Test("A pending stop is cancelled when another consumer claims the feed")
    func anotherConsumerCancelsPendingStop() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 0.1)

        coordinator.acquire("dashboard", feeds: [.system])
        coordinator.release("dashboard")
        coordinator.acquire("menuBarLabel", feeds: [.system])

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(coordinator.runningFeeds == [.system])
        #expect(spies[.system]?.startCount == 1)
        #expect(spies[.system]?.stopCount == 0)
    }
}

@Suite("TelemetryCoordinator lifecycle scenarios")
@MainActor
struct TelemetryCoordinatorLifecycleScenariosSuite {
    @Test("MenuBarExtra popover open and close does not kill active Dashboard telemetry")
    func menuBarPopoverInteractionWithActiveDashboard() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 0.1)

        // 1. Dashboard is active
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.system]?.startCount == 1)

        // 2. User opens MenuBarExtra popover
        coordinator.acquire(TelemetryConsumer.menuBarPopover, feeds: [.system, .network, .process])
        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.system]?.startCount == 1) // already running, no duplicate start

        // 3. User closes MenuBarExtra popover
        coordinator.release(TelemetryConsumer.menuBarPopover)
        
        // Wait past grace period
        try await Task.sleep(nanoseconds: 250_000_000)

        // Dashboard is still active, so feeds MUST remain running without stop
        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.system]?.stopCount == 0)
        #expect(spies[.network]?.stopCount == 0)
        #expect(spies[.process]?.stopCount == 0)
    }

    @Test("MenuBarExtra popover open and close stops cleanly when Dashboard is inactive")
    func menuBarPopoverAloneStopsCleanlyAfterGracePeriod() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 0.1)

        // Dashboard is closed / inactive
        // 1. User clicks MenuBarExtra -> popover opens
        coordinator.acquire(TelemetryConsumer.menuBarPopover, feeds: [.system, .network, .process])
        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.system]?.startCount == 1)

        // 2. Popover closes
        coordinator.release(TelemetryConsumer.menuBarPopover)
        #expect(coordinator.feedsPendingStop == [.system, .network, .process])
        #expect(spies[.system]?.stopCount == 0) // still in grace period

        // 3. Wait past grace period
        try await Task.sleep(nanoseconds: 300_000_000)

        // Feeds must be stopped cleanly
        #expect(coordinator.runningFeeds.isEmpty)
        #expect(coordinator.feedsPendingStop.isEmpty)
        #expect(spies[.system]?.stopCount == 1)
        #expect(spies[.network]?.stopCount == 1)
        #expect(spies[.process]?.stopCount == 1)
    }

    @Test("Tab switch away from Dashboard stops feeds after grace period, and tab switch back restarts feeds")
    func tabSwitchWorkflow() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 0.1)

        // 1. Dashboard active
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        #expect(coordinator.runningFeeds == [.system, .network, .process])

        // 2. User switches to Storage Map tab (lasting navigation)
        coordinator.release(TelemetryConsumer.dashboard)
        #expect(coordinator.feedsPendingStop == [.system, .network, .process])

        // Wait past grace period
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(coordinator.runningFeeds.isEmpty)
        #expect(spies[.system]?.stopCount == 1)

        // 3. User switches back to Dashboard
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.system]?.startCount == 2)
        #expect(spies[.system]?.stopCount == 1)
    }

    @Test("Transient onDisappear / re-appear during scene layout is absorbed by grace period")
    func transientDisappearReappearFlow() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 0.2)

        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        #expect(coordinator.runningFeeds == [.system, .network, .process])

        // Transient disappear (e.g. view rebuild)
        coordinator.release(TelemetryConsumer.dashboard)
        #expect(coordinator.feedsPendingStop == [.system, .network, .process])

        // Small sleep well within grace period
        try await Task.sleep(nanoseconds: 50_000_000)

        // Re-appear
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        #expect(coordinator.feedsPendingStop.isEmpty)

        // Wait past the original grace period deadline
        try await Task.sleep(nanoseconds: 300_000_000)

        // Feeds were NEVER stopped
        #expect(coordinator.runningFeeds == [.system, .network, .process])
        #expect(spies[.system]?.stopCount == 0)
        #expect(spies[.system]?.startCount == 1)
    }

    @Test("Clean termination via releaseAll cancels all pending stops and halts running feeds")
    func cleanTerminationBypassesGraceAndCleansUp() async throws {
        let (coordinator, spies) = makeGracefulCoordinator(stopGracePeriod: 5.0)

        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])
        coordinator.acquire(TelemetryConsumer.menuBarLabel, feeds: [.system])

        #expect(coordinator.runningFeeds == [.system, .network, .process])

        coordinator.releaseAll()

        #expect(coordinator.runningFeeds.isEmpty)
        #expect(coordinator.requestedFeeds.isEmpty)
        #expect(coordinator.feedsPendingStop.isEmpty)
        #expect(spies[.system]?.stopCount == 1)
        #expect(spies[.network]?.stopCount == 1)
        #expect(spies[.process]?.stopCount == 1)
    }
}
