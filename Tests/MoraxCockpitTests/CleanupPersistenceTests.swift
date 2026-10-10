import XCTest
import Foundation
@testable import MoraxCockpitKit

final class CleanupPersistenceTests: XCTestCase {
    
    func testFileItemCodable() throws {
        let testURL = URL(fileURLWithPath: "/Users/tester/Library/Caches/com.apple.Safari/Cache.db")
        let item = FileItem(
            id: UUID(),
            url: testURL,
            name: "Cache.db",
            sizeBytes: 15_000_000,
            modifiedDate: Date(),
            category: .browserSafariCache,
            riskTier: .safe,
            riskReason: "Safari page cache",
            isRecent: false,
            isSelected: true,
            details: "Detailed cache note"
        )
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(item)
        XCTAssertFalse(data.isEmpty)
        
        let decoder = PropertyListDecoder()
        let decoded = try decoder.decode(FileItem.self, from: data)
        
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.url.path, testURL.path)
        XCTAssertEqual(decoded.name, "Cache.db")
        XCTAssertEqual(decoded.sizeBytes, 15_000_000)
        XCTAssertEqual(decoded.category, .browserSafariCache)
        XCTAssertEqual(decoded.riskTier, .safe)
        XCTAssertEqual(decoded.riskReason, "Safari page cache")
        XCTAssertEqual(decoded.isSelected, true)
        XCTAssertEqual(decoded.details, "Detailed cache note")
    }
    
    func testCleanupSnapshotCodable() throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.dmg")
        let item = FileItem(
            url: testURL,
            name: "test.dmg",
            sizeBytes: 80_000_000,
            modifiedDate: Date(),
            category: .installerDMG,
            riskTier: .rebuildCost
        )
        
        let snapshot = CleanupSnapshot(
            scannerRawValue: ScannerType.installers.rawValue,
            lastScanDate: Date(),
            items: [item]
        )
        
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(snapshot)
        
        let decoder = PropertyListDecoder()
        let decoded = try decoder.decode(CleanupSnapshot.self, from: data)
        
        XCTAssertEqual(decoded.scannerRawValue, ScannerType.installers.rawValue)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items.first?.name, "test.dmg")
    }
    
    @MainActor
    func testCleanupStateServicePersistenceLifecycle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_cleanup_cache_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 1. Initial state (empty)
        let service1 = CleanupStateService(customCacheDirectory: tempDir)
        XCTAssertFalse(service1.hasLoadedOnce)
        XCTAssertTrue(service1.scannedItems.isEmpty)
        XCTAssertEqual(service1.flowState, .idle)
        
        // 2. Set scanned items and save to disk
        let testURL = URL(fileURLWithPath: "/tmp/sample_render.mov")
        let sampleItem = FileItem(
            url: testURL,
            name: "sample_render.mov",
            sizeBytes: 10_000_000,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .safe
        )
        service1.selectedScanner = .resolve
        service1.scannedItems = [sampleItem]
        service1.lastScanDate = Date()
        service1.flowState = .results
        service1.saveCacheToDisk(synchronously: true)
        
        let cacheFile = tempDir.appendingPathComponent("cleanup_cache.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path), "Cleanup cache file should be created")
        
        // 3. New service instance simulating app restart
        let service2 = CleanupStateService(customCacheDirectory: tempDir)
        XCTAssertTrue(service2.hasLoadedOnce, "Service should restore state from disk cache")
        XCTAssertEqual(service2.selectedScanner, .resolve)
        XCTAssertEqual(service2.scannedItems.count, 1)
        XCTAssertEqual(service2.scannedItems.first?.name, "sample_render.mov")
        XCTAssertNotNil(service2.lastScanDate)
        XCTAssertNotNil(service2.formattedLastScanDate)
        
        // 4. Clear cache
        service2.clearCache()
        XCTAssertEqual(service2.flowState, .idle)
        XCTAssertTrue(service2.scannedItems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path), "Cache file should be removed on clear")
        
        // 5. Subsequent instance
        let service3 = CleanupStateService(customCacheDirectory: tempDir)
        XCTAssertFalse(service3.hasLoadedOnce)
        XCTAssertTrue(service3.scannedItems.isEmpty)
        XCTAssertEqual(service3.flowState, .idle)
    }

    @MainActor
    func testMultiScannerCachingAndSummaryDerivation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_multiscanner_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = CleanupStateService(customCacheDirectory: tempDir)

        // 1. Initially no summaries
        XCTAssertNil(service.cachedSummary(for: .resolve))
        XCTAssertNil(service.cachedSummary(for: .photo))
        XCTAssertEqual(service.coverageSummary.available, 0)
        XCTAssertEqual(service.coverageSummary.total, ScannerType.concreteScanners.count)

        // 2. Save Resolve items including a blocked item
        let resolveSafe = FileItem(
            url: URL(fileURLWithPath: "/tmp/resolve_safe.cache"),
            name: "resolve_safe.cache",
            sizeBytes: 10_000_000,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .safe
        )
        let resolveBlocked = FileItem(
            url: URL(fileURLWithPath: "/tmp/resolve_blocked.cache"),
            name: "resolve_blocked.cache",
            sizeBytes: 99_000_000,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .blocked
        )
        service.selectedScanner = .resolve
        service.scannedItems = [resolveSafe, resolveBlocked]
        let scanDateResolve = Date()
        service.lastScanDate = scanDateResolve
        service.saveCacheToDisk(synchronously: true)

        // 3. Save Photo items
        let photoItem = FileItem(
            url: URL(fileURLWithPath: "/tmp/lr_previews.lrdata"),
            name: "lr_previews.lrdata",
            sizeBytes: 25_000_000,
            modifiedDate: Date(),
            category: .lightroomPreviews,
            riskTier: .rebuildCost
        )
        service.selectedScanner = .photo
        service.scannedItems = [photoItem]
        let scanDatePhoto = Date()
        service.lastScanDate = scanDatePhoto
        service.saveCacheToDisk(synchronously: true)

        // 4. Verify summaries derive non-blocked items correctly
        let resolveSummary = try XCTUnwrap(service.cachedSummary(for: .resolve))
        XCTAssertEqual(resolveSummary.bytes, 10_000_000, "Blocked tier items must be excluded from summary bytes")
        XCTAssertEqual(resolveSummary.itemCount, 1, "Blocked tier items must be excluded from count")
        XCTAssertFalse(resolveSummary.isStale)

        let photoSummary = try XCTUnwrap(service.cachedSummary(for: .photo))
        XCTAssertEqual(photoSummary.bytes, 25_000_000)
        XCTAssertEqual(photoSummary.itemCount, 1)
        XCTAssertFalse(photoSummary.isStale)

        // 5. Verify All Scanners aggregate
        let allSummary = try XCTUnwrap(service.cachedSummary(for: .all))
        XCTAssertEqual(allSummary.bytes, 35_000_000)
        XCTAssertEqual(allSummary.itemCount, 2)
        XCTAssertEqual(service.coverageSummary.available, 2)
        XCTAssertEqual(service.coverageSummary.total, ScannerType.concreteScanners.count)

        // 6. Reload from disk in a fresh instance
        let reloadedService = CleanupStateService(customCacheDirectory: tempDir)
        XCTAssertEqual(reloadedService.coverageSummary.available, 2)
        let reloadedResolve = try XCTUnwrap(reloadedService.cachedSummary(for: .resolve))
        XCTAssertEqual(reloadedResolve.bytes, 10_000_000)
        let reloadedPhoto = try XCTUnwrap(reloadedService.cachedSummary(for: .photo))
        XCTAssertEqual(reloadedPhoto.bytes, 25_000_000)
    }

    @MainActor
    func testNavigationFlowAndSelectionPreservation() throws {
        // Temp cache directory: never load the user's real cleanup cache into test state.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupNavTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = CleanupStateService(customCacheDirectory: tempDir)
        
        let item1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/item1.cache"),
            name: "item1.cache",
            sizeBytes: 1_000,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .safe,
            isSelected: true
        )
        let item2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/item2.cache"),
            name: "item2.cache",
            sizeBytes: 2_000,
            modifiedDate: Date(),
            category: .resolveRenderCache,
            riskTier: .safe,
            isSelected: false
        )
        
        service.selectedScanner = .resolve
        service.scannedItems = [item1, item2]
        service.flowState = .results
        
        XCTAssertEqual(service.selectedCount, 1)
        
        // 1. Navigate results -> selection -> results on same scanner
        service.switchToScannerSelection()
        XCTAssertEqual(service.flowState, .idle)
        XCTAssertEqual(service.selectedScanner, .resolve)
        
        service.flowState = .results
        XCTAssertEqual(service.selectedCount, 1, "Checkbox selection must be preserved when returning to results")
        XCTAssertEqual(service.scannedItems[0].isSelected, true)
        XCTAssertEqual(service.scannedItems[1].isSelected, false)
        
        // 2. Cancellation of scanning returns strictly to .idle
        service.flowState = .scanning(progress: "Scanning test...")
        service.cancelScan()
        XCTAssertEqual(service.flowState, .idle)
    }
}
