import Foundation
import Observation

@MainActor
@Observable
public final class UsageQuotaService: TelemetryFeedControlling {
    public static let shared = UsageQuotaService()
    public static let pollingInterval: TimeInterval = 300
    public static let requestTimeout: TimeInterval = 8
    public static let maximumBackoff: TimeInterval = 900

    public var state: UsageQuotaState = .disabled
    public private(set) var cachedSnapshot: UsageQuotaSnapshot?
    public private(set) var isRunning = false

    private let fileManager: FileManager
    private let session: URLSession
    private let clock: () -> Date
    private let cacheDirectory: URL?
    private var pollingTask: Task<Void, Never>?
    private var failureCount = 0
    /// Local time of the last successful fetch in this process (drives the restart freshness gate).
    private var lastSuccessAt: Date?
    private var baseURLProvider: () -> URL? = { AppSettings.shared.usageCockpitURL }
    private var keyProvider: @Sendable () -> String? = { UsageQuotaCredentials.read() }

    public init(fileManager: FileManager = .default, session: URLSession? = nil,
                now: @escaping () -> Date = Date.init, cacheDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.clock = now
        self.cacheDirectory = cacheDirectory
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        restoreCache()
    }

    public func configure(baseURLProvider: @escaping () -> URL?, keyProvider: @escaping @Sendable () -> String?) {
        self.baseURLProvider = baseURLProvider
        self.keyProvider = keyProvider
    }

    public func start() { startMonitoring() }
    public func stop() { stopMonitoring() }

    public func startMonitoring() {
        guard pollingTask == nil else { return }
        guard baseURLProvider() != nil else {
            state = .disabled
            return
        }
        isRunning = true
        if cachedSnapshot == nil { state = .loading }
        pollingTask = Task { [weak self] in
            guard let key = await self?.loadKey() else { return }
            guard let self, !Task.isCancelled else { return }
            guard !key.isEmpty else {
                self.state = .disabled
                self.stopMonitoring()
                return
            }
            await self.pollLoop()
        }
    }

    /// Reads the key off the main actor: a Keychain access prompt (e.g. after the
    /// app's signature changed) would otherwise freeze the whole UI until answered.
    private func loadKey() async -> String {
        let provider = keyProvider
        return await Task.detached(priority: .userInitiated) { provider() ?? "" }.value
    }

    /// Failures slow polling down (2x, 4x… the normal interval), capped at `maximumBackoff`.
    public var nextPollInterval: TimeInterval {
        guard failureCount > 0 else { return Self.pollingInterval }
        return min(Self.maximumBackoff, Self.pollingInterval * pow(2, Double(failureCount)))
    }

    /// The internal key may only travel over https, or plain http to the local machine.
    public static func isAllowedEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty else { return false }
        switch scheme {
        case "https": return true
        case "http": return loopbackHosts.contains(host)
        default: return false
        }
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    public var currentDate: Date { clock() }

    public func refreshLocalFreshness() {
        guard let snapshot = cachedSnapshot else { return }
        if case .restored = state { state = .restored(snapshot) }
    }

    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
    }

    private func pollLoop() async {
        let firstDelay = FeedFreshness.initialDelay(lastSuccessAt: lastSuccessAt, now: clock(), interval: Self.pollingInterval)
        if firstDelay > 0 { try? await Task.sleep(for: .seconds(firstDelay)) }
        if !Task.isCancelled { await refresh() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(nextPollInterval))
            if !Task.isCancelled { await refresh() }
        }
    }

    public func refresh() async {
        let key = await loadKey()
        guard let baseURL = baseURLProvider(), !key.isEmpty else {
            state = .disabled
            return
        }
        guard Self.isAllowedEndpoint(baseURL) else {
            state = .unreachable(Self.insecureEndpointMessage)
            return
        }
        var endpoint = baseURL
        endpoint.append(path: "api/usage/quotas")
        var request = URLRequest(url: endpoint, timeoutInterval: Self.requestTimeout)
        request.setValue(key, forHTTPHeaderField: "X-Internal-Key")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ServiceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let snapshot = try Self.decoder.decode(UsageQuotaSnapshot.self, from: data)
            failureCount = 0
            lastSuccessAt = clock()
            cachedSnapshot = snapshot
            state = .ready(snapshot)
            persist(snapshot)
        } catch {
            failureCount += 1
            let message = (error as? ServiceError)?.description ?? error.localizedDescription
            if let old = cachedSnapshot { state = .unreachable(messageWithCache(message, snapshot: old)) }
            else { state = .unreachable(message) }
        }
    }

    public static let insecureEndpointMessage = "URL du cockpit refusée : https requis (http seulement vers localhost)"

    private func messageWithCache(_ message: String, snapshot: UsageQuotaSnapshot) -> String {
        "\(message) — dernier relevé conservé du \(Self.displayDate.string(from: snapshot.capturedAt))"
    }

    nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            guard let date = fractional.date(from: value) ?? fallback.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }()

    private static let displayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var cacheURL: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return cacheDirectory ?? appSupport.appending(path: "MoraxGarage/usage-quotas.json")
    }

    private func persist(_ snapshot: UsageQuotaSnapshot) {
        guard let url = cacheURL else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch { TelemetryLogger.lifecycle.error("Usage quota cache write failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func restoreCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url), let snapshot = try? Self.decoder.decode(UsageQuotaSnapshot.self, from: data) else { return }
        cachedSnapshot = snapshot
        state = .restored(snapshot)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private enum ServiceError: Error, CustomStringConvertible {
        case httpStatus(Int)
        var description: String {
            switch self { case let .httpStatus(code): return code == 401 ? "Clé refusée (401)" : "Endpoint indisponible (HTTP \(code))" }
        }
    }
}
