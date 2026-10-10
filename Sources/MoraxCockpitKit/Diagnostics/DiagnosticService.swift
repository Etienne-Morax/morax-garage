import Foundation
import Observation

@Observable
@MainActor
public final class DiagnosticService {
    public static let shared = DiagnosticService()
    public private(set) var findings: [DiagnosticFinding] = []
    public private(set) var historyRecordCount = 0
    public private(set) var historyAvailable = false

    public private(set) var dismissedFindingIDs: Set<String> = []

    private let engine = DiagnosticEngine()
    private let history: TelemetryHistoryStore
    private var previousSnapshot: SystemSnapshot?
    private var previousProcesses: ProcessSnapshot?
    private var lastPersistedAt: Date?
    private var findingsByCategory: [DiagnosticCategory: [DiagnosticFinding]] = [:]
    /// 24 h RAM baselines per process identity, recomputed only when process history changes.
    private var processBaselines: [String: HistoryStatistics] = [:]
    private var isHistoryLoaded = false
    private var historyLoadTask: Task<Void, Never>?
    // Latest samples received before the history finished loading, persisted once it has.
    private var pendingSystemRecord: TelemetryHistoryRecord?
    private var pendingProcessRecord: ProcessHistoryRecord?
    private var pendingCacheRecord: CacheHistoryRecord?

    public init(history: TelemetryHistoryStore = TelemetryHistoryStore()) {
        self.history = history
        if let file = history.loadWithoutDecoding() {
            applyLoadedHistory(file)
            return
        }
        // Decoding the history file can take 100+ ms: keep it off the main actor.
        historyLoadTask = Task { [weak self] in
            let file = await Task.detached(priority: .utility) { history.load() }.value
            self?.applyLoadedHistory(file)
        }
    }

    /// Waits until the persisted history has been loaded in the background.
    public func waitForHistoryLoad() async {
        await historyLoadTask?.value
    }

    public func dismissFinding(id: String) {
        dismissedFindingIDs.insert(id)
        recomputeFindings()
    }

    public func dismissAllFindings() {
        for finding in findingsByCategory.values.flatMap({ $0 }) {
            dismissedFindingIDs.insert(finding.id)
        }
        recomputeFindings()
    }

    public func ingest(_ snapshot: SystemSnapshot) {
        let record = TelemetryHistoryRecord(timestamp: snapshot.timestamp, cpuUsage: snapshot.cpuUsage,
            memoryPressure: snapshot.memoryPressure, ramUsed: snapshot.ramUsed,
            compressedMemory: snapshot.compressedMemory, swapUsed: snapshot.swapUsed,
            diskUsed: snapshot.diskVolumes.first?.usedBytes, cpuTemp: snapshot.cpuTemp)
        if isHistoryLoaded {
            persistSystemRecord(record)
        } else {
            pendingSystemRecord = record
        }
        replaceFindings(for: [.memory, .thermal], with: engine.evaluate(DiagnosticInput(now: snapshot.timestamp,
            memoryPressure: snapshot.memoryPressure, currentSystem: snapshot, previousSystem: previousSnapshot)))
        previousSnapshot = snapshot
    }

    public func ingestProcesses(_ snapshot: ProcessSnapshot) {
        let entries = snapshot.topRamApps.map { process in
            ProcessHistoryEntry(identity: Self.identity(of: process), name: process.name,
                                bundlePath: process.bundlePath, cpuPercent: process.cpuPercent, ramBytes: process.ramBytes)
        }
        let record = ProcessHistoryRecord(timestamp: snapshot.timestamp, entries: entries)
        if isHistoryLoaded {
            let didAppend = history.appendProcessSnapshot(record, now: snapshot.timestamp)
            refreshProcessBaselines(for: snapshot, force: didAppend)
        } else {
            pendingProcessRecord = record
        }
        replaceFindings(for: [.process], with: engine.evaluate(DiagnosticInput(now: snapshot.timestamp, memoryPressure: previousSnapshot?.memoryPressure,
            currentSystem: previousSnapshot, previousSystem: nil, currentProcesses: snapshot, previousProcesses: previousProcesses,
            processBaselines: processBaselines)))
        previousProcesses = snapshot
    }

    public func ingestCache(_ snapshot: CacheSnapshot) {
        let categories: [String: Int64] = ["resolve": snapshot.resolveSizeBytes, "lightroom": snapshot.lightroomSizeBytes,
            "photoshop": snapshot.photoshopSizeBytes, "captureOne": snapshot.captureOneSizeBytes,
            "cloud": snapshot.cloudSizeBytes, "browsers": snapshot.browsersSizeBytes, "system": snapshot.systemSizeBytes]
        let record = CacheHistoryRecord(timestamp: snapshot.timestamp, categories: categories)
        var baselines: [String: HistoryStatistics] = [:]
        if isHistoryLoaded {
            _ = history.appendCacheSnapshot(record, now: snapshot.timestamp)
            baselines = Dictionary(uniqueKeysWithValues: categories.keys.map { key in
                (key, history.cacheStatistics(category: key, since: snapshot.timestamp.addingTimeInterval(-TelemetryHistoryStore.aggregateRetention), now: snapshot.timestamp))
            })
        } else {
            pendingCacheRecord = record
        }
        replaceFindings(for: [.storage], with: engine.evaluate(DiagnosticInput(now: snapshot.timestamp, currentSystem: previousSnapshot,
            cacheSnapshot: snapshot, cacheBaselines: baselines)))
    }

    public func clearForTesting() {
        findings = []
        findingsByCategory = [:]
        dismissedFindingIDs = []
        previousSnapshot = nil
        previousProcesses = nil
        processBaselines = [:]
    }

    private func applyLoadedHistory(_ file: TelemetryHistoryFile) {
        isHistoryLoaded = true
        lastPersistedAt = file.records.last?.timestamp
        updateHistoryRecordCount(file.records.count)
        if let record = pendingSystemRecord {
            pendingSystemRecord = nil
            persistSystemRecord(record)
        }
        if let record = pendingProcessRecord {
            pendingProcessRecord = nil
            _ = history.appendProcessSnapshot(record, now: record.timestamp)
        }
        if let record = pendingCacheRecord {
            pendingCacheRecord = nil
            _ = history.appendCacheSnapshot(record, now: record.timestamp)
        }
    }

    private func persistSystemRecord(_ record: TelemetryHistoryRecord) {
        if let lastPersistedAt, record.timestamp.timeIntervalSince(lastPersistedAt) < TelemetryHistoryStore.minimumWriteInterval { return }
        guard history.append(record, now: record.timestamp) else { return }
        lastPersistedAt = record.timestamp
        updateHistoryRecordCount(history.load().records.count)
    }

    private func updateHistoryRecordCount(_ count: Int) {
        historyRecordCount = count
        historyAvailable = count > 0
    }

    private func refreshProcessBaselines(for snapshot: ProcessSnapshot, force: Bool) {
        let identities = snapshot.topRamApps.map(Self.identity(of:))
        guard force || identities.contains(where: { processBaselines[$0] == nil }) else { return }
        let since = snapshot.timestamp.addingTimeInterval(-24 * 60 * 60)
        processBaselines = Dictionary(identities.map { identity in
            (identity, history.processMemoryStatistics(identity: identity, since: since, now: snapshot.timestamp))
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func identity(of process: ProcessResourceUsage) -> String {
        (process.bundlePath ?? process.name).lowercased()
    }

    private func replaceFindings(for categories: Set<DiagnosticCategory>, with newFindings: [DiagnosticFinding]) {
        for category in categories {
            findingsByCategory[category] = newFindings.filter { $0.category == category }
        }
        recomputeFindings()
    }

    private func recomputeFindings() {
        findings = findingsByCategory.values.flatMap { $0 }
            .filter { !dismissedFindingIDs.contains($0.id) }
            .sorted {
                if $0.severity != $1.severity { return $0.severity > $1.severity }
                return $0.id < $1.id
            }
    }
}
