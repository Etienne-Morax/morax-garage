import Foundation
import os
import Testing
@testable import MoraxCockpitKit

private final class UsageQuotaURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let status = Self.statusCode
        let data = Self.responseData
        Self.requests.append(request)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func respond(status: Int, data: Data) {
        lock.lock(); defer { lock.unlock() }
        statusCode = status
        responseData = data
        requests = []
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }
}

@Suite("Usage quota service", .serialized)
@MainActor
struct UsageQuotaServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("200 produces ready and writes the cache")
    func successWritesCache() async throws {
        let directory = try makeDirectory()
        let snapshot = makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(snapshot))
        let service = makeService(directory: directory)
        await service.refresh()
        #expect(service.state == .ready(snapshot))
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("401 preserves the previous cache and reports the key error")
    func unauthorizedPreservesCache() async throws {
        let directory = try makeDirectory()
        let snapshot = makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(snapshot))
        let first = makeService(directory: directory)
        await first.refresh()
        UsageQuotaURLProtocol.respond(status: 401, data: Data())
        let second = makeService(directory: directory)
        await second.refresh()
        guard case .unreachable(let message) = second.state else {
            Issue.record("expected unreachable state")
            return
        }
        #expect(message.contains("Clé refusée (401)"))
        #expect(second.cachedSnapshot == snapshot)
    }

    @Test("network failure keeps the cached snapshot and exposes its local age")
    func networkFailureKeepsCache() async throws {
        let directory = try makeDirectory()
        let snapshot = makeSnapshot(capturedAt: now.addingTimeInterval(-3 * 3_600), resetAt: now.addingTimeInterval(3_600))
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(snapshot))
        let first = makeService(directory: directory)
        await first.refresh()
        UsageQuotaURLProtocol.respond(status: 503, data: Data())
        let second = makeService(directory: directory)
        await second.refresh()
        guard case .unreachable = second.state else {
            Issue.record("expected unreachable state")
            return
        }
        #expect(second.cachedSnapshot == snapshot)
        #expect(snapshot.isLocallyStale(at: now))
    }

    @Test("old and recent disk snapshots are restored, never ready")
    func restoredSnapshotsAreOffline() throws {
        let oldDirectory = try makeDirectory()
        let old = makeSnapshot(capturedAt: now.addingTimeInterval(-3 * 3_600), resetAt: now.addingTimeInterval(3_600))
        try encoded(old).write(to: oldDirectory)
        let oldService = makeService(directory: oldDirectory)
        #expect(oldService.state == .restored(old))
        #expect(old.isLocallyStale(at: now))

        let recentDirectory = try makeDirectory()
        let recent = makeSnapshot(capturedAt: now.addingTimeInterval(-600), resetAt: now.addingTimeInterval(3_600))
        try encoded(recent).write(to: recentDirectory)
        let recentService = makeService(directory: recentDirectory)
        #expect(recentService.state == .restored(recent))
        #expect(!recent.isLocallyStale(at: now))
    }

    @Test("a closed reset makes a recent snapshot stale")
    func overdueResetIsStale() {
        let snapshot = makeSnapshot(capturedAt: now.addingTimeInterval(-60), resetAt: now.addingTimeInterval(-1_800))
        #expect(snapshot.isLocallyStale(at: now))
        #expect(snapshot.gauges[0].worst.localResetLabel(snapshotIsStale: true, at: now).isEmpty)
    }

    @Test("backoff slows polling below the normal rate, caps, then resets after success")
    func backoffGrowsAndResets() async throws {
        let service = makeService(directory: try makeDirectory())
        UsageQuotaURLProtocol.respond(status: 503, data: Data())
        await service.refresh()
        #expect(service.nextPollInterval == 2 * UsageQuotaService.pollingInterval)
        await service.refresh()
        #expect(service.nextPollInterval == UsageQuotaService.maximumBackoff)
        await service.refresh()
        #expect(service.nextPollInterval == UsageQuotaService.maximumBackoff)
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))))
        await service.refresh()
        #expect(service.nextPollInterval == UsageQuotaService.pollingInterval)
    }

    @Test("a restart within the poll interval serves the cache instead of refetching")
    func restartWithinIntervalSkipsFetch() async throws {
        let clock = MutableTestClock(now)
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))))
        let service = makeService(directory: try makeDirectory(), clock: clock)
        // Every start and every fetch reads the key first, so the read count tells
        // when the restart reached its freshness decision and whether it refetched.
        let keyReads = OSAllocatedUnfairLock(initialState: 0)
        service.configure(baseURLProvider: { URL(string: "https://garage.test") }, keyProvider: {
            keyReads.withLock { $0 += 1 }
            return "test-key"
        })
        let keyReadCount = { keyReads.withLock { $0 } }

        service.startMonitoring()
        #expect(await waitUntil { UsageQuotaURLProtocol.requestCount == 1 })
        service.stopMonitoring()
        let keyReadsBeforeRestart = keyReadCount()

        clock.advance(by: 60)
        service.startMonitoring()
        #expect(await waitUntil { keyReadCount() >= keyReadsBeforeRestart + 1 })
        try await Task.sleep(for: .milliseconds(150))
        #expect(keyReadCount() == keyReadsBeforeRestart + 1)
        #expect(UsageQuotaURLProtocol.requestCount == 1)
        service.stopMonitoring()

        clock.advance(by: UsageQuotaService.pollingInterval)
        service.startMonitoring()
        #expect(await waitUntil { UsageQuotaURLProtocol.requestCount == 2 })
        service.stopMonitoring()
    }

    @Test("the Keychain key is read off the main thread so an access prompt cannot freeze the UI")
    func keyIsReadOffMainThread() async throws {
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))))
        let service = makeService(directory: try makeDirectory())
        let readOnMain = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        service.configure(baseURLProvider: { URL(string: "https://garage.test") }, keyProvider: {
            readOnMain.withLock { $0.append(Thread.isMainThread) }
            return "test-key"
        })

        service.startMonitoring()
        #expect(await waitUntil { UsageQuotaURLProtocol.requestCount == 1 })
        service.stopMonitoring()

        let reads = readOnMain.withLock { $0 }
        #expect(!reads.isEmpty)
        #expect(reads.allSatisfy { !$0 })
    }

    @Test("the internal key is never sent to a plain http host")
    func refusesPlainHTTPHost() async throws {
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))))
        let service = makeService(directory: try makeDirectory(), baseURL: "http://garage.example.com")
        await service.refresh()
        #expect(UsageQuotaURLProtocol.requestCount == 0)
        guard case .unreachable(let message) = service.state else {
            Issue.record("expected unreachable state, got \(service.state)")
            return
        }
        #expect(message.contains("https"))
    }

    @Test("loopback http is allowed for local development")
    func allowsLoopbackHTTP() async throws {
        let snapshot = makeSnapshot(capturedAt: now, resetAt: now.addingTimeInterval(3_600))
        UsageQuotaURLProtocol.respond(status: 200, data: try encoded(snapshot))
        let service = makeService(directory: try makeDirectory(), baseURL: "http://127.0.0.1:8080")
        await service.refresh()
        #expect(UsageQuotaURLProtocol.requestCount == 1)
        #expect(UsageQuotaURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Internal-Key") == "test-key")
        #expect(service.state == .ready(snapshot))
    }

    @Test("endpoint policy accepts https and loopback http only")
    func endpointPolicy() throws {
        let allowed = ["https://garage.test", "https://usage.example.com", "http://localhost:3000", "http://127.0.0.1", "http://[::1]:8080"]
        let refused = ["http://garage.example.com", "http://192.168.1.10", "http://garage.local", "ftp://garage.test", "file:///tmp/x", "https://"]
        for text in allowed { #expect(UsageQuotaService.isAllowedEndpoint(try #require(URL(string: text))), "\(text)") }
        for text in refused {
            guard let url = URL(string: text) else { continue }
            #expect(!UsageQuotaService.isAllowedEndpoint(url), "\(text)")
        }
    }

    private func makeService(directory: URL, clock: MutableTestClock? = nil,
                             baseURL: String = "https://garage.test") -> UsageQuotaService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageQuotaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let fixedNow = now
        let service = UsageQuotaService(fileManager: .default, session: session,
                                        now: { clock?.now ?? fixedNow }, cacheDirectory: directory)
        service.configure(baseURLProvider: { URL(string: baseURL) }, keyProvider: { "test-key" })
        return service
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        try Data().write(to: directory)
        return directory
    }

    private func makeSnapshot(capturedAt: Date, resetAt: Date) -> UsageQuotaSnapshot {
        let window = QuotaWindow(windowMinutes: 300, label: "5 heures", usedPercent: 42, remainingPercent: 58,
                                 resetsAt: resetAt, observedAt: capturedAt, tone: .ok,
                                 resetLabel: "reset dans 1 h", resetAtLabel: "26 août, 12:00")
        let gauge = ProviderQuotaGauge(provider: "claude", label: "Claude Max", planType: "Max",
                                       windows: [window], worst: window, outer: window, inner: nil,
                                       tone: .ok, observedAt: capturedAt, stale: false, observedLabel: "relevé récent")
        return UsageQuotaSnapshot(ok: true, capturedAt: capturedAt, gauges: [gauge], paidApiMonthToDate: [])
    }

    private func encoded(_ snapshot: UsageQuotaSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }
}
