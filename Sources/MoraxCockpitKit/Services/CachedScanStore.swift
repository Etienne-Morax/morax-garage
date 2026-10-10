import Foundation

/// Disk-backed cache for the result of an expensive scan.
///
/// The application inventory, the persistence audit and the tool registry are all
/// costly to compute and change rarely. Their results are persisted to the shared
/// application support directory as a binary property list and reused until they
/// go stale, so a relaunch does not trigger a full rescan.
///
/// Mirrors the persistence conventions already used by `CleanupStateService`.
private let cachedScanStoreFileLock = NSLock()

public final class CachedScanStore<Item: Codable & Sendable>: @unchecked Sendable {
    /// A scan result together with the moment it was produced.
    public struct Snapshot: Codable, Sendable {
        public let scanDate: Date
        public let items: [Item]

        public init(scanDate: Date, items: [Item]) {
            self.scanDate = scanDate
            self.items = items
        }
    }

    /// Default lifetime of a cached scan: one day.
    public static var defaultTimeToLive: TimeInterval { 86_400 }

    /// Shared application support directory used by every Morax Garage cache.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MoraxGarage")
    }

    public static var defaultKey: String { "_default" }

    public let fileURL: URL
    public let timeToLive: TimeInterval

    private let directory: URL
    private let fileManager = FileManager.default

    public init(
        fileName: String,
        timeToLive: TimeInterval = CachedScanStore.defaultTimeToLive,
        directory: URL? = nil
    ) {
        self.directory = directory ?? CachedScanStore.defaultDirectory
        self.fileURL = self.directory.appendingPathComponent(fileName)
        self.timeToLive = timeToLive
    }

    /// Returns `true` when a scan performed at `scanDate` is still within its lifetime.
    public func isFresh(_ scanDate: Date?, now: Date = Date()) -> Bool {
        guard let scanDate else { return false }
        let age = now.timeIntervalSince(scanDate)
        return age >= 0 && age < timeToLive
    }

    /// Checks freshness of a scan for a specific key.
    public func isFresh(for key: String, now: Date = Date()) -> Bool {
        guard let snapshot = load(for: key) else { return false }
        return isFresh(snapshot.scanDate, now: now)
    }

    /// Reads all persisted snapshots keyed by identifier.
    public func loadAll() -> [String: Snapshot] {
        Self.readAllSnapshots(from: fileURL)
    }

    /// Reads a specific snapshot for the given key, whether or not it is still fresh.
    public func load(for key: String) -> Snapshot? {
        let all = loadAll()
        return all[key]
    }

    /// Reads the default snapshot, or single snapshot if only one exists.
    public func load() -> Snapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let all = loadAll()
        if let def = all[Self.defaultKey] {
            return def
        }
        if all.count == 1, let first = all.values.first {
            return first
        }
        return nil
    }

    /// Persists a scan result for a specific key off the calling thread.
    public func save(items: [Item], scanDate: Date, for key: String) {
        let destinationFileURL = fileURL
        let destinationDirURL = directory

        Task.detached(priority: .utility) {
            Self.writeSnapshot(items: items, scanDate: scanDate, for: key, to: destinationFileURL, in: destinationDirURL)
        }
    }

    /// Persists a scan result for a specific key before returning.
    public func saveSynchronously(items: [Item], scanDate: Date, for key: String) {
        Self.writeSnapshot(items: items, scanDate: scanDate, for: key, to: fileURL, in: directory)
    }

    /// Persists a scan result for the default key off the calling thread.
    public func save(items: [Item], scanDate: Date) {
        save(items: items, scanDate: scanDate, for: Self.defaultKey)
    }

    /// Persists a scan result for the default key before returning.
    public func saveSynchronously(items: [Item], scanDate: Date) {
        saveSynchronously(items: items, scanDate: scanDate, for: Self.defaultKey)
    }

    /// Removes the persisted snapshot for a specific key.
    public func clear(for key: String) {
        cachedScanStoreFileLock.lock()
        defer { cachedScanStoreFileLock.unlock() }

        var all = Self.readAllSnapshotsUnsafe(from: fileURL)
        all.removeValue(forKey: key)
        if all.isEmpty {
            try? fileManager.removeItem(at: fileURL)
        } else {
            Self.writeAllUnsafe(all, to: fileURL, in: directory)
        }
    }

    /// Removes all persisted snapshots.
    public func clear() {
        cachedScanStoreFileLock.lock()
        defer { cachedScanStoreFileLock.unlock() }
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Private Persistence & Migration

    private static func readAllSnapshots(from fileURL: URL) -> [String: Snapshot] {
        cachedScanStoreFileLock.lock()
        defer { cachedScanStoreFileLock.unlock() }
        return readAllSnapshotsUnsafe(from: fileURL)
    }

    private static func readAllSnapshotsUnsafe(from fileURL: URL) -> [String: Snapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = PropertyListDecoder()

        // 1. Try v2 format: [String: Snapshot]
        if let multi = try? decoder.decode([String: Snapshot].self, from: data) {
            return multi
        }

        // 2. Try v1 format: Snapshot
        if let single = try? decoder.decode(Snapshot.self, from: data) {
            let migrated = [defaultKey: single]
            writeAllUnsafe(migrated, to: fileURL, in: fileURL.deletingLastPathComponent())
            return migrated
        }

        // 3. Try legacy CleanupSnapshot format
        if let legacy = try? decoder.decode(LegacyCleanupSnapshot<Item>.self, from: data) {
            let migratedSnapshot = Snapshot(scanDate: legacy.lastScanDate, items: legacy.items)
            let migrated = [legacy.scannerRawValue: migratedSnapshot]
            writeAllUnsafe(migrated, to: fileURL, in: fileURL.deletingLastPathComponent())
            return migrated
        }

        return [:]
    }

    private static func writeAllUnsafe(_ snapshots: [String: Snapshot], to fileURL: URL, in directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure handled silently
        }
    }

    private static func writeSnapshot(items: [Item], scanDate: Date, for key: String, to fileURL: URL, in directory: URL) {
        cachedScanStoreFileLock.lock()
        defer { cachedScanStoreFileLock.unlock() }

        var all = readAllSnapshotsUnsafe(from: fileURL)
        all[key] = Snapshot(scanDate: scanDate, items: items)
        writeAllUnsafe(all, to: fileURL, in: directory)
    }
}

extension CachedScanStore.Snapshot: Equatable where Item: Equatable {}

private struct LegacyCleanupSnapshot<T: Codable & Sendable>: Codable, Sendable {
    let scannerRawValue: String
    let lastScanDate: Date
    let items: [T]
}
