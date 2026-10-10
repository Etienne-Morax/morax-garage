import XCTest
import Foundation
@testable import MoraxCockpitKit

@MainActor
final class TabMemoryStateServicesTests: XCTestCase {
    nonisolated(unsafe) private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        // These services persist their scans, so each test needs its own directory:
        // sharing the real one would leak results from one run into the next.
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TabMemoryStateServicesTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let cacheDirectory {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        cacheDirectory = nil
        super.tearDown()
    }

    func testAppsStateServiceCaching() async {
        let service = AppsStateService(customCacheDirectory: cacheDirectory)
        XCTAssertFalse(service.hasLoadedOnce)
        XCTAssertTrue(service.apps.isEmpty)
        
        await service.loadApps(force: false)
        XCTAssertTrue(service.hasLoadedOnce)
        XCTAssertFalse(service.isLoading)
        XCTAssertFalse(service.isScanning)
        XCTAssertNotNil(service.lastScanDate)
        
        let initialScanDate = service.lastScanDate
        
        // Calling loadApps without force should keep cached data without re-executing
        await service.loadApps(force: false)
        XCTAssertEqual(service.lastScanDate, initialScanDate)
    }
    
    func testAuditStateServiceCaching() async {
        let service = AuditStateService(customCacheDirectory: cacheDirectory)
        XCTAssertFalse(service.hasLoadedOnce)
        XCTAssertTrue(service.items.isEmpty)
        
        await service.loadAudit(force: false)
        XCTAssertTrue(service.hasLoadedOnce)
        XCTAssertFalse(service.isLoading)
        XCTAssertFalse(service.isScanning)
        XCTAssertNotNil(service.lastScanDate)
        
        let initialScanDate = service.lastScanDate
        await service.loadAudit(force: false)
        XCTAssertEqual(service.lastScanDate, initialScanDate)
    }
    
    func testEnvironmentStateServiceCaching() async {
        let service = EnvironmentStateService(customCacheDirectory: cacheDirectory)
        XCTAssertFalse(service.hasLoadedOnce)
        XCTAssertTrue(service.tools.isEmpty)
        
        await service.loadTools(force: false)
        XCTAssertTrue(service.hasLoadedOnce)
        XCTAssertFalse(service.isLoading)
        XCTAssertFalse(service.isScanning)
        XCTAssertNotNil(service.lastScanDate)
        
        let initialScanDate = service.lastScanDate
        await service.loadTools(force: false)
        XCTAssertEqual(service.lastScanDate, initialScanDate)
    }
    
    func testAppsStateServiceReusesPersistedScanOnNextLaunch() async {
        let first = AppsStateService(customCacheDirectory: cacheDirectory)
        await first.loadApps(force: false)
        let scanDate = first.lastScanDate
        XCTAssertNotNil(scanDate)

        // Persistence is written off the main actor, so give it a moment to land.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let second = AppsStateService(customCacheDirectory: cacheDirectory)
        XCTAssertTrue(second.hasLoadedOnce)
        XCTAssertTrue(second.hasFreshCache)
        XCTAssertEqual(second.lastScanDate, scanDate)
        XCTAssertEqual(second.apps.count, first.apps.count)

        // A fresh cache means no rescan.
        await second.loadApps(force: false)
        XCTAssertEqual(second.lastScanDate, scanDate)
    }

    func testBrewStateServiceInitialState() {
        let service = BrewStateService()
        XCTAssertFalse(service.hasLoadedOnce)
        XCTAssertNil(service.report)
        XCTAssertNil(service.errorMessage)
        XCTAssertFalse(service.isLoading)
        XCTAssertFalse(service.isScanning)
    }
    
    func testCleanupStateServiceWorkflow() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-cleanup-\(UUID().uuidString)")
        let service = CleanupStateService(customCacheDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        XCTAssertEqual(service.flowState, .idle)
        XCTAssertEqual(service.selectedScanner, .resolve)
        XCTAssertTrue(service.scannedItems.isEmpty)
        
        // Set mock items
        let testURL1 = URL(fileURLWithPath: "/tmp/mock_file_1.cache")
        let testURL2 = URL(fileURLWithPath: "/tmp/mock_file_2.cache")
        let item1 = FileItem(
            url: testURL1,
            name: "Mock 1",
            sizeBytes: 1024 * 1024,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .safe,
            riskReason: "Safe cache",
            isRecent: false,
            isSelected: true
        )
        let item2 = FileItem(
            url: testURL2,
            name: "Mock 2",
            sizeBytes: 2048 * 1024,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .safe,
            riskReason: "Safe cache",
            isRecent: false,
            isSelected: false
        )
        
        service.scannedItems = [item1, item2]
        service.flowState = .results
        
        XCTAssertEqual(service.selectedCount, 1)
        XCTAssertEqual(service.totalReclaimableBytes, 1024 * 1024)
        
        service.selectAllSafe()
        XCTAssertEqual(service.selectedCount, 2)
        XCTAssertEqual(service.totalReclaimableBytes, 3072 * 1024)
        
        service.deselectAll()
        XCTAssertEqual(service.selectedCount, 0)
        XCTAssertEqual(service.totalReclaimableBytes, 0)
        
        service.resetToIdle()
        XCTAssertEqual(service.flowState, .idle)
        XCTAssertTrue(service.scannedItems.isEmpty)
    }
    
    func testCleanupStateServiceStartScanAndComplete() async throws {
        // Isolated instance: temp cache directory and a stub scanner, so the test neither
        // walks the real Downloads folder nor rewrites the user's persisted cleanup cache.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-cleanup-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let stubItem = FileItem(
            url: tempDir.appendingPathComponent("stub.dmg"),
            sizeBytes: 1_000,
            modifiedDate: Date(),
            category: .installerDMG,
            riskTier: .safe
        )
        let service = CleanupStateService(customCacheDirectory: tempDir, scanRunner: { _, _ in [stubItem] })
        service.selectedScanner = .installers
        service.startScan()

        // Wait for flowState to become .results (with timeout)
        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline {
            if case .results = service.flowState {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        if case .results = service.flowState {
            // Results land on this instance, not on the shared singleton
            XCTAssertEqual(service.scannedItems.map(\.url), [stubItem.url])
            XCTAssertEqual(service.cachedSnapshots[ScannerType.installers.id]?.items.count, 1)
        } else {
            XCTFail("CleanupStateService failed to reach .results state in time: \(service.flowState)")
        }
        
        service.resetToIdle()
    }
}
