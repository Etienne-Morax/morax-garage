import Foundation
import os

/// The independent streams stored in the telemetry history file.
enum TelemetryHistoryStream: Hashable, Sendable {
    case system, process, cache
}

/// Process-wide in-memory copy of each history file. Mutations are applied here
/// synchronously and persisted later by `TelemetryHistoryWriter`, so callers never
/// encode or write the file themselves.
final class TelemetryHistoryCache: @unchecked Sendable {
    private struct DiskStamp: Equatable {
        let modificationDate: Date?
        let fileSize: Int?
    }

    private struct Entry {
        var file: TelemetryHistoryFile
        var diskStamp: DiskStamp
        var generation = 0
        var writtenGeneration = 0
        var isWriteBlocked = false
        var lastPrunedAt: [TelemetryHistoryStream: Date] = [:]

        var isDirty: Bool { generation != writtenGeneration }
    }

    struct WriteStatistics: Equatable, Sendable {
        var diskWriteCount = 0
        var lastWriteWasOnMainThread: Bool?
    }

    private let lock = NSLock()
    private var storage: [URL: Entry] = [:]
    private var statistics: [URL: WriteStatistics] = [:]

    /// Returns the cached file. A file with pending writes is always served from memory;
    /// otherwise the entry is only valid while the file on disk is unchanged.
    func get(for url: URL) -> TelemetryHistoryFile? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[url] else { return nil }
        if entry.isDirty || entry.diskStamp == Self.diskStamp(for: url) {
            return entry.file
        }
        return nil
    }

    func set(_ file: TelemetryHistoryFile, for url: URL, isWriteBlocked: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        storage[url] = Entry(file: file, diskStamp: Self.diskStamp(for: url), isWriteBlocked: isWriteBlocked)
    }

    /// Records a new in-memory version that still has to be persisted.
    /// Returns false when writes are blocked to protect an unreadable file.
    func update(_ file: TelemetryHistoryFile, for url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var entry = storage[url] ?? Entry(file: file, diskStamp: Self.diskStamp(for: url))
        guard !entry.isWriteBlocked else { return false }
        entry.file = file
        entry.generation += 1
        storage[url] = entry
        return true
    }

    /// Returns true, and records `now`, when the stream is due for a full prune.
    func claimPrune(_ stream: TelemetryHistoryStream, for url: URL, now: Date, interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = storage[url] else { return true }
        if let last = entry.lastPrunedAt[stream], now >= last, now.timeIntervalSince(last) < interval {
            return false
        }
        entry.lastPrunedAt[stream] = now
        storage[url] = entry
        return true
    }

    /// Returns the version to persist, and whether the file on disk changed since this
    /// process last loaded or wrote it (another process wrote it in between).
    func pendingWrite(for url: URL) -> (file: TelemetryHistoryFile, generation: Int, isDiskChanged: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[url], entry.isDirty else { return nil }
        let currentStamp = Self.diskStamp(for: url)
        let isDiskChanged = currentStamp.modificationDate != nil && currentStamp != entry.diskStamp
        return (entry.file, entry.generation, isDiskChanged)
    }

    func dirtyURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage.filter { $0.value.isDirty }.map(\.key)
    }

    /// Records a completed write. `writtenFile` is what reached the disk, including records
    /// merged from another process; it replaces the in-memory copy unless a newer version is
    /// already pending, which keeps the old stamp and is merged again on its own write.
    func markWritten(_ url: URL, generation: Int, writtenFile: TelemetryHistoryFile, onMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var stats = statistics[url] ?? WriteStatistics()
        stats.diskWriteCount += 1
        stats.lastWriteWasOnMainThread = onMainThread
        statistics[url] = stats
        guard var entry = storage[url], generation > entry.writtenGeneration else { return }
        entry.writtenGeneration = generation
        if !entry.isDirty {
            entry.file = writtenFile
            entry.diskStamp = Self.diskStamp(for: url)
        }
        storage[url] = entry
    }

    func writeStatistics(for url: URL) -> WriteStatistics {
        lock.lock()
        defer { lock.unlock() }
        return statistics[url] ?? WriteStatistics()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        statistics.removeAll()
    }

    private static func diskStamp(for url: URL) -> DiskStamp {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return DiskStamp(modificationDate: attributes?[.modificationDate] as? Date, fileSize: attributes?[.size] as? Int)
    }
}

/// Serial background writer. Several appends landing within the coalescing delay
/// produce a single encode and atomic write of the latest in-memory version.
final class TelemetryHistoryWriter: @unchecked Sendable {
    static let shared = TelemetryHistoryWriter()

    private let queue = DispatchQueue(label: "com.morax.garage.telemetry-history.writer", qos: .utility)
    private let lock = NSLock()
    private var scheduledURLs: Set<URL> = []
    private static let logger = Logger(subsystem: "com.morax.garage", category: "TelemetryHistory")

    func schedule(_ url: URL, cache: TelemetryHistoryCache, delay: TimeInterval) {
        lock.lock()
        let isAlreadyScheduled = !scheduledURLs.insert(url).inserted
        lock.unlock()
        guard !isAlreadyScheduled else { return }

        let work: @Sendable () -> Void = { [self] in
            lock.lock()
            scheduledURLs.remove(url)
            lock.unlock()
            performPendingWrite(url, cache: cache)
        }
        if delay <= 0 {
            queue.async(execute: work)
        } else {
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Waits for queued writes and persists anything still pending.
    func flush(_ urls: [URL]? = nil, cache: TelemetryHistoryCache) {
        queue.sync {
            for url in urls ?? cache.dirtyURLs() {
                performPendingWrite(url, cache: cache)
            }
        }
    }

    /// Writes the pending version. The main app and the menu helper share the file, so the
    /// stamp check, merge, write and re-stamp run under a cross-process lock, and a file
    /// changed by the other process is merged instead of overwritten.
    private func performPendingWrite(_ url: URL, cache: TelemetryHistoryCache) {
        let lockDescriptor = Self.acquireFileLock(for: url)
        defer { Self.releaseFileLock(lockDescriptor) }
        guard let pending = cache.pendingWrite(for: url) else { return }
        do {
            let file = try pending.isDiskChanged ? mergedWithDisk(pending.file, url: url) : pending.file
            try JSONEncoder().encode(file).write(to: url, options: .atomic)
            cache.markWritten(url, generation: pending.generation, writtenFile: file, onMainThread: Thread.isMainThread)
        } catch {
            Self.logger.error("History write failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func mergedWithDisk(_ file: TelemetryHistoryFile, url: URL) throws -> TelemetryHistoryFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return file
        }
        guard let onDisk = try? JSONDecoder().decode(TelemetryHistoryFile.self, from: data) else {
            // Never overwrite an unreadable file: move it aside, or give up on this write.
            try TelemetryHistoryStore.backUpUnreadableFile(at: url)
            return file
        }
        return TelemetryHistoryStore.merged(file, onDisk, now: Date())
    }

    private static func acquireFileLock(for url: URL) -> Int32 {
        let descriptor = open(url.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            logger.error("History lock unavailable, writing without it: errno \(errno, privacy: .public)")
            return -1
        }
        flock(descriptor, LOCK_EX)
        return descriptor
    }

    private static func releaseFileLock(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
