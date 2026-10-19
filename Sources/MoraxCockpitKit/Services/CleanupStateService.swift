import Foundation
import Observation

public enum CleanupFlowState: Equatable, Sendable {
    case idle
    case scanning(progress: String)
    case results
    case confirming
    case trashing(progress: String, done: Int, total: Int)
    case completed(result: TrashBatchResult)
}

public enum ScannerType: String, CaseIterable, Identifiable, Sendable, Codable, CodingKeyRepresentable {
    case resolve = "DaVinci Resolve Caches"
    case photo = "Photo Apps (Lightroom, Capture One, Photoshop)"
    case apps = "App Caches (WhatsApp, Spotify, Slack…)"
    case dev = "Developer Build Artefacts"
    case claude = "Claude Code Caches & Worktrees"
    case browsers = "Web Browser Caches"
    case system = "System & User Caches"
    case installers = "Installers & Large Archives"
    /// Curated subset of caches that refill on their own; driven by the one-click purge,
    /// so it stays out of `concreteScanners` (the other scanners already cover its paths).
    case recurring = "Recurring Caches"
    case all = "All Scanners"
    
    public var id: String { rawValue }
    
    public static var concreteScanners: [ScannerType] {
        [.resolve, .photo, .apps, .dev, .claude, .browsers, .system, .installers]
    }
    
    public var iconName: String {
        switch self {
        case .resolve: return "film"
        case .photo: return "camera.aperture"
        case .apps: return "square.stack.3d.up"
        case .dev: return "hammer"
        case .claude: return "bubble.left.and.bubble.right"
        case .browsers: return "globe"
        case .system: return "internaldrive"
        case .installers: return "archivebox"
        case .recurring: return "arrow.3.trianglepath"
        case .all: return "sparkles"
        }
    }
}

/// Summary statistics derived from cached scan items for a category.
public struct CategorySummary: Sendable, Equatable {
    public let bytes: Int64
    public let itemCount: Int
    public let scanDate: Date
    public let isStale: Bool
    
    public init(bytes: Int64, itemCount: Int, scanDate: Date, isStale: Bool) {
        self.bytes = bytes
        self.itemCount = itemCount
        self.scanDate = scanDate
        self.isStale = isStale
    }
}

@Observable
@MainActor
public final class CleanupStateService {
    public static let shared = CleanupStateService()
    
    public var selectedScanner: ScannerType = .resolve
    public var flowState: CleanupFlowState = .idle
    public var scannedItems: [FileItem] = []
    public var selectedCategoryId: String? = nil
    public var lastScanDate: Date? = nil
    public var isScanning: Bool = false
    
    public var isConfirming: Bool {
        get {
            if case .confirming = flowState { return true }
            return false
        }
        set {
            if !newValue && flowState == .confirming {
                flowState = .results
            }
        }
    }

    /// Number of selected items dropped by the last cleanup run because they had
    /// changed on disk since the scan that produced them.
    public private(set) var staleSkippedCount: Int = 0

    /// User-facing reason the last cleanup run moved nothing at all (the batch was
    /// refused as a whole), or `nil`. Per-item failures are reported in the
    /// `.completed` result instead, and those items stay listed.
    public private(set) var lastTrashErrorMessage: String? = nil

    /// Lifetime of a persisted cleanup snapshot: one day, matching `CachedScanStore`.
    public static let snapshotTimeToLive: TimeInterval = 86_400
    
    public let cacheDirectory: URL
    public let cacheFileURL: URL
    public private(set) var cachedSnapshots: [String: CachedScanStore<FileItem>.Snapshot] = [:]
    
    public private(set) var currentlyEstimatingScanner: ScannerType? = nil
    public private(set) var isEstimating: Bool = false
    public private(set) var estimationProgressText: String = ""
    
    /// Runs one concrete scanner; injectable so tests never walk the real disk.
    public typealias ScanRunner = @Sendable (ScannerType, @Sendable @escaping (String) -> Void) async -> [FileItem]

    private let cacheStore: CachedScanStore<FileItem>
    private let fileManager = FileManager.default
    private let trashService: TrashService
    private let stagingService: CleanupStagingService
    private let scanRunner: ScanRunner
    private var inMemoryItems: [ScannerType: [FileItem]] = [:]

    /// Set by `startRecurringCachePurge`: the next finished scan preselects its `.safe` items.
    private var shouldPreselectSafeAfterScan = false

    private var scanTask: Task<Void, Never>? = nil
    private var estimationTask: Task<Void, Never>? = nil
    private var trashTask: Task<Void, Never>? = nil

    public init(
        customCacheDirectory: URL? = nil,
        trashService: TrashService = .shared,
        stagingService: CleanupStagingService? = nil,
        scanRunner: ScanRunner? = nil
    ) {
        self.trashService = trashService
        self.stagingService = stagingService ?? .shared
        self.scanRunner = scanRunner ?? { scanner, progress in
            await CleanupStateService.runScanner(scanner, progressHandler: progress)
        }
        let directory: URL
        if let custom = customCacheDirectory {
            directory = custom
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            directory = home.appendingPathComponent("Library/Application Support/MoraxGarage")
        }
        self.cacheDirectory = directory
        self.cacheFileURL = directory.appendingPathComponent("cleanup_cache.plist")
        self.cacheStore = CachedScanStore<FileItem>(fileName: "cleanup_cache.plist", directory: directory)
        
        loadCacheFromDisk()
    }
    
    /// `true` when the displayed results come from a snapshot older than its lifetime.
    public var isSnapshotStale: Bool {
        guard let lastScanDate else { return false }
        return Date().timeIntervalSince(lastScanDate) >= Self.snapshotTimeToLive
    }

    public var hasLoadedOnce: Bool {
        !cachedSnapshots.isEmpty || lastScanDate != nil || !scannedItems.isEmpty
    }
    
    public var formattedLastScanDate: String? {
        guard let date = lastScanDate else { return nil }
        return Self.formatDate(date)
    }
    
    public static func formatDate(_ date: Date) -> String {
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
    
    /// Reads cached cleanup snapshots from disk into memory without triggering rescan.
    public func loadCacheFromDisk() {
        let all = cacheStore.loadAll()
        self.cachedSnapshots = all
        
        if let currentSnapshot = all[selectedScanner.id] {
            self.scannedItems = currentSnapshot.items
            self.lastScanDate = currentSnapshot.scanDate
            self.inMemoryItems[selectedScanner] = currentSnapshot.items
        }
    }
    
    /// Returns the derived summary for a scanner (excluding `.blocked` tier items).
    public func cachedSummary(for scanner: ScannerType) -> CategorySummary? {
        if scanner == .all {
            return allScannersSummary()
        }
        
        guard let snapshot = cachedSnapshots[scanner.id] else {
            return nil
        }
        
        let validItems = snapshot.items.filter { $0.riskTier != .blocked }
        let bytes = validItems.reduce(0) { $0 + $1.sizeBytes }
        let isStale = Date().timeIntervalSince(snapshot.scanDate) >= Self.snapshotTimeToLive
        
        return CategorySummary(
            bytes: bytes,
            itemCount: validItems.count,
            scanDate: snapshot.scanDate,
            isStale: isStale
        )
    }
    
    private func allScannersSummary() -> CategorySummary? {
        let concrete = ScannerType.concreteScanners
        let availableSnapshots = concrete.compactMap { scanner -> (ScannerType, CachedScanStore<FileItem>.Snapshot)? in
            guard let snap = cachedSnapshots[scanner.id] else { return nil }
            return (scanner, snap)
        }
        
        guard !availableSnapshots.isEmpty else {
            if let allSnapshot = cachedSnapshots[ScannerType.all.id] {
                let validItems = allSnapshot.items.filter { $0.riskTier != .blocked }
                let bytes = validItems.reduce(0) { $0 + $1.sizeBytes }
                let isStale = Date().timeIntervalSince(allSnapshot.scanDate) >= Self.snapshotTimeToLive
                return CategorySummary(
                    bytes: bytes,
                    itemCount: validItems.count,
                    scanDate: allSnapshot.scanDate,
                    isStale: isStale
                )
            }
            return nil
        }
        
        var seen = Set<URL>()
        var totalBytes: Int64 = 0
        var totalCount: Int = 0
        var latestScanDate = Date.distantPast
        var isAnyStale = false
        
        for (_, snapshot) in availableSnapshots {
            if snapshot.scanDate > latestScanDate {
                latestScanDate = snapshot.scanDate
            }
            if Date().timeIntervalSince(snapshot.scanDate) >= Self.snapshotTimeToLive {
                isAnyStale = true
            }
            for item in snapshot.items where item.riskTier != .blocked {
                let stdURL = item.url.standardizedFileURL
                if !seen.contains(stdURL) {
                    seen.insert(stdURL)
                    totalBytes += item.sizeBytes
                    totalCount += 1
                }
            }
        }
        
        return CategorySummary(
            bytes: totalBytes,
            itemCount: totalCount,
            scanDate: latestScanDate == .distantPast ? Date() : latestScanDate,
            isStale: isAnyStale
        )
    }
    
    public var coverageSummary: (available: Int, total: Int) {
        let concrete = ScannerType.concreteScanners
        let available = concrete.filter { cachedSnapshots[$0.id] != nil }.count
        return (available, concrete.count)
    }
    
    public func selectScanner(_ scanner: ScannerType) {
        guard scanner != selectedScanner else { return }
        inMemoryItems[selectedScanner] = scannedItems
        selectedScanner = scanner
        
        if let inMem = inMemoryItems[scanner] {
            scannedItems = inMem
            lastScanDate = cachedSnapshots[scanner.id]?.scanDate
        } else if let snapshot = cachedSnapshots[scanner.id] {
            scannedItems = snapshot.items
            lastScanDate = snapshot.scanDate
            inMemoryItems[scanner] = snapshot.items
        } else {
            scannedItems = []
            lastScanDate = nil
        }
    }
    
    /// Persists current cleanup scan results to disk
    public func saveCacheToDisk(synchronously: Bool = false) {
        guard let scanDate = self.lastScanDate else { return }
        let items = self.scannedItems
        let key = self.selectedScanner.id
        let snapshot = CachedScanStore<FileItem>.Snapshot(scanDate: scanDate, items: items)
        self.cachedSnapshots[key] = snapshot
        self.inMemoryItems[self.selectedScanner] = items
        
        if synchronously {
            cacheStore.saveSynchronously(items: items, scanDate: scanDate, for: key)
        } else {
            cacheStore.save(items: items, scanDate: scanDate, for: key)
        }
    }
    
    public var totalReclaimableBytes: Int64 {
        scannedItems.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }
    
    public var selectedCount: Int {
        scannedItems.filter { $0.isSelected }.count
    }
    
    public var selectionRiskSummary: (safe: Int64, rebuild: Int64, destructive: Int64) {
        var safe: Int64 = 0
        var rebuild: Int64 = 0
        var destructive: Int64 = 0
        for item in scannedItems where item.isSelected {
            switch item.riskTier {
            case .safe:
                safe += item.sizeBytes
            case .rebuildCost:
                rebuild += item.sizeBytes
            case .destructive:
                destructive += item.sizeBytes
            case .blocked:
                break
            }
        }
        return (safe: safe, rebuild: rebuild, destructive: destructive)
    }
    
    public var totalRiskSummary: (safe: Int64, rebuild: Int64, destructive: Int64, blocked: Int64) {
        var safe: Int64 = 0
        var rebuild: Int64 = 0
        var destructive: Int64 = 0
        var blocked: Int64 = 0
        for item in scannedItems {
            switch item.riskTier {
            case .safe:
                safe += item.sizeBytes
            case .rebuildCost:
                rebuild += item.sizeBytes
            case .destructive:
                destructive += item.sizeBytes
            case .blocked:
                blocked += item.sizeBytes
            }
        }
        return (safe: safe, rebuild: rebuild, destructive: destructive, blocked: blocked)
    }
    
    public var hasSelectedDestructiveItems: Bool {
        scannedItems.contains { $0.isSelected && $0.riskTier == .destructive }
    }
    
    public var categories: [CleanupCategory] {
        Array(Set(scannedItems.map { $0.category })).sorted { $0.rawValue < $1.rawValue }
    }
    
    public func selectAllSafe() {
        for i in scannedItems.indices {
            if scannedItems[i].riskTier == .safe {
                scannedItems[i].isSelected = true
            } else {
                scannedItems[i].isSelected = false
            }
        }
    }
    
    public func deselectAll() {
        for i in scannedItems.indices {
            scannedItems[i].isSelected = false
        }
    }
    
    public func select(tier: RiskTier) {
        guard tier != .blocked else { return }
        for i in scannedItems.indices {
            if scannedItems[i].riskTier == tier {
                scannedItems[i].isSelected = true
            }
        }
    }
    
    // MARK: - Scanning Flow

    /// One-click purge of the caches that refill on their own: scans the recurring
    /// caches and preselects every `.safe` item. Nothing moves until the user confirms
    /// the selection through the regular confirmation sheet.
    public func startRecurringCachePurge() {
        selectScanner(.recurring)
        shouldPreselectSafeAfterScan = true
        startScan()
    }

    public func startScan() {
        flowState = .scanning(progress: "Initializing scan...")
        isScanning = true

        scanTask?.cancel()
        let scanner = selectedScanner
        let scanRunner = self.scanRunner

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let progressThrottle = ProgressThrottle(minimumInterval: 0.25)
            let updateProgress: @Sendable (String) -> Void = { [weak self] p in
                guard progressThrottle.shouldEmit() else { return }
                Task { @MainActor [weak self] in
                    // A late progress message must not revive a cancelled scan.
                    guard let self, self.isScanning else { return }
                    self.flowState = .scanning(progress: p)
                }
            }

            var items: [FileItem] = []

            if scanner == .all {
                let concrete = ScannerType.concreteScanners
                var combined: [FileItem] = []
                for (index, sc) in concrete.enumerated() {
                    guard !Task.isCancelled else { return }
                    let scItems = await scanRunner(sc) { p in
                        updateProgress("[\(index + 1)/\(concrete.count)] \(p)")
                    }
                    guard !Task.isCancelled else { return }
                    combined.append(contentsOf: scItems)

                    // Also update individual cached snapshot for that scanner
                    await self?.storeSnapshot(scItems, for: sc, scanDate: Date())
                }

                var seen = Set<URL>()
                for item in combined {
                    if !seen.contains(item.url) {
                        seen.insert(item.url)
                        items.append(item)
                    }
                }
            } else {
                items = await scanRunner(scanner, updateProgress)
            }

            guard !Task.isCancelled else { return }
            await self?.finishScan(items, for: scanner)
        }
    }

    /// Records a fresh snapshot for one scanner in memory and on disk.
    private func storeSnapshot(_ items: [FileItem], for scanner: ScannerType, scanDate: Date) {
        cachedSnapshots[scanner.id] = CachedScanStore<FileItem>.Snapshot(scanDate: scanDate, items: items)
        cacheStore.save(items: items, scanDate: scanDate, for: scanner.id)
        inMemoryItems[scanner] = items
    }

    /// Publishes the results of `startScan`. Runs on the scan task, so a scan cancelled
    /// while this hop was queued is dropped instead of overwriting the idle state.
    private func finishScan(_ items: [FileItem], for scanner: ScannerType) {
        guard !Task.isCancelled else { return }
        let now = Date()
        storeSnapshot(items, for: scanner, scanDate: now)
        scannedItems = items
        if shouldPreselectSafeAfterScan {
            shouldPreselectSafeAfterScan = false
            selectAllSafe()
        }
        flowState = .results
        lastScanDate = now
        isScanning = false
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        shouldPreselectSafeAfterScan = false
        isScanning = false
        flowState = .idle
    }

    // MARK: - Estimation Flow (Serial Background Scan without UI State Change)

    public func estimate(scanner: ScannerType) {
        if scanner == .all {
            estimateAll()
            return
        }

        cancelEstimation()
        isEstimating = true
        currentlyEstimatingScanner = scanner
        estimationProgressText = "Estimation en cours..."
        let scanRunner = self.scanRunner
        let startedAt = Date()

        estimationTask = Task.detached(priority: .utility) { [weak self] in
            let progressThrottle = ProgressThrottle(minimumInterval: 0.25)
            let items = await scanRunner(scanner) { [weak self] p in
                guard progressThrottle.shouldEmit() else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isEstimating else { return }
                    self.estimationProgressText = p
                }
            }

            guard !Task.isCancelled else { return }
            await self?.applyEstimate(items, for: scanner, startedAt: startedAt)
            await self?.finishEstimation()
        }
    }

    public func estimateAll() {
        cancelEstimation()
        isEstimating = true
        let concrete = ScannerType.concreteScanners
        let scanRunner = self.scanRunner

        estimationTask = Task.detached(priority: .utility) { [weak self] in
            let progressThrottle = ProgressThrottle(minimumInterval: 0.25)

            for (index, scanner) in concrete.enumerated() {
                guard !Task.isCancelled else { break }
                let startedAt = Date()

                await self?.setEstimationProgress(
                    scanner: scanner,
                    text: "[\(index + 1)/\(concrete.count)] \(scanner.rawValue)..."
                )

                let items = await scanRunner(scanner) { [weak self] p in
                    guard progressThrottle.shouldEmit() else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.isEstimating else { return }
                        self.estimationProgressText = "[\(index + 1)/\(concrete.count)] \(p)"
                    }
                }

                guard !Task.isCancelled else { break }
                await self?.applyEstimate(items, for: scanner, startedAt: startedAt)
            }

            guard !Task.isCancelled else { return }
            await self?.finishEstimation()
        }
    }

    private func setEstimationProgress(scanner: ScannerType, text: String) {
        guard !Task.isCancelled else { return }
        currentlyEstimatingScanner = scanner
        estimationProgressText = text
    }

    /// Stores an estimation result unless a scan finished after this estimate started:
    /// that scan's data is fresher and must not be overwritten by the older walk.
    private func applyEstimate(_ items: [FileItem], for scanner: ScannerType, startedAt: Date) {
        guard !Task.isCancelled else { return }
        if let existing = cachedSnapshots[scanner.id], existing.scanDate > startedAt {
            return
        }
        let isSelected = selectedScanner == scanner
        if isSelected && isScanning {
            return
        }

        let now = Date()
        cachedSnapshots[scanner.id] = CachedScanStore<FileItem>.Snapshot(scanDate: now, items: items)
        cacheStore.save(items: items, scanDate: now, for: scanner.id)

        if isSelected {
            scannedItems = items
            lastScanDate = now
            inMemoryItems[scanner] = items
        }
    }

    private func finishEstimation() {
        guard !Task.isCancelled else { return }
        currentlyEstimatingScanner = nil
        isEstimating = false
        estimationProgressText = ""
    }

    public func cancelEstimation() {
        estimationTask?.cancel()
        estimationTask = nil
        currentlyEstimatingScanner = nil
        isEstimating = false
        estimationProgressText = ""
    }

    private nonisolated static func runScanner(_ scanner: ScannerType, progressHandler: @Sendable @escaping (String) -> Void) async -> [FileItem] {
        switch scanner {
        case .resolve:
            return await ResolveScanner().scan(progressHandler: progressHandler)
        case .photo:
            return await PhotoAppsScanner().scan(progressHandler: progressHandler)
        case .apps:
            return await AppCacheScanner().scan(progressHandler: progressHandler)
        case .dev:
            return await DevArtefactScanner().scan(progressHandler: progressHandler)
        case .claude:
            return await ClaudeCodeScanner().scan(progressHandler: progressHandler)
        case .browsers:
            return await BrowserCacheScanner().scan(progressHandler: progressHandler)
        case .system:
            return await SystemCacheScanner().scan(progressHandler: progressHandler)
        case .installers:
            return await InstallerScanner().scan(progressHandler: progressHandler)
        case .recurring:
            return await RecurringCacheScanner().scan(progressHandler: progressHandler)
        case .all:
            return []
        }
    }
    
    // MARK: - Trashing Flow

    nonisolated static func isUnchangedSinceScan(_ item: FileItem, fileManager: FileManager = .default) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: item.url.path),
              let currentDate = attributes[.modificationDate] as? Date else {
            return false
        }
        return abs(currentDate.timeIntervalSince(item.modifiedDate)) < 1
    }

    public func executeTrash(confirmDestructive: Bool = false) {
        let selectedItems = scannedItems.filter { $0.isSelected }
        guard !selectedItems.isEmpty else {
            flowState = .results
            return
        }

        let containsDestructive = selectedItems.contains { $0.riskTier == .destructive }
        if containsDestructive && !confirmDestructive {
            flowState = .results
            return
        }

        let freshItems = selectedItems.filter { Self.isUnchangedSinceScan($0) }
        staleSkippedCount = selectedItems.count - freshItems.count
        lastTrashErrorMessage = nil
        guard !freshItems.isEmpty else {
            flowState = .results
            return
        }

        // Each item must still resolve inside the directory it was scanned in: an item
        // that became a symlink to somewhere else since the scan is refused.
        let requests = freshItems.map {
            TrashRequest(url: $0.url, scanRoot: SafetyGate.containmentRoot(for: $0.url))
        }
        flowState = .trashing(progress: "Preparing batch...", done: 0, total: requests.count)

        trashTask?.cancel()
        let trashService = self.trashService
        trashTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try await trashService.trashBatch(requests: requests) { [weak self] done, total in
                    Task { @MainActor [weak self] in
                        guard let self, case .trashing = self.flowState else { return }
                        self.flowState = .trashing(progress: "Moving items...", done: done, total: total)
                    }
                }

                guard !Task.isCancelled else { return }
                await self?.applyTrashResult(result)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.failTrash(error)
            }
        }
    }

    /// Removes only the items that actually reached the Trash. Refused or failed items
    /// stay listed (and in the persisted cache) so the user can see and retry them.
    private func applyTrashResult(_ result: TrashBatchResult) {
        guard !Task.isCancelled else { return }
        let trashedSet = Set(result.items.filter(\.isSuccess).map { $0.sourceURL.standardizedFileURL })

        stagingService.removeItems(urls: trashedSet)
        if !stagingService.hasStagedItems {
            stagingService.clearAll()
        }

        scannedItems.removeAll { trashedSet.contains($0.url.standardizedFileURL) }
        let remainingItems = scannedItems
        let now = Date()
        lastScanDate = now

        if selectedScanner == .all {
            for scanner in ScannerType.concreteScanners {
                if let existing = cachedSnapshots[scanner.id] {
                    let updated = existing.items.filter { !trashedSet.contains($0.url.standardizedFileURL) }
                    storeSnapshot(updated, for: scanner, scanDate: now)
                }
            }
        } else {
            storeSnapshot(remainingItems, for: selectedScanner, scanDate: now)
        }

        flowState = .completed(result: result)
    }

    /// The batch was refused as a whole (safety caps): nothing moved, so every item stays.
    private func failTrash(_ error: Error) {
        guard !Task.isCancelled else { return }
        lastTrashErrorMessage = "Nothing was moved to the Trash: \(error.localizedDescription)"
        flowState = .results
    }

    public func cancelTrash() {
        trashTask?.cancel()
        trashTask = nil
        flowState = .results
    }

    public func switchToScannerSelection() {
        flowState = .idle
    }
    
    public func resetToIdle() {
        flowState = .idle
        isScanning = false
        scannedItems = []
        lastScanDate = nil
    }
    
    public func clearCache() {
        resetToIdle()
        cachedSnapshots = [:]
        inMemoryItems = [:]
        cacheStore.clear()
    }
}

/// Rate limiter for scan progress messages.
private final class ProgressThrottle: @unchecked Sendable {
    private let minimumInterval: TimeInterval
    private let lock = NSLock()
    private var lastEmitDate = Date.distantPast

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func shouldEmit(at date: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard date.timeIntervalSince(lastEmitDate) >= minimumInterval else { return false }
        lastEmitDate = date
        return true
    }
}

