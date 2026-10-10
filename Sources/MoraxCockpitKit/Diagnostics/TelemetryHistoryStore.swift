import Foundation
import os

public struct TelemetryHistoryRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpuUsage: Double?
    public let memoryPressure: MemoryPressureState?
    public let ramUsed: Int64?
    public let compressedMemory: Int64?
    public let swapUsed: Int64?
    public let diskUsed: Int64?
    public let cpuTemp: Double?
    public let sampleCount: Int
    public let ramUsedMinimum: Int64?
    public let ramUsedMaximum: Int64?
    public let cpuUsageMinimum: Double?
    public let cpuUsageMaximum: Double?

    private enum CodingKeys: String, CodingKey {
        case timestamp, cpuUsage, memoryPressure, ramUsed, compressedMemory, swapUsed, diskUsed, cpuTemp
        case sampleCount, ramUsedMinimum, ramUsedMaximum, cpuUsageMinimum, cpuUsageMaximum
    }

    public init(timestamp: Date, cpuUsage: Double? = nil, memoryPressure: MemoryPressureState? = nil,
                ramUsed: Int64? = nil, compressedMemory: Int64? = nil, swapUsed: Int64? = nil,
                diskUsed: Int64? = nil, cpuTemp: Double? = nil, sampleCount: Int = 1,
                ramUsedMinimum: Int64? = nil, ramUsedMaximum: Int64? = nil,
                cpuUsageMinimum: Double? = nil, cpuUsageMaximum: Double? = nil) {
        self.timestamp = timestamp; self.cpuUsage = cpuUsage; self.memoryPressure = memoryPressure
        self.ramUsed = ramUsed; self.compressedMemory = compressedMemory; self.swapUsed = swapUsed
        self.diskUsed = diskUsed; self.cpuTemp = cpuTemp; self.sampleCount = max(1, sampleCount)
        self.ramUsedMinimum = ramUsedMinimum ?? ramUsed; self.ramUsedMaximum = ramUsedMaximum ?? ramUsed
        self.cpuUsageMinimum = cpuUsageMinimum ?? cpuUsage; self.cpuUsageMaximum = cpuUsageMaximum ?? cpuUsage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(timestamp: try c.decode(Date.self, forKey: .timestamp),
            cpuUsage: try c.decodeIfPresent(Double.self, forKey: .cpuUsage),
            memoryPressure: try c.decodeIfPresent(MemoryPressureState.self, forKey: .memoryPressure),
            ramUsed: try c.decodeIfPresent(Int64.self, forKey: .ramUsed),
            compressedMemory: try c.decodeIfPresent(Int64.self, forKey: .compressedMemory),
            swapUsed: try c.decodeIfPresent(Int64.self, forKey: .swapUsed),
            diskUsed: try c.decodeIfPresent(Int64.self, forKey: .diskUsed),
            cpuTemp: try c.decodeIfPresent(Double.self, forKey: .cpuTemp),
            sampleCount: try c.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 1,
            ramUsedMinimum: try c.decodeIfPresent(Int64.self, forKey: .ramUsedMinimum),
            ramUsedMaximum: try c.decodeIfPresent(Int64.self, forKey: .ramUsedMaximum),
            cpuUsageMinimum: try c.decodeIfPresent(Double.self, forKey: .cpuUsageMinimum),
            cpuUsageMaximum: try c.decodeIfPresent(Double.self, forKey: .cpuUsageMaximum))
    }
}

public struct ProcessHistoryEntry: Codable, Equatable, Sendable {
    public let identity: String
    public let name: String
    public let bundlePath: String?
    public let cpuPercent: Double
    public let ramBytes: Int64

    public init(identity: String, name: String, bundlePath: String?, cpuPercent: Double, ramBytes: Int64) {
        self.identity = identity; self.name = name; self.bundlePath = bundlePath
        self.cpuPercent = max(0, cpuPercent); self.ramBytes = max(0, ramBytes)
    }
}

public struct ProcessHistoryRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let entries: [ProcessHistoryEntry]
    public init(timestamp: Date, entries: [ProcessHistoryEntry]) { self.timestamp = timestamp; self.entries = Array(entries.prefix(5)) }
}

public struct CacheHistoryRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let categories: [String: Int64]
    public init(timestamp: Date, categories: [String: Int64]) { self.timestamp = timestamp; self.categories = categories.mapValues { max(0, $0) } }
}

public struct TelemetryHistoryFile: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public let version: Int
    public var records: [TelemetryHistoryRecord]
    public var processRecords: [ProcessHistoryRecord]
    public var cacheRecords: [CacheHistoryRecord]

    public init(version: Int = Self.currentVersion, records: [TelemetryHistoryRecord] = [],
                processRecords: [ProcessHistoryRecord] = [], cacheRecords: [CacheHistoryRecord] = []) {
        self.version = version; self.records = records; self.processRecords = processRecords; self.cacheRecords = cacheRecords
    }

    private enum CodingKeys: String, CodingKey { case version, records, processRecords, cacheRecords }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == 1 || decodedVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Unsupported history version")
        }
        version = Self.currentVersion
        records = try container.decodeIfPresent([TelemetryHistoryRecord].self, forKey: .records) ?? []
        processRecords = decodedVersion == 1 ? [] : (try container.decodeIfPresent([ProcessHistoryRecord].self, forKey: .processRecords) ?? [])
        cacheRecords = decodedVersion == 1 ? [] : (try container.decodeIfPresent([CacheHistoryRecord].self, forKey: .cacheRecords) ?? [])
    }
}

public struct HistoryStatistics: Equatable, Sendable {
    public let count: Int
    public let average: Double?
    public let median: Double?
    public let maximum: Double?
    public let delta: Double?
    public let window: TimeInterval

    public init(values: [Double], window: TimeInterval) {
        count = values.count; self.window = window
        guard !values.isEmpty else { average = nil; median = nil; maximum = nil; delta = nil; return }
        average = values.reduce(0, +) / Double(values.count); maximum = values.max()
        let sorted = values.sorted(); median = sorted[sorted.count / 2]; delta = values.last! - values.first!
    }
}

/// Local, versioned and bounded history. Recent samples remain detailed while older
/// samples are deterministically compacted into numeric summaries.
///
/// Reads and appends operate on a process-wide in-memory copy; encoding and the atomic
/// file write happen later on a background queue, coalesced across streams.
public struct TelemetryHistoryStore: Sendable {
    public static let detailedRetention: TimeInterval = 24 * 60 * 60
    public static let intermediateRetention: TimeInterval = 7 * 24 * 60 * 60
    public static let aggregateRetention: TimeInterval = 30 * 24 * 60 * 60
    public static let minimumWriteInterval: TimeInterval = 60
    public static let intermediateBucket: TimeInterval = 5 * 60
    public static let aggregateBucket: TimeInterval = 60 * 60
    public static let maxRecords = 10_000
    public static let maxProcessRecords = 1_000
    public static let maxCacheRecords = 1_000
    /// A full prune (filter, sort, bucket compaction) runs at most once per interval per
    /// stream; appends in between only append, or trim the head once over capacity.
    public static let pruneInterval: TimeInterval = 15 * 60
    /// Appends landing within this delay are persisted by a single write.
    public static let defaultWriteCoalescingDelay: TimeInterval = 60

    public let fileURL: URL
    public let writeCoalescingDelay: TimeInterval
    private let decoder = JSONDecoder()
    private let cache: TelemetryHistoryCache
    private static let sharedCache = TelemetryHistoryCache()
    private static let logger = Logger(subsystem: "com.morax.garage", category: "TelemetryHistory")

    public init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MoraxGarage/telemetry-history.json"),
                writeCoalescingDelay: TimeInterval = Self.defaultWriteCoalescingDelay) {
        self.init(fileURL: fileURL, writeCoalescingDelay: writeCoalescingDelay, cache: Self.sharedCache)
    }

    /// A separate `cache` stands in for another process's memory in tests.
    init(fileURL: URL, writeCoalescingDelay: TimeInterval, cache: TelemetryHistoryCache) {
        self.fileURL = fileURL
        self.writeCoalescingDelay = writeCoalescingDelay
        self.cache = cache
    }

    public static func clearCacheForTesting() {
        sharedCache.clear()
    }

    /// Persists every pending history write immediately. Call before the process exits.
    public static func flushPendingWrites() {
        TelemetryHistoryWriter.shared.flush(cache: sharedCache)
    }

    /// Waits for queued writes of this file and persists anything still pending.
    public func flush() {
        TelemetryHistoryWriter.shared.flush([fileURL], cache: cache)
    }

    /// Returns the history when it is available without decoding the file: already in
    /// memory, or no file on disk yet. Returns nil when `load()` would have to decode.
    public func loadWithoutDecoding() -> TelemetryHistoryFile? {
        if let cached = cache.get(for: fileURL) { return cached }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return load()
    }

    public func load() -> TelemetryHistoryFile {
        if let cached = cache.get(for: fileURL) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = TelemetryHistoryFile()
            cache.set(empty, for: fileURL)
            return empty
        }
        do {
            let decoded = try decoder.decode(TelemetryHistoryFile.self, from: Data(contentsOf: fileURL))
            cache.set(decoded, for: fileURL)
            return decoded
        } catch {
            Self.logger.error("History load failed: \(String(describing: error), privacy: .public)")
            // Never overwrite an unreadable file: move it aside, or refuse writes if that fails.
            let isBackedUp = (try? Self.backUpUnreadableFile(at: fileURL)) != nil
            let empty = TelemetryHistoryFile()
            cache.set(empty, for: fileURL, isWriteBlocked: !isBackedUp)
            return empty
        }
    }

    @discardableResult public func append(_ record: TelemetryHistoryRecord, now: Date = Date()) -> Bool {
        var file = load()
        if let last = file.records.last, record.timestamp.timeIntervalSince(last.timestamp) < Self.minimumWriteInterval { return false }
        file.records.append(record)
        if file.records.count > Self.maxRecords || claimPrune(.system, now: now) {
            file.records = Self.pruned(file.records, now: now)
        }
        return write(file)
    }

    @discardableResult public func appendProcessSnapshot(_ record: ProcessHistoryRecord, now: Date = Date()) -> Bool {
        var file = load()
        if let last = file.processRecords.last, record.timestamp.timeIntervalSince(last.timestamp) < Self.minimumWriteInterval { return false }
        file.processRecords.append(record)
        file.processRecords = claimPrune(.process, now: now)
            ? Self.prunedProcess(file.processRecords, now: now) : Array(file.processRecords.suffix(Self.maxProcessRecords))
        return write(file)
    }

    @discardableResult public func appendCacheSnapshot(_ record: CacheHistoryRecord, now: Date = Date()) -> Bool {
        var file = load()
        if let last = file.cacheRecords.last, record.timestamp.timeIntervalSince(last.timestamp) < Self.minimumWriteInterval { return false }
        file.cacheRecords.append(record)
        file.cacheRecords = claimPrune(.cache, now: now)
            ? Self.prunedCache(file.cacheRecords, now: now) : Array(file.cacheRecords.suffix(Self.maxCacheRecords))
        return write(file)
    }

    @discardableResult public func purge(now: Date = Date()) -> Bool {
        var file = load(); file.records = Self.pruned(file.records, now: now)
        file.processRecords = Self.prunedProcess(file.processRecords, now: now); file.cacheRecords = Self.prunedCache(file.cacheRecords, now: now)
        return write(file)
    }

    public func statistics(since: Date, keyPath: KeyPath<TelemetryHistoryRecord, Int64?>, now: Date = Date()) -> HistoryStatistics {
        let values = load().records.filter { $0.timestamp >= since && $0.timestamp <= now }.compactMap { $0[keyPath: keyPath].map(Double.init) }
        return HistoryStatistics(values: values, window: now.timeIntervalSince(since))
    }

    public func processMemoryStatistics(identity: String, since: Date, now: Date = Date()) -> HistoryStatistics {
        let values = load().processRecords.filter { $0.timestamp >= since && $0.timestamp <= now }
            .compactMap { $0.entries.first(where: { $0.identity == identity }).map { Double($0.ramBytes) } }
        return HistoryStatistics(values: values, window: now.timeIntervalSince(since))
    }

    public func cacheStatistics(category: String, since: Date, now: Date = Date()) -> HistoryStatistics {
        let values = load().cacheRecords.filter { $0.timestamp >= since && $0.timestamp <= now }
            .compactMap { $0.categories[category].map(Double.init) }
        return HistoryStatistics(values: values, window: now.timeIntervalSince(since))
    }

    func writeStatisticsForTesting() -> TelemetryHistoryCache.WriteStatistics {
        cache.writeStatistics(for: fileURL)
    }

    /// Updates the in-memory copy and schedules the disk write on the background writer.
    private func write(_ file: TelemetryHistoryFile) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            Self.logger.error("History directory creation failed: \(String(describing: error), privacy: .public)")
            return false
        }
        guard cache.update(file, for: fileURL) else {
            Self.logger.error("History write skipped: the unreadable file could not be backed up")
            return false
        }
        TelemetryHistoryWriter.shared.schedule(fileURL, cache: cache, delay: writeCoalescingDelay)
        return true
    }

    private func claimPrune(_ stream: TelemetryHistoryStream, now: Date) -> Bool {
        cache.claimPrune(stream, for: fileURL, now: now, interval: Self.pruneInterval)
    }

    /// Moves an unreadable history file aside so it is never overwritten.
    static func backUpUnreadableFile(at fileURL: URL) throws {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension.isEmpty ? "json" : fileURL.pathExtension
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(name).corrupt-\(Int(Date().timeIntervalSince1970)).\(fileExtension)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            logger.error("Unreadable history moved to \(backupURL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("History backup failed; writes disabled: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Union of two versions of the file written by different processes: records are
    /// deduplicated by timestamp, keeping the more complete one, then pruned.
    static func merged(_ lhs: TelemetryHistoryFile, _ rhs: TelemetryHistoryFile, now: Date) -> TelemetryHistoryFile {
        TelemetryHistoryFile(
            records: pruned(union(lhs.records, rhs.records, \.timestamp) { $0.sampleCount >= $1.sampleCount }, now: now),
            processRecords: prunedProcess(union(lhs.processRecords, rhs.processRecords, \.timestamp) {
                $0.entries.count >= $1.entries.count
            }, now: now),
            cacheRecords: prunedCache(union(lhs.cacheRecords, rhs.cacheRecords, \.timestamp) {
                $0.categories.count >= $1.categories.count
            }, now: now))
    }

    private static func union<Record>(_ lhs: [Record], _ rhs: [Record], _ timestamp: KeyPath<Record, Date>,
                                      isAtLeastAsComplete: (Record, Record) -> Bool) -> [Record] {
        let byTimestamp = Dictionary((lhs + rhs).map { ($0[keyPath: timestamp], $0) }) { isAtLeastAsComplete($0, $1) ? $0 : $1 }
        return Array(byTimestamp.values)
    }

    /// Buckets records by age regardless of their current sample count, so partial
    /// buckets created at a retention boundary keep absorbing later samples. Averages
    /// are weighted by sample count, which keeps repeated pruning idempotent.
    public static func pruned(_ records: [TelemetryHistoryRecord], now: Date) -> [TelemetryHistoryRecord] {
        let cutoff = now.addingTimeInterval(-aggregateRetention)
        let sorted = records.filter { $0.timestamp >= cutoff && $0.timestamp <= now }.sorted { $0.timestamp < $1.timestamp }
        let recentCutoff = now.addingTimeInterval(-detailedRetention); let intermediateCutoff = now.addingTimeInterval(-intermediateRetention)
        let older = sorted.filter { $0.timestamp < recentCutoff }
        // Tier by 5-minute bucket start so a bucket straddling the 7-day boundary lands in
        // the hourly tier on the first pass instead of moving there on the next one.
        let isAggregate = { (record: TelemetryHistoryRecord) in
            Double(bucketIndex(record.timestamp, bucket: intermediateBucket)) * intermediateBucket < intermediateCutoff.timeIntervalSince1970
        }
        var result = sorted.filter { $0.timestamp >= recentCutoff }
        result += compact(older.filter { !isAggregate($0) }, bucket: intermediateBucket)
        result += compact(older.filter(isAggregate), bucket: aggregateBucket)
        return Array(result.sorted { $0.timestamp < $1.timestamp }.suffix(maxRecords))
    }

    private static func bucketIndex(_ date: Date, bucket: TimeInterval) -> Int {
        Int((date.timeIntervalSince1970 / bucket).rounded(.down))
    }

    private static func compact(_ records: [TelemetryHistoryRecord], bucket: TimeInterval) -> [TelemetryHistoryRecord] {
        Dictionary(grouping: records) { bucketIndex($0.timestamp, bucket: bucket) }.map { index, group in
            let bucketStart = Date(timeIntervalSince1970: Double(index) * bucket)
            // A lone record already aligned on its bucket is a finished summary.
            if group.count == 1, let only = group.first, only.timestamp == bucketStart { return only }
            return TelemetryHistoryRecord(timestamp: bucketStart,
                cpuUsage: weightedAverage(group, \.cpuUsage), memoryPressure: group.compactMap(\.memoryPressure).max(by: pressureOrder),
                ramUsed: weightedAverage(group, \.ramUsed), compressedMemory: weightedAverage(group, \.compressedMemory),
                swapUsed: weightedAverage(group, \.swapUsed), diskUsed: weightedAverage(group, \.diskUsed),
                cpuTemp: weightedAverage(group, \.cpuTemp), sampleCount: group.reduce(0) { $0 + $1.sampleCount },
                ramUsedMinimum: group.compactMap(\.ramUsedMinimum).min(), ramUsedMaximum: group.compactMap(\.ramUsedMaximum).max(),
                cpuUsageMinimum: group.compactMap(\.cpuUsageMinimum).min(), cpuUsageMaximum: group.compactMap(\.cpuUsageMaximum).max())
        }
    }

    private static func weightedAverage(_ group: [TelemetryHistoryRecord], _ keyPath: KeyPath<TelemetryHistoryRecord, Double?>) -> Double? {
        weightedAverage(group.compactMap { record in record[keyPath: keyPath].map { (value: $0, weight: record.sampleCount) } })
    }
    private static func weightedAverage(_ group: [TelemetryHistoryRecord], _ keyPath: KeyPath<TelemetryHistoryRecord, Int64?>) -> Int64? {
        weightedAverage(group.compactMap { record in record[keyPath: keyPath].map { (value: Double($0), weight: record.sampleCount) } }).map(Int64.init)
    }
    private static func weightedAverage(_ samples: [(value: Double, weight: Int)]) -> Double? {
        let totalWeight = samples.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return samples.reduce(0) { $0 + $1.value * Double($1.weight) } / Double(totalWeight)
    }
    private static func pressureOrder(_ lhs: MemoryPressureState, _ rhs: MemoryPressureState) -> Bool {
        let rank: [MemoryPressureState: Int] = [.normal: 0, .warning: 1, .critical: 2]; return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
    private static func prunedProcess(_ records: [ProcessHistoryRecord], now: Date) -> [ProcessHistoryRecord] {
        let cutoff = now.addingTimeInterval(-aggregateRetention); return Array(records.filter { $0.timestamp >= cutoff && $0.timestamp <= now }.sorted { $0.timestamp < $1.timestamp }.suffix(maxProcessRecords))
    }
    private static func prunedCache(_ records: [CacheHistoryRecord], now: Date) -> [CacheHistoryRecord] {
        let cutoff = now.addingTimeInterval(-aggregateRetention); return Array(records.filter { $0.timestamp >= cutoff && $0.timestamp <= now }.sorted { $0.timestamp < $1.timestamp }.suffix(maxCacheRecords))
    }
}
