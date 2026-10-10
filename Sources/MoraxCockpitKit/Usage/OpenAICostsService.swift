import Foundation
import Observation

/// Month-to-date OpenAI spend as billed by OpenAI (`GET /v1/organization/costs`).
///
/// The cockpit feed carries no OpenAI line, so the dashboard used to show a
/// hard-coded $0. This reads the same endpoint the NAS party app uses: it needs an
/// organization admin key and reports every billed request, not only the ones a
/// local counter saw. OpenAI exposes no remaining-credit endpoint to API keys, so
/// only the spend is shown.
@MainActor
@Observable
public final class OpenAICostsService: TelemetryFeedControlling {
    public static let shared = OpenAICostsService()
    public static let pollingInterval: TimeInterval = 300
    public static let requestTimeout: TimeInterval = 15
    public static let maximumPages = 10
    public static let projectIDDefaultsKey = "morax_openai_costs_project_id"
    public static let endpoint = URL(string: "https://api.openai.com/v1/organization/costs")!

    public private(set) var spend: PaidApiSpend?
    public private(set) var lastError: String?
    public private(set) var isRunning = false

    private let session: URLSession
    private let clock: () -> Date
    private var keyProvider: @Sendable () -> String? = { OpenAIAdminCredentials.read() }
    private var projectIDProvider: () -> String? = {
        UserDefaults.standard.string(forKey: OpenAICostsService.projectIDDefaultsKey)
    }
    private var pollingTask: Task<Void, Never>?
    /// Local time of the last successful fetch in this process (drives the restart freshness gate).
    private var lastSuccessAt: Date?

    public init(session: URLSession? = nil, now: @escaping () -> Date = Date.init) {
        self.clock = now
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public func configure(keyProvider: @escaping @Sendable () -> String?, projectIDProvider: @escaping () -> String?) {
        self.keyProvider = keyProvider
        self.projectIDProvider = projectIDProvider
    }

    public var isConfigured: Bool { keyProvider()?.isEmpty == false }

    private func loadKey() async -> String {
        let provider = keyProvider
        return await Task.detached(priority: .userInitiated) { provider() ?? "" }.value
    }

    // MARK: - TelemetryFeedControlling

    public func startMonitoring() {
        guard pollingTask == nil else { return }
        isRunning = true
        let firstDelay = FeedFreshness.initialDelay(lastSuccessAt: lastSuccessAt, now: clock(), interval: Self.pollingInterval)
        pollingTask = Task { [weak self] in
            // Checked off the main actor: a Keychain prompt must not freeze the UI.
            guard let key = await self?.loadKey(), !Task.isCancelled else { return }
            guard !key.isEmpty else {
                self?.stopMonitoring()
                return
            }
            if firstDelay > 0 { try? await Task.sleep(for: .seconds(firstDelay)) }
            if !Task.isCancelled { await self?.refresh() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollingInterval))
                if !Task.isCancelled { await self?.refresh() }
            }
        }
    }

    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
    }

    /// Fetches the billed total since the first day of the current UTC month.
    public func refresh() async {
        let key = await loadKey()
        guard !key.isEmpty else {
            spend = nil
            lastError = nil
            return
        }
        let now = clock()
        let since = Self.monthStartUTC(for: now)
        do {
            let total = try await fetchTotal(key: key, since: since)
            spend = Self.makeSpend(total: total, since: since, observedAt: now)
            lastError = nil
            lastSuccessAt = now
        } catch {
            // Keep the last good figure: a transient failure must not reset it to $0.
            lastError = (error as? CostsError)?.description ?? error.localizedDescription
            TelemetryLogger.lifecycle.error("OpenAI costs fetch failed: \(self.lastError ?? "", privacy: .public)")
        }
    }

    private func fetchTotal(key: String, since: Date) async throws -> Double {
        let baseURL = Self.requestURL(since: since, projectID: projectIDProvider(), page: nil)
        var url = baseURL
        var total = 0.0
        for _ in 0..<Self.maximumPages {
            var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else { throw CostsError.httpStatus(status) }
            let page = try Self.parsePage(data)
            total += page.total
            guard let next = page.nextPage else { break }
            url = Self.requestURL(since: since, projectID: projectIDProvider(), page: next)
        }
        return (total * 10_000).rounded() / 10_000
    }

    // MARK: - Pure helpers (tested)

    struct CostsPage: Equatable {
        let total: Double
        let nextPage: String?
    }

    static func parsePage(_ data: Data) throws -> CostsPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = root["data"] as? [[String: Any]] else {
            throw CostsError.unparseable
        }
        var total = 0.0
        for bucket in buckets {
            for result in bucket["results"] as? [[String: Any]] ?? [] {
                let amount = result["amount"] as? [String: Any]
                total += (amount?["value"] as? NSNumber)?.doubleValue ?? 0
            }
        }
        let hasMore = (root["has_more"] as? Bool) ?? false
        let next = root["next_page"] as? String
        return CostsPage(total: total, nextPage: hasMore ? next : nil)
    }

    static func requestURL(since: Date, projectID: String?, page: String?) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "start_time", value: String(Int(since.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        if let projectID = projectID?.trimmingCharacters(in: .whitespaces), !projectID.isEmpty {
            items.append(URLQueryItem(name: "project_ids[]", value: projectID))
        }
        if let page { items.append(URLQueryItem(name: "page", value: page)) }
        components.queryItems = items
        return components.url!
    }

    /// Costs are bucketed by UTC day, so the window must open on a UTC midnight.
    static func monthStartUTC(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    static func makeSpend(total: Double, since: Date, observedAt: Date) -> PaidApiSpend {
        PaidApiSpend(
            provider: "openai",
            label: "OpenAI API",
            costUsd: total,
            calls: 0,
            totalTokens: 0,
            since: since,
            latestAt: nil,
            balanceUsd: nil,
            balanceCurrency: "USD",
            balanceObservedAt: observedAt,
            balanceAvailable: nil,
            balanceSpendUsd: total,
            balanceSpendSince: since
        )
    }

    enum CostsError: Error, CustomStringConvertible {
        case httpStatus(Int)
        case unparseable

        var description: String {
            switch self {
            case .httpStatus(401), .httpStatus(403):
                return "Clé refusée — une clé admin (sk-admin-…) est requise"
            case .httpStatus(let code):
                return "API OpenAI indisponible (HTTP \(code))"
            case .unparseable:
                return "Réponse OpenAI illisible"
            }
        }
    }
}

extension UsageQuotaSnapshot {
    /// Replaces any OpenAI API line of the cockpit feed with the billed figure.
    /// ChatGPT / Codex subscriptions are separate products and are left alone.
    public func replacingOpenAISpend(_ spend: PaidApiSpend?) -> UsageQuotaSnapshot {
        guard let spend else { return self }
        let others = paidApiMonthToDate.filter { !PaidApiSpend.isOpenAIAPI($0) }
        return UsageQuotaSnapshot(ok: ok, capturedAt: capturedAt, gauges: gauges, paidApiMonthToDate: others + [spend])
    }
}

extension PaidApiSpend {
    public static func isOpenAIAPI(_ spend: PaidApiSpend) -> Bool {
        let text = (spend.provider + " " + spend.label).lowercased()
        return text.contains("openai") && !text.contains("chatgpt") && !text.contains("codex")
    }
}
