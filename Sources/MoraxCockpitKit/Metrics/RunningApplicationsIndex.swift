import Foundation
import AppKit

/// Cached view of the applications currently running.
///
/// `NSWorkspace.runningApplications` walks every process on the main thread, which is
/// too expensive to repeat on every sampling tick. The list only changes when an
/// application launches or quits, so it is cached for a short while and invalidated
/// by the workspace notifications rather than polled.
@MainActor
final class RunningApplicationsIndex {
    static let shared = RunningApplicationsIndex()

    typealias Entry = (name: String, bundleURL: URL?)

    private var cached: [pid_t: Entry] = [:]
    private var lastRefresh: Date?
    private let timeToLive: TimeInterval

    // Kept alive for the lifetime of the process; this index is a singleton, so the
    // observers are never torn down.
    private var observers: [NSObjectProtocol] = []

    init(timeToLive: TimeInterval = 30) {
        self.timeToLive = timeToLive

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.invalidate() }
            }
            observers.append(observer)
        }
    }

    /// Returns the running applications, refreshing the cache when it has expired.
    func snapshot(now: Date = Date()) -> [pid_t: Entry] {
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < timeToLive, !cached.isEmpty {
            return cached
        }
        return refresh(now: now)
    }

    /// Forces the next `snapshot(now:)` to rebuild the cache.
    func invalidate() {
        lastRefresh = nil
    }

    @discardableResult
    private func refresh(now: Date) -> [pid_t: Entry] {
        var result: [pid_t: Entry] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName
                ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                ?? "App"
            result[app.processIdentifier] = (name: name, bundleURL: app.bundleURL)
        }
        cached = result
        lastRefresh = now
        return result
    }
}
