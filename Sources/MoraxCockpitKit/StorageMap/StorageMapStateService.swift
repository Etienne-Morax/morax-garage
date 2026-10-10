import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class StorageMapStateService {
    public static let shared = StorageMapStateService()
    
    public var rootNode: StorageNode? = nil
    public var currentZoomNode: StorageNode? = nil
    public var targetURL: URL = FileManager.default.homeDirectoryForCurrentUser
    public var lastScanDate: Date? = nil
    public var isScanning: Bool = false
    public var scanProgress: StorageScanProgress? = nil
    public var maxDepth: Int = 3
    public var lastErrorMessage: String? = nil
    /// Completeness of the last scan: unreadable paths, deliberate skips, volume reconciliation.
    public var scanReport: StorageScanReport? = nil
    
    /// True while the on-disk snapshot is being decoded off the main actor.
    public private(set) var isRestoringCache: Bool = false
    /// True once a restore attempt has finished, successfully or not. The view uses it to
    /// tell "no cache" apart from "cache not read yet", so it never starts a full scan
    /// over a snapshot that was about to appear.
    public private(set) var hasAttemptedRestore: Bool = false
    
    private var scanTask: Task<Void, Never>? = nil
    /// Identifies the scan whose results may still reach the UI. A cancelled scan unwinds
    /// asynchronously, after its replacement has started: without this token its
    /// cancellation handler would clear `isScanning` for the scan that replaced it.
    private var scanGeneration: UInt64 = 0
    private var restoreTask: Task<Void, Never>? = nil
    
    // MARK: - Cache budget
    
    /// Node ceiling for the tree kept in memory and written to disk.
    ///
    /// The treemap drops any tile under three pixels, so a whole-disk walk retains
    /// hundreds of times more nodes than it can ever draw. Past this count the snapshot
    /// costs more to decode than the scan that produced it and pins gigabytes for tiles
    /// nobody sees.
    nonisolated public static let maxCachedNodeCount = 80_000
    
    /// Depth ceiling for the same tree, counted from the scan root.
    nonisolated public static let maxCachedDepth = 12
    
    /// A snapshot larger than this predates the node budget. Decoding it would stall the
    /// tab for longer than a fresh scan, so it is discarded unread.
    nonisolated public static let maxCacheFileBytes: Int64 = 48 * 1024 * 1024
    
    public let cacheDirectory: URL
    public let cacheFileURL: URL
    private let fileManager = FileManager.default
    
    public init(customCacheDirectory: URL? = nil) {
        if let custom = customCacheDirectory {
            self.cacheDirectory = custom
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.cacheDirectory = home.appendingPathComponent("Library/Application Support/MoraxGarage")
        }
        self.cacheFileURL = self.cacheDirectory.appendingPathComponent("storage_map_cache.plist")
    }
    
    public var activeNode: StorageNode? {
        currentZoomNode ?? rootNode
    }
    
    public var hasLoadedOnce: Bool {
        lastScanDate != nil || rootNode != nil
    }
    
    public var formattedLastScanDate: String? {
        guard let date = lastScanDate else { return nil }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        if calendar.isDateInToday(date) {
            return "Aujourd'hui à \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Hier à \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
    }
    
    /// Decodes the on-disk snapshot. Runs off the main actor: a whole-disk tree holds tens
    /// of thousands of nodes, and decoding it inline is what used to freeze the tab on the
    /// first visit.
    nonisolated public static func decodeSnapshot(at url: URL) -> StorageMapSnapshot? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        
        // Checked before reading: an oversized snapshot is never worth the decode.
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let fileSize = (attributes[.size] as? NSNumber)?.int64Value,
           fileSize > maxCacheFileBytes {
            try? fileManager.removeItem(at: url)
            return nil
        }
        
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        if let snapshot = try? PropertyListDecoder().decode(StorageMapSnapshot.self, from: data) {
            return snapshot
        }
        // Fallback for snapshots previously saved in JSON format.
        return try? JSONDecoder().decode(StorageMapSnapshot.self, from: data)
    }
    
    private func apply(_ snapshot: StorageMapSnapshot) {
        self.rootNode = snapshot.rootNode
        self.targetURL = snapshot.targetURL
        self.lastScanDate = snapshot.lastScanDate
        self.maxDepth = snapshot.maxDepth
        self.scanReport = snapshot.report?.reclassifyingSystemDataVaults()
        self.currentZoomNode = nil
        self.lastErrorMessage = nil
    }
    
    /// Restores the cached tree without blocking the main actor. Safe to call on every
    /// appearance: the work happens once and concurrent callers await the same task.
    public func restoreCacheFromDisk() async {
        if hasAttemptedRestore { return }
        if let existing = restoreTask {
            await existing.value
            return
        }
        
        let url = cacheFileURL
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRestoringCache = true
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.decodeSnapshot(at: url)
            }.value
            if let snapshot, !self.isScanning {
                self.apply(snapshot)
            }
            self.isRestoringCache = false
            self.hasAttemptedRestore = true
            self.restoreTask = nil
        }
        restoreTask = task
        await task.value
    }
    
    /// Synchronous restore. Kept for callers that cannot await; the view uses
    /// ``restoreCacheFromDisk()`` instead.
    public func loadCacheFromDisk() {
        guard let snapshot = Self.decodeSnapshot(at: cacheFileURL) else { return }
        apply(snapshot)
        hasAttemptedRestore = true
    }
    
    /// Folds a freshly walked tree down to the cache budget, in place.
    ///
    /// The threshold rises until the tree fits: every pass folds the smallest entries of
    /// each directory into one aggregate, so sizes, item counts and breakdowns stay exact
    /// while the node count — and with it the decode cost on the next visit — collapses.
    nonisolated public static func collapseToCacheBudget(_ root: StorageNode) {
        root.collapseEntries(belowAllocatedBytes: 0, maxDepth: maxCachedDepth)
        
        // The walker already folds everything under its own floor, so that floor is where
        // a useful threshold starts.
        var threshold = max(1, StorageScanOptions.default.minRetainedBytes)
        var passes = 0
        // Each pass quadruples the threshold, so 16 passes reach the terabyte range: well
        // past the point where any single directory can still hold 80 000 entries.
        let maxPasses = 16
        while root.nodeCount > maxCachedNodeCount && passes < maxPasses {
            threshold *= 4
            root.collapseEntries(belowAllocatedBytes: threshold, maxDepth: maxCachedDepth)
            passes += 1
        }
    }
    
    /// Persists current storage tree snapshot to disk
    public func saveCacheToDisk(synchronously: Bool = false) {
        guard let root = self.rootNode, let scanDate = self.lastScanDate else { return }
        let snapshot = StorageMapSnapshot(
            targetURL: self.targetURL,
            lastScanDate: scanDate,
            maxDepth: self.maxDepth,
            rootNode: root,
            report: self.scanReport
        )
        
        let destinationFileURL = self.cacheFileURL
        let destinationDirURL = self.cacheDirectory
        
        if synchronously {
            do {
                try FileManager.default.createDirectory(at: destinationDirURL, withIntermediateDirectories: true)
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(snapshot)
                try data.write(to: destinationFileURL, options: .atomic)
            } catch {
                // Background persistence failure handled silently
            }
        } else {
            Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(at: destinationDirURL, withIntermediateDirectories: true)
                    let encoder = PropertyListEncoder()
                    encoder.outputFormat = .binary
                    let data = try encoder.encode(snapshot)
                    try data.write(to: destinationFileURL, options: .atomic)
                } catch {
                    // Background persistence failure handled silently
                }
            }
        }
    }
    
    /// Starts or restarts a scan for a given URL.
    ///
    /// The walk runs on a detached task: it is IO bound and must stay off the main
    /// actor, which only publishes progress and the resulting tree.
    public func startScan(url: URL? = nil) {
        let destinationURL = url ?? targetURL
        scanTask?.cancel()

        targetURL = destinationURL
        isScanning = true
        scanProgress = StorageScanProgress(
            scannedCount: 0,
            scannedAllocatedBytes: 0,
            scannedLogicalBytes: 0,
            currentPath: destinationURL.path,
            errorsCount: 0,
            isCompleted: false
        )
        lastErrorMessage = nil
        scanReport = nil

        scanGeneration &+= 1
        let generation = scanGeneration

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try await StorageScanner.shared.scanWithReport(rootURL: destinationURL) { progress in
                    Task { @MainActor in
                        guard let self, self.scanGeneration == generation else { return }
                        self.scanProgress = progress
                    }
                }

                // Done here, while the tree is still private to this task: the main actor
                // only ever receives a tree that fits the budget, and the memory the
                // folded nodes held is released before it is published.
                Self.collapseToCacheBudget(result.rootNode)

                await self?.finishScan(generation: generation, rootNode: result.rootNode, report: result.report)
            } catch is CancellationError {
                await self?.endScan(generation: generation, errorMessage: nil)
            } catch {
                await self?.endScan(generation: generation, errorMessage: error.localizedDescription)
            }
        }
    }

    private func finishScan(generation: UInt64, rootNode: StorageNode, report: StorageScanReport) {
        guard scanGeneration == generation else { return }
        self.rootNode = rootNode
        scanReport = report
        currentZoomNode = nil
        lastScanDate = Date()
        isScanning = false
        lastErrorMessage = nil
        scanTask = nil
        saveCacheToDisk()
    }

    /// Ends a scan that produced no tree. A nil message means it was cancelled.
    private func endScan(generation: UInt64, errorMessage: String?) {
        guard scanGeneration == generation else { return }
        isScanning = false
        if let errorMessage { lastErrorMessage = errorMessage }
        scanTask = nil
    }

    /// Cancels active scan
    public func cancelScan() {
        scanGeneration &+= 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
    
    /// Clears cached tree from memory and disk
    public func clearCache() {
        rootNode = nil
        currentZoomNode = nil
        lastScanDate = nil
        scanProgress = nil
        lastErrorMessage = nil
        scanReport = nil

        try? fileManager.removeItem(at: cacheFileURL)
    }
}
