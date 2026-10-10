import Foundation
import os
import Testing
@testable import MoraxCockpitKit

private final class OpenAICostsURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let (status, data) = Self.responses.isEmpty ? (500, Data()) : Self.responses.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func queue(_ items: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        responses = items.map { ($0.0, Data($0.1.utf8)) }
        requests = []
    }
}

@Suite("OpenAI costs service", .serialized)
@MainActor
struct OpenAICostsServiceTests {
    // 2027-01-15T08:00:00Z, month opens 2027-01-01T00:00:00Z
    private let now = Date(timeIntervalSince1970: 1_798_761_600 + 8 * 3_600 + 14 * 86_400)

    private func page(_ values: [Double], next: String? = nil) -> String {
        let results = values.map { #"{"amount":{"value":\#($0),"currency":"usd"}}"# }.joined(separator: ",")
        let more = next.map { #""has_more":true,"next_page":"\#($0)""# } ?? #""has_more":false,"next_page":null"#
        return #"{"object":"page","data":[{"object":"bucket","results":[\#(results)]}],\#(more)}"#
    }

    private func makeService(key: String? = "sk-admin-test", project: String? = nil,
                             clock: MutableTestClock? = nil) -> OpenAICostsService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAICostsURLProtocol.self]
        let service = OpenAICostsService(session: URLSession(configuration: configuration),
                                         now: { [now] in clock?.now ?? now })
        service.configure(keyProvider: { key }, projectIDProvider: { project })
        return service
    }

    @Test("sums billed amounts across buckets and pages since the UTC month start")
    func sumsAcrossPages() async {
        OpenAICostsURLProtocol.queue([(200, page([1.25, 2.5], next: "p2")), (200, page([10.0]))])
        let service = makeService(project: "proj_abc")

        await service.refresh()

        #expect(service.spend?.balanceSpendUsd == 13.75)
        #expect(service.spend?.balanceSpendSince == Date(timeIntervalSince1970: 1_798_761_600))
        #expect(service.lastError == nil)
        let urls = OpenAICostsURLProtocol.requests.compactMap { $0.url?.absoluteString }
        #expect(urls.count == 2)
        #expect(urls[0].contains("start_time=1798761600"))
        #expect(urls[0].contains("project_ids%5B%5D=proj_abc") || urls[0].contains("project_ids[]=proj_abc"))
        #expect(urls[1].contains("page=p2"))
        #expect(OpenAICostsURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-admin-test")
    }

    @Test("a refused key keeps the last good figure and reports the admin-key requirement")
    func refusedKeyKeepsLastFigure() async {
        OpenAICostsURLProtocol.queue([(200, page([4.0])), (401, "{}")])
        let service = makeService()

        await service.refresh()
        await service.refresh()

        #expect(service.spend?.balanceSpendUsd == 4.0)
        #expect(service.lastError?.contains("sk-admin") == true)
    }

    @Test("a restart within the poll interval serves the last figure instead of refetching")
    func restartWithinIntervalSkipsFetch() async throws {
        OpenAICostsURLProtocol.queue([(200, page([4.0])), (200, page([5.0]))])
        let clock = MutableTestClock(now)
        let service = makeService(clock: clock)
        let requestCount = { OpenAICostsURLProtocol.lock.withLock { OpenAICostsURLProtocol.requests.count } }
        // Every start and every fetch reads the key first, so the read count tells
        // when the restart reached its freshness decision and whether it refetched.
        let keyReads = OSAllocatedUnfairLock(initialState: 0)
        service.configure(keyProvider: {
            keyReads.withLock { $0 += 1 }
            return "sk-admin-test"
        }, projectIDProvider: { nil })
        let keyReadCount = { keyReads.withLock { $0 } }

        service.startMonitoring()
        #expect(await waitUntil { requestCount() == 1 })
        service.stopMonitoring()
        let keyReadsBeforeRestart = keyReadCount()

        clock.advance(by: 60)
        service.startMonitoring()
        #expect(await waitUntil { keyReadCount() >= keyReadsBeforeRestart + 1 })
        try await Task.sleep(for: .milliseconds(150))
        #expect(keyReadCount() == keyReadsBeforeRestart + 1)
        #expect(requestCount() == 1)
        #expect(service.spend?.balanceSpendUsd == 4.0)
        service.stopMonitoring()

        clock.advance(by: OpenAICostsService.pollingInterval)
        service.startMonitoring()
        #expect(await waitUntil { requestCount() == 2 })
        service.stopMonitoring()
    }

    @Test("without a key nothing is fetched and no spend is reported")
    func missingKeyReportsNothing() async {
        OpenAICostsURLProtocol.queue([])
        let service = makeService(key: nil)

        await service.refresh()

        #expect(service.spend == nil)
        #expect(OpenAICostsURLProtocol.requests.isEmpty)
    }

    @Test("billed OpenAI spend replaces the feed line but leaves ChatGPT and DeepSeek alone")
    func replacesOnlyOpenAIAPILine() {
        let since = Date(timeIntervalSince1970: 0)
        func line(_ provider: String, _ label: String) -> PaidApiSpend {
            PaidApiSpend(provider: provider, label: label, costUsd: 0, calls: 0, totalTokens: 0, since: since,
                         latestAt: nil, balanceUsd: nil, balanceCurrency: nil, balanceObservedAt: nil,
                         balanceAvailable: nil, balanceSpendUsd: nil, balanceSpendSince: nil)
        }
        let snapshot = UsageQuotaSnapshot(ok: true, capturedAt: since, gauges: [], paidApiMonthToDate: [
            line("deepseek", "DeepSeek API"), line("openai", "OpenAI API"), line("chatgpt", "ChatGPT"),
        ])
        let billed = OpenAICostsService.makeSpend(total: 42, since: since, observedAt: since)

        let merged = snapshot.replacingOpenAISpend(billed).paidApiMonthToDate

        #expect(merged.map(\.provider) == ["deepseek", "chatgpt", "openai"])
        #expect(merged.last?.balanceSpendUsd == 42)
    }
}
