import Foundation
import Observation

/// Exact per-session token totals resolved from a `muse export` document.
public struct MetaMuseTokenTotals: Sendable, Equatable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cachedTokens: Int = 0
    public var reasoningTokens: Int = 0

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cachedTokens: Int = 0, reasoningTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
    }

    public static func + (lhs: MetaMuseTokenTotals, rhs: MetaMuseTokenTotals) -> MetaMuseTokenTotals {
        MetaMuseTokenTotals(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cachedTokens: lhs.cachedTokens + rhs.cachedTokens,
            reasoningTokens: lhs.reasoningTokens + rhs.reasoningTokens
        )
    }
}

/// Resolves exact token usage for one on-disk session log.
///
/// Only `model_completed` events are counted: `goal_usage_attribution`
/// events carry the same quantities re-attributed to goals and would double
/// count. Reasoning tokens are reported inside output tokens by providers and
/// are tracked separately for display only, never added to spend.
public protocol MuseExportExecuting: Sendable {
    func exportUsage(sessionLog: URL) async throws -> MetaMuseTokenTotals
}

/// Production executor: runs `muse export --session <log> --out <tmp>` and
/// sums the `model_completed` usage blocks.
public struct MuseExportRunner: MuseExportExecuting {
    private let toolRegistry: ToolRegistry
    private let processRunner: ProcessRunner

    public init(
        toolRegistry: ToolRegistry = .shared,
        processRunner: ProcessRunner = .shared
    ) {
        self.toolRegistry = toolRegistry
        self.processRunner = processRunner
    }

    public func exportUsage(sessionLog: URL) async throws -> MetaMuseTokenTotals {
        guard let musePath = toolRegistry.resolveBinaryPath(name: "muse") else {
            throw MetaMuseExportError.cliUnavailable
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("metamuse-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outURL) }

        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: musePath),
            arguments: ["export", "--session", sessionLog.path, "--out", outURL.path],
            timeout: 30.0
        )
        guard result.isSuccess else {
            throw MetaMuseExportError.exportFailed(result.standardError)
        }
        return try Self.parseExport(at: outURL)
    }

    /// Sums `model_completed` usage blocks of an export document.
    static func parseExport(at url: URL) throws -> MetaMuseTokenTotals {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            throw MetaMuseExportError.unparseableExport
        }
        var totals = MetaMuseTokenTotals()
        for event in events {
            guard let envelope = event["envelope"] as? [String: Any],
                  let payload = envelope["payload"] as? [String: Any],
                  let inner = payload["event"] as? [String: Any],
                  (inner["kind"] as? String) == "model_completed",
                  let usage = inner["usage"] as? [String: Any] else { continue }
            totals.inputTokens += Self.intValue(usage["input_tokens"])
            totals.outputTokens += Self.intValue(usage["output_tokens"])
            totals.cachedTokens += Self.intValue(usage["cached_tokens"])
            totals.reasoningTokens += Self.intValue(usage["reasoning_tokens"])
        }
        return totals
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }
}

public enum MetaMuseExportError: Error, LocalizedError, Equatable {
    case cliUnavailable
    case exportFailed(String)
    case unparseableExport

    public var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            return "CLI `muse` introuvable dans le PATH."
        case .exportFailed(let stderr):
            return stderr.isEmpty ? "`muse export` a échoué." : stderr
        case .unparseableExport:
            return "Document d'export illisible."
        }
    }
}

/// Service singleton reporting Muse Code usage from the on-disk session logs.
///
/// Two layers, both local and credential-free:
/// - cheap scan of `session.jsonl` files (sessions, tool calls, models);
/// - exact token totals via `muse export` (input/output/cached/reasoning) plus
///   an estimated USD spend from the public Model API pricing (standard:
///   $1.25/$4.25 par million in/out, $0.15 cached input ; contributor:
///   $0.10/$0.20 — cached au tarif input faute de tarif publié).
///
/// Meta exposes no subscription-usage endpoint, so the window/weekly
/// percentages of `dev.meta.ai/usage` remain out of reach; this service tracks
/// everything observable locally instead of inventing them.
@MainActor
@Observable
public final class MetaMuseService: TelemetryFeedControlling {
    public static let shared = MetaMuseService()

    public static let pollingInterval: TimeInterval = 300.0 // 5 minutes
    public static let activityWindow: TimeInterval = 7 * 24 * 3_600 // 7 days

    public var state: MetaMuseState = .loading
    public private(set) var cachedSnapshot: MetaMuseSnapshot?
    public private(set) var isRunning = false
    public private(set) var isRefreshing = false

    private let fileManager: FileManager
    private let sessionsRoot: URL?
    private let exporter: MuseExportExecuting
    private let clock: @Sendable () -> Date

    private var pollingTask: Task<Void, Never>?
    private var inFlightRefreshTask: Task<MetaMuseSnapshot?, Never>?

    public init(
        fileManager: FileManager = .default,
        sessionsRoot: URL? = nil,
        exporter: MuseExportExecuting = MuseExportRunner(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        if let sessionsRoot {
            self.sessionsRoot = sessionsRoot
        } else {
            self.sessionsRoot = MetaMuseService.defaultSessionsRoot(fileManager: fileManager)
        }
        self.exporter = exporter
        self.clock = now
    }

    public static func defaultSessionsRoot(fileManager: FileManager = .default) -> URL? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent(".local/share/muse/sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }

    public var currentDate: Date {
        clock()
    }

    // MARK: - TelemetryFeedControlling

    public func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            await self.refresh()

            while !Task.isCancelled && self.isRunning {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollingInterval * 1_000_000_000))
                if !Task.isCancelled && self.isRunning {
                    await self.refresh()
                }
            }
        }
    }

    public func stopMonitoring() {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Recomputes the snapshot from the session logs, with deduplication.
    @discardableResult
    public func refresh() async -> MetaMuseSnapshot? {
        if let existing = inFlightRefreshTask {
            return await existing.value
        }

        isRefreshing = true
        let task = Task<MetaMuseSnapshot?, Never> { [weak self] () -> MetaMuseSnapshot? in
            guard let self = self else { return nil }
            return await self.performRefresh()
        }
        inFlightRefreshTask = task
        let snapshot = await task.value
        inFlightRefreshTask = nil
        isRefreshing = false
        return snapshot
    }

    private func performRefresh() async -> MetaMuseSnapshot? {
        guard let root = sessionsRoot,
              (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            let reason = "Dossier de sessions Muse introuvable — lancez `muse login` puis une session."
            self.state = .unavailable(reason)
            return nil
        }
        do {
            let now = clock()
            let aggregation = try Self.aggregate(
                sessionsRoot: root,
                fileManager: fileManager,
                now: now
            )
            var tokens = MetaMuseTokenTotals()
            var spendUSD = 0.0
            for file in aggregation.recentFiles {
                let fileTotals = try await exporter.exportUsage(sessionLog: file.url)
                tokens = tokens + fileTotals
                spendUSD += Self.estimatedSpend(for: fileTotals, modelID: file.modelID)
            }
            let snapshot = MetaMuseSnapshot(
                sessionsCount: aggregation.sessionsCount,
                toolCallsCount: aggregation.toolCallsCount,
                models: aggregation.models,
                lastActivityAt: aggregation.lastActivityAt,
                inputTokens: tokens.inputTokens,
                outputTokens: tokens.outputTokens,
                cachedTokens: tokens.cachedTokens,
                reasoningTokens: tokens.reasoningTokens,
                estimatedSpendUSD: spendUSD,
                capturedAt: now,
                isStale: false
            )
            self.cachedSnapshot = snapshot
            self.state = .live(snapshot)
            return snapshot
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let old = cachedSnapshot {
                let staleSnap = old.staleCopy()
                self.cachedSnapshot = staleSnap
                self.state = .stale(staleSnap, reason: reason)
            } else {
                self.state = .error(reason)
            }
            return nil
        }
    }

    /// Estimated USD spend for token totals under a model tier (public pricing).
    static func estimatedSpend(for totals: MetaMuseTokenTotals, modelID: String?) -> Double {
        let contributor = (modelID ?? "").contains("contributor")
        let inputRate = contributor ? 0.10 : 1.25
        let cachedRate = contributor ? 0.10 : 0.15
        let outputRate = contributor ? 0.20 : 4.25
        let uncachedInput = max(0, totals.inputTokens - totals.cachedTokens)
        return (Double(uncachedInput) * inputRate
            + Double(totals.cachedTokens) * cachedRate
            + Double(totals.outputTokens) * outputRate) / 1_000_000
    }

    // MARK: - Log aggregation (testable, synchronous)

    struct RecentFile: Equatable {
        let url: URL
        let modelID: String?
    }

    struct Aggregation: Equatable {
        var sessionsCount: Int = 0
        var toolCallsCount: Int = 0
        var models: [String] = []
        var lastActivityAt: Date?
        var recentFiles: [RecentFile] = []
    }

    /// Scans `session.jsonl` files under `sessionsRoot`, keeping only files
    /// touched inside the trailing 7-day window.
    static func aggregate(
        sessionsRoot: URL,
        fileManager: FileManager,
        now: Date
    ) throws -> Aggregation {
        var result = Aggregation()
        var modelSet = Set<String>()
        let windowStart = now.addingTimeInterval(-Self.activityWindow)

        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "session.jsonl" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let modified = values?.contentModificationDate, modified >= windowStart else { continue }

            result.sessionsCount += 1
            if let last = result.lastActivityAt {
                result.lastActivityAt = max(last, modified)
            } else {
                result.lastActivityAt = modified
            }

            var fileModel: String?
            var fileToolCalls = 0
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                for line in content.split(separator: "\n") {
                    guard let data = line.data(using: .utf8),
                          let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    guard let payloadType = record["payload_type"] as? String else { continue }
                    if payloadType == "tool_batch.effect.terminal" {
                        fileToolCalls += 1
                    } else if payloadType == "runtime.session.metadata",
                              let payload = record["payload"] as? [String: Any],
                              let entry = payload["record"] as? [String: Any],
                              let model = entry["model_id"] as? String {
                        fileModel = model
                        modelSet.insert(model)
                    }
                }
            }
            result.toolCallsCount += fileToolCalls
            result.recentFiles.append(RecentFile(url: fileURL, modelID: fileModel))
        }

        result.models = modelSet.sorted()
        return result
    }
}
