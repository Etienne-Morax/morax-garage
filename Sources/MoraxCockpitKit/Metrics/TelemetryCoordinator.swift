import AppKit
import Foundation

/// One of the live metric sources the coordinator can keep running.
public enum TelemetryFeed: String, CaseIterable, Hashable, Sendable {
    /// `macmon` driven CPU, GPU, memory, power and thermal sampling.
    case system
    /// `nettop` driven per-application and interface throughput.
    case network
    /// `/bin/ps` driven top CPU and RAM applications.
    case process
    /// Authenticated cockpit usage-quota polling.
    case usage
    /// Higgsfield AI account credit polling.
    case higgsfield
    /// Local Muse Code (Meta) session activity polling.
    case metaMuse
    /// OpenAI organization costs polling (admin key).
    case openAICosts
}

/// Why the coordinator holds every feed off.
public enum TelemetrySuspensionReason: String, Hashable, Sendable {
    case systemSleep
    case displaySleep
    case sessionInactive
}

/// A metric service the coordinator can switch on and off.
@MainActor
public protocol TelemetryFeedControlling: AnyObject {
    func startMonitoring()
    func stopMonitoring()
}

extension SystemMetricsService: TelemetryFeedControlling {}
extension NetworkMetricsService: TelemetryFeedControlling {}
extension ProcessMetricsService: TelemetryFeedControlling {}

/// Reference counted owner of the live telemetry services.
///
/// Monitoring used to be started and stopped from three places that disagreed with
/// each other: the dashboard's appearance, the menu bar popover's appearance (which
/// inspected `NSApp.windows` by hand) and the root view's scene phase. Whichever ran
/// last decided whether the external processes kept running, so they sometimes
/// outlived every window.
///
/// Consumers now declare which feeds they need and release them when they go away.
/// A feed runs while at least one consumer wants it and stops as soon as the last one
/// lets go, so `macmon`, `nettop` and `ps` are alive only while something displays
/// their output.
///
/// `CacheTelemetryService` is deliberately outside this: it owns a daily scan that
/// belongs to the application lifetime, not to any view.
@MainActor
public final class TelemetryCoordinator {
    public static let shared = TelemetryCoordinator(
        powerNotificationCenter: NSWorkspace.shared.notificationCenter
    )

    /// How long a feed keeps running after its last consumer lets go.
    ///
    /// SwiftUI tears views down and rebuilds them constantly: switching tab, opening
    /// the menu bar popover or re-laying out the status item all fire
    /// `onDisappear` followed by `onAppear` within the same second. Stopping the
    /// feeds on the spot meant `macmon` and `nettop` were killed before they had
    /// produced a second sample, so the gauges never left their "waiting for the
    /// first interval" state. A short grace period absorbs that churn; a real
    /// release still stops the feed once the delay elapses.
    public static let defaultStopGracePeriod: TimeInterval = 5.0

    private let controls: [TelemetryFeed: any TelemetryFeedControlling]
    private let stopGracePeriod: TimeInterval
    private var demands: [String: Set<TelemetryFeed>] = [:]
    private var pausedConsumers: Set<String> = []
    private var suspensionReasons: Set<TelemetrySuspensionReason> = []
    private var pendingStops: [TelemetryFeed: Task<Void, Never>] = [:]

    /// Feeds currently switched on.
    public private(set) var runningFeeds: Set<TelemetryFeed> = []

    /// True while the Mac sleeps, its displays sleep or the user session is switched
    /// out. Every feed is stopped then; demands are kept and restored on resume.
    public var isSuspended: Bool { !suspensionReasons.isEmpty }

    /// - Parameter powerNotificationCenter: where sleep, wake and session
    ///   notifications arrive (`NSWorkspace.shared.notificationCenter` for the shared
    ///   instance). `nil` leaves suspension to explicit `suspend`/`resume` calls.
    public init(
        controls: [TelemetryFeed: any TelemetryFeedControlling]? = nil,
        stopGracePeriod: TimeInterval = TelemetryCoordinator.defaultStopGracePeriod,
        powerNotificationCenter: NotificationCenter? = nil
    ) {
        self.controls = controls ?? [
            .system: SystemMetricsService.shared,
            .network: NetworkMetricsService.shared,
            .process: ProcessMetricsService.shared,
            .usage: UsageQuotaService.shared,
            .higgsfield: HiggsfieldCreditService.shared,
            .metaMuse: MetaMuseService.shared,
            .openAICosts: OpenAICostsService.shared
        ]
        self.stopGracePeriod = stopGracePeriod
        if let powerNotificationCenter {
            observePowerEvents(on: powerNotificationCenter)
        }
    }

    /// Holds every feed off for `reason`, stopping running ones immediately: nobody
    /// is looking, and a sleeping Mac should not keep `macmon` or pollers alive.
    public func suspend(_ reason: TelemetrySuspensionReason) {
        let wasSuspended = isSuspended
        guard suspensionReasons.insert(reason).inserted else { return }
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: suspended (\(reason.rawValue, privacy: .public))")
        guard !wasSuspended else { return }
        for feed in TelemetryFeed.allCases where runningFeeds.contains(feed) {
            stopNow(feed)
        }
    }

    /// Lifts `reason`; once no reason is left, the retained demands restart their
    /// feeds, which also relaunches a fresh `macmon` after wake.
    public func resume(_ reason: TelemetrySuspensionReason) {
        guard suspensionReasons.remove(reason) != nil else { return }
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: resumed (\(reason.rawValue, privacy: .public))")
        guard !isSuspended else { return }
        reconcile()
    }

    private func observePowerEvents(on center: NotificationCenter) {
        let transitions: [(Notification.Name, @MainActor (TelemetryCoordinator) -> Void)] = [
            (NSWorkspace.willSleepNotification, { $0.suspend(.systemSleep) }),
            // A system wake also wakes the displays; clearing both avoids staying
            // suspended if the display wake notification never arrives.
            (NSWorkspace.didWakeNotification, { $0.resume(.systemSleep); $0.resume(.displaySleep) }),
            (NSWorkspace.screensDidSleepNotification, { $0.suspend(.displaySleep) }),
            (NSWorkspace.screensDidWakeNotification, { $0.resume(.displaySleep) }),
            (NSWorkspace.sessionDidResignActiveNotification, { $0.suspend(.sessionInactive) }),
            (NSWorkspace.sessionDidBecomeActiveNotification, { $0.resume(.sessionInactive) })
        ]
        for (name, transition) in transitions {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    transition(self)
                }
            }
        }
    }

    /// Feeds whose last consumer let go but that are still inside the grace period.
    public var feedsPendingStop: Set<TelemetryFeed> {
        Set(pendingStops.keys)
    }

    /// Feeds wanted by at least one consumer that is not paused.
    public var requestedFeeds: Set<TelemetryFeed> {
        demands.reduce(into: Set<TelemetryFeed>()) { wanted, entry in
            guard !pausedConsumers.contains(entry.key) else { return }
            wanted.formUnion(entry.value)
        }
    }

    /// Whether `consumer` is currently paused.
    public func isPaused(_ consumer: String) -> Bool {
        pausedConsumers.contains(consumer)
    }

    /// Pauses or resumes a consumer without forgetting its demand.
    ///
    /// A paused consumer keeps its declared feeds but no longer keeps them running,
    /// so hiding a window lets its feeds stop (after the grace period) while other
    /// consumers such as the menu bar keep theirs. Resuming restores the demand.
    public func setPaused(_ paused: Bool, consumer: String) {
        let changed = paused
            ? pausedConsumers.insert(consumer).inserted
            : pausedConsumers.remove(consumer) != nil
        guard changed else { return }
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: '\(consumer, privacy: .public)' \(paused ? "paused" : "resumed", privacy: .public)")
        reconcile()
    }

    /// Registers, or updates, what a consumer needs. Calling it again with the same
    /// identifier replaces that consumer's previous demand; an empty set releases it.
    public func acquire(_ consumer: String, feeds: Set<TelemetryFeed>) {
        guard !feeds.isEmpty else {
            release(consumer)
            return
        }
        guard demands[consumer] != feeds else { return }
        demands[consumer] = feeds
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: '\(consumer, privacy: .public)' acquired feeds: [\(feeds.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)]")
        reconcile()
    }

    /// Drops a consumer's claim. Feeds no other consumer wants are stopped.
    public func release(_ consumer: String) {
        guard demands.removeValue(forKey: consumer) != nil else { return }
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: '\(consumer, privacy: .public)' released")
        reconcile()
    }

    /// Drops every claim and stops all feeds at once, skipping the grace period.
    /// Used on termination, where waiting would leave orphaned child processes.
    public func releaseAll() {
        guard !demands.isEmpty || !runningFeeds.isEmpty else { return }
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: releaseAll called (stopping \(self.runningFeeds.count) running feeds immediately)")
        demands.removeAll()
        for feed in TelemetryFeed.allCases where runningFeeds.contains(feed) {
            stopNow(feed)
        }
    }

    private func reconcile() {
        let wanted = isSuspended ? [] : requestedFeeds

        for feed in TelemetryFeed.allCases {
            if wanted.contains(feed) {
                // A consumer came back: cancel any stop still waiting out its delay.
                if pendingStops.removeValue(forKey: feed) != nil {
                    TelemetryLogger.lifecycle.info("TelemetryCoordinator: cancelled pending stop for '\(feed.rawValue, privacy: .public)' (demand restored)")
                }
                guard !runningFeeds.contains(feed) else { continue }
                TelemetryLogger.lifecycle.info("TelemetryCoordinator: starting feed '\(feed.rawValue, privacy: .public)'")
                controls[feed]?.startMonitoring()
                runningFeeds.insert(feed)
            } else if runningFeeds.contains(feed), pendingStops[feed] == nil {
                scheduleStop(feed)
            }
        }
    }

    private func scheduleStop(_ feed: TelemetryFeed) {
        guard stopGracePeriod > 0 else {
            stopNow(feed)
            return
        }

        let delay = stopGracePeriod
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: scheduling stop for '\(feed.rawValue, privacy: .public)' in \(delay)s grace period")
        pendingStops[feed] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.pendingStops[feed] = nil
            guard !self.requestedFeeds.contains(feed) else { return }
            self.stopNow(feed)
        }
    }

    private func stopNow(_ feed: TelemetryFeed) {
        pendingStops.removeValue(forKey: feed)?.cancel()
        guard runningFeeds.contains(feed) else { return }
        TelemetryLogger.lifecycle.info("TelemetryCoordinator: stopping feed '\(feed.rawValue, privacy: .public)' now")
        controls[feed]?.stopMonitoring()
        runningFeeds.remove(feed)
    }
}

/// Identifiers of the consumers shipped with the application.
public enum TelemetryConsumer {
    /// The dashboard tab, which shows every live gauge.
    public static let dashboard = "dashboard"
    /// The menu bar popover, open only while the user looks at it.
    public static let menuBarPopover = "menuBarPopover"
    /// The always-visible menu bar readout, whose needs depend on user settings.
    public static let menuBarLabel = "menuBarLabel"
    /// The floating Mini Cockpit HUD in glance mode.
    public static let miniCockpit = "miniCockpit"
    /// The floating Mini Cockpit HUD in expanded detail mode.
    public static let miniCockpitDetail = "miniCockpitDetail"
    /// The Dashboard's authenticated AI usage quota strip.
    public static let usage = "usage"
}

/// What the dashboard tab asks the coordinator for.
///
/// The dashboard is the single owner of `TelemetryConsumer.dashboard`: it acquires
/// this set when it appears, re-acquires it when a card is toggled and releases it
/// when it disappears. Keeping the computation here makes that set testable.
public enum DashboardTelemetryDemand {
    /// Feeds shown by the dashboard whatever the user's card preferences.
    public static let baseFeeds: Set<TelemetryFeed> = [.system, .network, .process]

    public static func feeds(showUsageQuotas: Bool, showHiggsfield: Bool) -> Set<TelemetryFeed> {
        var feeds = baseFeeds
        if showUsageQuotas { feeds.formUnion([.usage, .openAICosts]) }
        if showHiggsfield { feeds.insert(.higgsfield) }
        return feeds
    }
}

/// Reference-counted hold on the dashboard demand.
///
/// SwiftUI can rebuild `DashboardView` and deliver the old instance's `onDisappear`
/// after the new instance's `onAppear`. Releasing on every disappear then dropped the
/// demand while the dashboard was on screen, stopping every feed (macmon included).
/// The demand is released only when the last visible instance goes away.
@MainActor
public final class DashboardTelemetryLease {
    public static let shared = DashboardTelemetryLease()

    private let coordinator: TelemetryCoordinator
    private var holders = 0

    public init(coordinator: TelemetryCoordinator? = nil) {
        self.coordinator = coordinator ?? .shared
    }

    /// Registers a visible dashboard and (re)declares the feeds it needs.
    public func hold(feeds: Set<TelemetryFeed>) {
        holders += 1
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: feeds)
    }

    /// Updates the feeds while a dashboard is visible (e.g. a card was toggled).
    public func update(feeds: Set<TelemetryFeed>) {
        guard holders > 0 else { return }
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: feeds)
    }

    /// Unregisters a dashboard; the demand goes away with the last one.
    public func drop() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 {
            coordinator.release(TelemetryConsumer.dashboard)
        }
    }
}
