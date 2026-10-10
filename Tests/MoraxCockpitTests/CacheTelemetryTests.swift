import XCTest
@testable import MoraxCockpitKit

final class CacheTelemetryTests: XCTestCase {
    var tempDir: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        if let tempDir = tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }
    
    // MARK: - Browser Cache Scanner Tests
    
    func testBrowserCacheScannerDetectsBrowsers() async throws {
        let cachesDir = tempDir.appendingPathComponent("Caches")
        let appSupportDir = tempDir.appendingPathComponent("AppSupport")
        let containersDir = tempDir.appendingPathComponent("Containers")
        
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containersDir, withIntermediateDirectories: true)
        
        // 1. Create Safari mock
        let safariCache = cachesDir.appendingPathComponent("com.apple.Safari")
        try FileManager.default.createDirectory(at: safariCache, withIntermediateDirectories: true)
        try "safari data".write(to: safariCache.appendingPathComponent("Cache.db"), atomically: true, encoding: .utf8)
        
        // 2. Create Chrome mock
        let chromeCache = cachesDir.appendingPathComponent("Google/Chrome")
        try FileManager.default.createDirectory(at: chromeCache, withIntermediateDirectories: true)
        try "chrome data".write(to: chromeCache.appendingPathComponent("data_0"), atomically: true, encoding: .utf8)
        
        // 3. Create Arc mock
        let arcCache = cachesDir.appendingPathComponent("company.thebrowser.Browser")
        try FileManager.default.createDirectory(at: arcCache, withIntermediateDirectories: true)
        try "arc data".write(to: arcCache.appendingPathComponent("data_0"), atomically: true, encoding: .utf8)
        
        // 4. Create Firefox mock
        let ffCache = cachesDir.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(at: ffCache, withIntermediateDirectories: true)
        try "firefox data".write(to: ffCache.appendingPathComponent("entries"), atomically: true, encoding: .utf8)
        
        let scanner = BrowserCacheScanner()
        let items = await scanner.scan(
            customCachesDirectory: cachesDir,
            customAppSupportDirectory: appSupportDir,
            customContainersDirectory: containersDir
        )
        
        XCTAssertFalse(items.isEmpty)
        
        let categories = Set(items.map { $0.category })
        XCTAssertTrue(categories.contains(.browserSafariCache))
        XCTAssertTrue(categories.contains(.browserChromeCache))
        XCTAssertTrue(categories.contains(.browserArcCache))
        XCTAssertTrue(categories.contains(.browserFirefoxCache))
        
        for item in items {
            XCTAssertFalse(item.isSelected, "Items must default to unselected")
            XCTAssertGreaterThan(item.sizeBytes, 0)
        }
    }
    
    // MARK: - System Cache Scanner Tests
    
    func testSystemCacheScannerDetectsQuickLookAndLogs() async throws {
        let cachesDir = tempDir.appendingPathComponent("Caches")
        let logsDir = tempDir.appendingPathComponent("Logs")
        
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // QuickLook cache
        let qlDir = cachesDir.appendingPathComponent("com.apple.QuickLook.thumbnailcache")
        try FileManager.default.createDirectory(at: qlDir, withIntermediateDirectories: true)
        try "thumbnail index".write(to: qlDir.appendingPathComponent("index.sqlite"), atomically: true, encoding: .utf8)
        
        // Diagnostic log
        let crashLog = logsDir.appendingPathComponent("DiagnosticReports")
        try FileManager.default.createDirectory(at: crashLog, withIntermediateDirectories: true)
        try "crash dump trace".write(to: crashLog.appendingPathComponent("test.ips"), atomically: true, encoding: .utf8)
        
        let scanner = SystemCacheScanner()
        let items = await scanner.scan(
            customCachesDirectory: cachesDir,
            customLogsDirectory: logsDir
        )
        
        XCTAssertFalse(items.isEmpty)
        let categories = Set(items.map { $0.category })
        XCTAssertTrue(categories.contains(.systemQuickLook))
        XCTAssertTrue(categories.contains(.systemLogs))
    }
    
    // MARK: - Cache Telemetry Snapshot Aggregation Tests
    
    func testCacheSnapshotTotalsAndFormatting() {
        let domains: [AppCacheDomainMetrics] = [
            AppCacheDomainMetrics(
                id: "resolve",
                name: "DaVinci Resolve",
                shortName: "Resolve",
                iconName: "film",
                accentColorHex: "#C8463A",
                sizeBytes: 10 * 1024 * 1024 * 1024 // 10 GB
            ),
            AppCacheDomainMetrics(
                id: "lightroom",
                name: "Adobe Lightroom",
                shortName: "Lightroom",
                iconName: "photo.stack",
                accentColorHex: "#31A8FF",
                sizeBytes: 5 * 1024 * 1024 * 1024 // 5 GB
            ),
            AppCacheDomainMetrics(
                id: "photoshop",
                name: "Adobe Photoshop & ACR",
                shortName: "Photoshop",
                iconName: "wand.and.stars",
                accentColorHex: "#31A8FF",
                sizeBytes: 3 * 1024 * 1024 * 1024 // 3 GB
            ),
            AppCacheDomainMetrics(
                id: "captureOne",
                name: "Capture One Pro",
                shortName: "Capture One",
                iconName: "camera.aperture",
                accentColorHex: "#D97706",
                sizeBytes: 2 * 1024 * 1024 * 1024 // 2 GB
            ),
            AppCacheDomainMetrics(
                id: "cloud",
                name: "Cloud (Claude & CC)",
                shortName: "Cloud",
                iconName: "icloud",
                accentColorHex: "#8B5CF6",
                sizeBytes: 4 * 1024 * 1024 * 1024 // 4 GB
            ),
            AppCacheDomainMetrics(
                id: "browsers",
                name: "Web Browsers",
                shortName: "Browsers",
                iconName: "globe",
                accentColorHex: "#10B981",
                sizeBytes: 6 * 1024 * 1024 * 1024 // 6 GB
            ),
            AppCacheDomainMetrics(
                id: "system",
                name: "macOS System & Logs",
                shortName: "System",
                iconName: "internaldrive",
                accentColorHex: "#6B7280",
                sizeBytes: 8 * 1024 * 1024 * 1024 // 8 GB
            )
        ]
        
        let snapshot = CacheSnapshot(
            timestamp: Date(),
            resolveSizeBytes: 10 * 1024 * 1024 * 1024,
            lightroomSizeBytes: 5 * 1024 * 1024 * 1024,
            photoshopSizeBytes: 3 * 1024 * 1024 * 1024,
            captureOneSizeBytes: 2 * 1024 * 1024 * 1024,
            cloudSizeBytes: 4 * 1024 * 1024 * 1024,
            browsersSizeBytes: 6 * 1024 * 1024 * 1024,
            systemSizeBytes: 8 * 1024 * 1024 * 1024,
            domains: domains,
            browserBreakdown: ["Safari": Int64(2) * 1024 * 1024 * 1024, "Chrome": Int64(4) * 1024 * 1024 * 1024]
        )
        
        // Controlled Apps = 10 + 5 + 3 + 2 + 4 = 24 GB
        XCTAssertEqual(snapshot.controlledAppsTotal, 24 * 1024 * 1024 * 1024)
        
        // Grand Total = 24 + 6 + 8 = 38 GB
        XCTAssertEqual(snapshot.grandTotal, 38 * 1024 * 1024 * 1024)
        
        XCTAssertFalse(snapshot.formattedControlledAppsTotal.isEmpty)
        XCTAssertFalse(snapshot.formattedGrandTotal.isEmpty)
        XCTAssertFalse(snapshot.formattedBrowsersTotal.isEmpty)
        XCTAssertFalse(snapshot.formattedSystemTotal.isEmpty)
        
        XCTAssertEqual(snapshot.domains.count, 7)
    }
}
