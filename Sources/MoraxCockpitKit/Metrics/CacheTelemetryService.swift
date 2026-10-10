import Foundation
import SwiftUI

public struct AppCacheItemDetail: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let categoryDescription: String
    
    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        sizeBytes: Int64,
        categoryDescription: String
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.categoryDescription = categoryDescription
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct AppCacheDomainMetrics: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let shortName: String
    public let iconName: String
    public let accentColorHex: String
    public let sizeBytes: Int64
    public let items: [AppCacheItemDetail]
    
    public init(
        id: String,
        name: String,
        shortName: String,
        iconName: String,
        accentColorHex: String,
        sizeBytes: Int64,
        items: [AppCacheItemDetail] = []
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.iconName = iconName
        self.accentColorHex = accentColorHex
        self.sizeBytes = sizeBytes
        self.items = items
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct CacheSnapshot: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let resolveSizeBytes: Int64
    public let lightroomSizeBytes: Int64
    public let photoshopSizeBytes: Int64
    public let captureOneSizeBytes: Int64
    public let cloudSizeBytes: Int64
    public let browsersSizeBytes: Int64
    public let systemSizeBytes: Int64
    
    public let domains: [AppCacheDomainMetrics]
    public let browserBreakdown: [String: Int64]
    
    public init(
        timestamp: Date = Date(),
        resolveSizeBytes: Int64 = 0,
        lightroomSizeBytes: Int64 = 0,
        photoshopSizeBytes: Int64 = 0,
        captureOneSizeBytes: Int64 = 0,
        cloudSizeBytes: Int64 = 0,
        browsersSizeBytes: Int64 = 0,
        systemSizeBytes: Int64 = 0,
        domains: [AppCacheDomainMetrics] = [],
        browserBreakdown: [String: Int64] = [:]
    ) {
        self.timestamp = timestamp
        self.resolveSizeBytes = resolveSizeBytes
        self.lightroomSizeBytes = lightroomSizeBytes
        self.photoshopSizeBytes = photoshopSizeBytes
        self.captureOneSizeBytes = captureOneSizeBytes
        self.cloudSizeBytes = cloudSizeBytes
        self.browsersSizeBytes = browsersSizeBytes
        self.systemSizeBytes = systemSizeBytes
        self.domains = domains
        self.browserBreakdown = browserBreakdown
    }
    
    public var controlledAppsTotal: Int64 {
        resolveSizeBytes + lightroomSizeBytes + photoshopSizeBytes + captureOneSizeBytes + cloudSizeBytes
    }
    
    public var grandTotal: Int64 {
        controlledAppsTotal + browsersSizeBytes + systemSizeBytes
    }
    
    public var formattedControlledAppsTotal: String {
        ByteCountFormatter.string(fromByteCount: controlledAppsTotal, countStyle: .file)
    }
    
    public var formattedGrandTotal: String {
        ByteCountFormatter.string(fromByteCount: grandTotal, countStyle: .file)
    }
    
    public var formattedBrowsersTotal: String {
        ByteCountFormatter.string(fromByteCount: browsersSizeBytes, countStyle: .file)
    }
    
    public var formattedSystemTotal: String {
        ByteCountFormatter.string(fromByteCount: systemSizeBytes, countStyle: .file)
    }
}

@Observable
@MainActor
public final class CacheTelemetryService {
    public static let shared = CacheTelemetryService()
    private static let storageKey = "morax_cockpit_cached_cache_snapshot"
    
    public var snapshot = CacheSnapshot()
    public var isScanning = false
    public var lastScannedDate: Date? = nil
    
    private var backgroundTask: Task<Void, Never>? = nil
    
    public init() {
        // Load persisted cache snapshot from disk/UserDefaults if available
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let cached = try? JSONDecoder().decode(CacheSnapshot.self, from: data) {
            self.snapshot = cached
            self.lastScannedDate = cached.timestamp
        }
    }
    
    /// Returns formatted last scan date description (e.g. "Aujourd'hui à 11:45" or "17/08/2026 11:45")
    public var formattedLastScanDate: String? {
        guard let date = lastScannedDate else { return nil }
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
    
    /// Asynchronously refreshes all cache telemetry metrics without blocking the UI.
    ///
    /// Unless `force` is set, a scan younger than `maxAge` is reused instead of being
    /// recomputed: walking every cache directory is expensive and the totals barely
    /// move minute to minute. Explicit user refreshes pass `force: true`.
    public func refreshCacheTelemetry(force: Bool = false, maxAge: TimeInterval = 3600) async {
        guard !isScanning else { return }
        if !force, let lastScannedDate, Date().timeIntervalSince(lastScannedDate) < maxAge {
            return
        }
        isScanning = true
        
        let newSnapshot = await Task.detached(priority: .userInitiated) {
            await Self.collectSnapshot()
        }.value
        
        self.snapshot = newSnapshot
        self.lastScannedDate = newSnapshot.timestamp
        DiagnosticService.shared.ingestCache(newSnapshot)
        self.isScanning = false
        
        // Persist to disk/UserDefaults
        if let data = try? JSONEncoder().encode(newSnapshot) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    /// Starts periodic background telemetry updates.
    /// Uses cached data immediately if fresh (< 24h), and schedules daily automatic refresh.
    public func startMonitoring(dailyMaxAge: TimeInterval = 86400, checkInterval: TimeInterval = 3600) {
        guard backgroundTask == nil else { return }
        
        // 1. If we have never scanned or if the cached scan is older than 24h (1 day), run initial background scan
        Task {
            await refreshCacheTelemetry(maxAge: dailyMaxAge)
        }
        
        // 2. Periodic background checker (checks every hour if 24 hours elapsed)
        backgroundTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                guard let self = self else { break }
                
                let shouldRescan = await MainActor.run {
                    if let lastDate = self.lastScannedDate {
                        return Date().timeIntervalSince(lastDate) >= dailyMaxAge
                    }
                    return true
                }
                
                if shouldRescan {
                    await self.refreshCacheTelemetry(maxAge: dailyMaxAge)
                }
            }
        }
    }
    
    public func stopMonitoring() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }
    
    // MARK: - Snapshot Collector
    
    public static func collectSnapshot() async -> CacheSnapshot {
        // Run scanners in parallel
        async let resolveItemsTask = ResolveScanner().scan()
        async let photoItemsTask = PhotoAppsScanner().scan()
        async let claudeItemsTask = ClaudeCodeScanner().scan()
        async let browserItemsTask = BrowserCacheScanner().scan()
        async let systemItemsTask = SystemCacheScanner().scan()
        
        let resolveItems = await resolveItemsTask
        let photoItems = await photoItemsTask
        let claudeItems = await claudeItemsTask
        let browserItems = await browserItemsTask
        let systemItems = await systemItemsTask
        
        // 1. Resolve
        let resolveSize = resolveItems.reduce(0) { $0 + $1.sizeBytes }
        let resolveDetails = resolveItems.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        
        // 2. Lightroom
        let lrCategories: Set<CleanupCategory> = [.lightroomPreviews, .lightroomSmartPreviews, .lightroomAppCache]
        let lrItems = photoItems.filter { lrCategories.contains($0.category) }
        let lrSize = lrItems.reduce(0) { $0 + $1.sizeBytes }
        let lrDetails = lrItems.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        
        // 3. Photoshop
        let psItems = photoItems.filter { $0.category == .photoshopCache }
        let psSize = psItems.reduce(0) { $0 + $1.sizeBytes }
        let psDetails = psItems.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        
        // 4. Capture One
        let c1Categories: Set<CleanupCategory> = [.captureOneSessionCache, .captureOneCatalogCache, .captureOneAppCache]
        let c1Items = photoItems.filter { c1Categories.contains($0.category) }
        let c1Size = c1Items.reduce(0) { $0 + $1.sizeBytes }
        let c1Details = c1Items.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        
        // 5. Cloud (Claude Code + Creative Cloud Caches)
        let claudeSize = claudeItems.reduce(0) { $0 + $1.sizeBytes }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let ccDirs = [
            home.appendingPathComponent("Library/Caches/Adobe/CCX Welcome"),
            home.appendingPathComponent("Library/Caches/Adobe/Creative Cloud Libraries"),
            home.appendingPathComponent("Library/Caches/Adobe/CoreSync")
        ]
        var extraCloudSize: Int64 = 0
        var extraCloudDetails: [AppCacheItemDetail] = []
        for dir in ccDirs where fm.fileExists(atPath: dir.path) {
            let s = TrashService.shared.calculateSize(url: dir)
            if s > 0 {
                extraCloudSize += s
                extraCloudDetails.append(AppCacheItemDetail(
                    name: "Creative Cloud/\(dir.lastPathComponent)",
                    path: dir.path,
                    sizeBytes: s,
                    categoryDescription: "Adobe Creative Cloud Cache"
                ))
            }
        }
        let totalCloudSize = claudeSize + extraCloudSize
        var cloudDetails = claudeItems.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        cloudDetails.append(contentsOf: extraCloudDetails)
        
        // 6. Browsers
        let browserSize = browserItems.reduce(0) { $0 + $1.sizeBytes }
        var browserMap: [String: Int64] = [:]
        for item in browserItems {
            let key: String
            switch item.category {
            case .browserSafariCache: key = "Safari"
            case .browserChromeCache: key = "Chrome"
            case .browserArcCache: key = "Arc"
            case .browserBraveCache: key = "Brave"
            case .browserFirefoxCache: key = "Firefox"
            case .browserEdgeCache: key = "Edge"
            default: key = "Other"
            }
            browserMap[key, default: 0] += item.sizeBytes
        }
        let browserDetails = browserItems.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        
        // 7. System
        let systemSize = systemItems.reduce(0) { $0 + $1.sizeBytes }
        let systemDetails = systemItems.map {
            AppCacheItemDetail(name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes, categoryDescription: $0.category.rawValue)
        }
        
        // Build Domain Models
        let domains: [AppCacheDomainMetrics] = [
            AppCacheDomainMetrics(
                id: "resolve",
                name: "DaVinci Resolve",
                shortName: "Resolve",
                iconName: "film",
                accentColorHex: "#C8463A",
                sizeBytes: resolveSize,
                items: resolveDetails
            ),
            AppCacheDomainMetrics(
                id: "lightroom",
                name: "Adobe Lightroom",
                shortName: "Lightroom",
                iconName: "photo.stack",
                accentColorHex: "#31A8FF",
                sizeBytes: lrSize,
                items: lrDetails
            ),
            AppCacheDomainMetrics(
                id: "photoshop",
                name: "Adobe Photoshop & ACR",
                shortName: "Photoshop",
                iconName: "wand.and.stars",
                accentColorHex: "#31A8FF",
                sizeBytes: psSize,
                items: psDetails
            ),
            AppCacheDomainMetrics(
                id: "captureOne",
                name: "Capture One Pro",
                shortName: "Capture One",
                iconName: "camera.aperture",
                accentColorHex: "#D97706",
                sizeBytes: c1Size,
                items: c1Details
            ),
            AppCacheDomainMetrics(
                id: "cloud",
                name: "Cloud (Claude & Creative Cloud)",
                shortName: "Cloud",
                iconName: "icloud",
                accentColorHex: "#8B5CF6",
                sizeBytes: totalCloudSize,
                items: cloudDetails
            ),
            AppCacheDomainMetrics(
                id: "browsers",
                name: "Web Browsers",
                shortName: "Browsers",
                iconName: "globe",
                accentColorHex: "#10B981",
                sizeBytes: browserSize,
                items: browserDetails
            ),
            AppCacheDomainMetrics(
                id: "system",
                name: "macOS System & Logs",
                shortName: "System",
                iconName: "internaldrive",
                accentColorHex: "#6B7280",
                sizeBytes: systemSize,
                items: systemDetails
            )
        ]
        
        return CacheSnapshot(
            timestamp: Date(),
            resolveSizeBytes: resolveSize,
            lightroomSizeBytes: lrSize,
            photoshopSizeBytes: psSize,
            captureOneSizeBytes: c1Size,
            cloudSizeBytes: totalCloudSize,
            browsersSizeBytes: browserSize,
            systemSizeBytes: systemSize,
            domains: domains,
            browserBreakdown: browserMap
        )
    }
}
