import Foundation

/// Cache-first scheduling for slow polled feeds (quotas, OpenAI costs, Higgsfield).
///
/// Feeds are stopped a few seconds after their last consumer leaves and restarted on
/// return. A restart must serve the value fetched less than one poll interval ago
/// instead of refetching it, so the first fetch waits for the remaining time.
public enum FeedFreshness {
    /// Seconds to wait before the first fetch after a (re)start: zero when nothing was
    /// fetched yet, the last fetch is older than `interval`, or the clock went backwards.
    public static func initialDelay(lastSuccessAt: Date?, now: Date, interval: TimeInterval) -> TimeInterval {
        guard let lastSuccessAt else { return 0 }
        let age = now.timeIntervalSince(lastSuccessAt)
        guard age >= 0 else { return 0 }
        return max(0, interval - age)
    }
}
