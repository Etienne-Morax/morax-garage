import Foundation
import Testing
@testable import MoraxCockpitKit

/// Thread-safe clock the tests move forward by hand.
final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) { value = start }

    var now: Date { lock.withLock { value } }

    func advance(by seconds: TimeInterval) { lock.withLock { value += seconds } }
}

/// Polls `condition` every 10 ms until it holds or `timeout` elapses.
@MainActor
func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Suite("Feed freshness gate")
struct FeedFreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("fetches immediately when nothing was fetched yet")
    func noPreviousFetch() {
        #expect(FeedFreshness.initialDelay(lastSuccessAt: nil, now: now, interval: 300) == 0)
    }

    @Test("waits only the remaining time when the last fetch is recent")
    func recentFetchWaitsRemainder() {
        let delay = FeedFreshness.initialDelay(lastSuccessAt: now.addingTimeInterval(-120), now: now, interval: 300)
        #expect(delay == 180)
    }

    @Test("fetches immediately when the last fetch is older than the interval")
    func oldFetchRefetches() {
        #expect(FeedFreshness.initialDelay(lastSuccessAt: now.addingTimeInterval(-301), now: now, interval: 300) == 0)
    }

    @Test("fetches immediately when the clock went backwards")
    func clockWentBackwards() {
        #expect(FeedFreshness.initialDelay(lastSuccessAt: now.addingTimeInterval(60), now: now, interval: 300) == 0)
    }
}
