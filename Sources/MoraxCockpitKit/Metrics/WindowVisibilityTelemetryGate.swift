import AppKit

/// Pauses one telemetry consumer while none of the windows showing it can be seen.
///
/// SwiftUI's `onDisappear` only fires when a window closes, not when it is
/// minimized, hidden with Cmd-H or fully covered by other windows, so the dashboard
/// used to keep `macmon`, `nettop` and `ps` running behind the user's back. The gate
/// follows the window's occlusion state instead and pauses the consumer through the
/// coordinator, which keeps the demand and applies its usual stop grace period.
/// Other consumers (menu bar, Mini Cockpit) are left alone.
@MainActor
public final class WindowVisibilityTelemetryGate {
    /// Gate for the main window's dashboard.
    public static let dashboard = WindowVisibilityTelemetryGate(consumer: TelemetryConsumer.dashboard)

    private struct TrackedWindow {
        let observers: [NSObjectProtocol]
        let isVisibleProvider: @MainActor () -> Bool
        var isVisible: Bool
    }

    private let consumer: String
    private let coordinator: TelemetryCoordinator
    private let notificationCenter: NotificationCenter
    private var trackedWindows: [ObjectIdentifier: TrackedWindow] = [:]

    public init(
        consumer: String,
        coordinator: TelemetryCoordinator = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.consumer = consumer
        self.coordinator = coordinator
        self.notificationCenter = notificationCenter
    }

    /// True while every tracked window is out of sight.
    public var isPaused: Bool {
        !trackedWindows.isEmpty && trackedWindows.values.allSatisfy { !$0.isVisible }
    }

    /// Whether a window is actually on screen for the user.
    public static func isVisible(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    /// Starts following `window`. Tracking the same window twice is a no-op.
    public func track(_ window: NSWindow) {
        track(window) { [weak window] in
            window.map(Self.isVisible) ?? false
        }
        // A window attached to its content is usually ordered in during the same
        // run-loop turn; read its real state once that has happened.
        let id = ObjectIdentifier(window)
        DispatchQueue.main.async { [weak self] in
            self?.refresh(id)
        }
    }

    /// Stops following `window`, e.g. when its content moves elsewhere or it closes.
    public func untrack(_ window: AnyObject) {
        untrack(id: ObjectIdentifier(window))
    }

    private func untrack(id: ObjectIdentifier) {
        guard let tracked = trackedWindows.removeValue(forKey: id) else { return }
        for observer in tracked.observers {
            notificationCenter.removeObserver(observer)
        }
        applyPauseState()
    }

    /// Core tracking, with the visibility check injected so it can be tested without
    /// a real window. The object starts as visible until a notification says otherwise.
    func track(_ object: AnyObject, isVisible: @escaping @MainActor () -> Bool) {
        let id = ObjectIdentifier(object)
        guard trackedWindows[id] == nil else { return }

        let refreshNames: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        var observers = refreshNames.map { name in
            notificationCenter.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(id) }
            }
        }
        observers.append(
            notificationCenter.addObserver(forName: NSWindow.willCloseNotification, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.untrack(id: id) }
            }
        )
        // Hiding the application orders every window out at once.
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh(id) }
                }
            )
        }

        trackedWindows[id] = TrackedWindow(observers: observers, isVisibleProvider: isVisible, isVisible: true)
        applyPauseState()
    }

    private func refresh(_ id: ObjectIdentifier) {
        guard var tracked = trackedWindows[id] else { return }
        let visible = tracked.isVisibleProvider()
        guard visible != tracked.isVisible else { return }
        tracked.isVisible = visible
        trackedWindows[id] = tracked
        applyPauseState()
    }

    private func applyPauseState() {
        coordinator.setPaused(isPaused, consumer: consumer)
    }
}
