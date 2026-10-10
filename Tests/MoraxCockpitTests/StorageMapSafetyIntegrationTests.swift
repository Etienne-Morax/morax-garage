import XCTest
import Foundation
@testable import MoraxCockpitKit

final class StorageMapSafetyIntegrationTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            CleanupStagingService.shared.clearAll()
        }
    }
    
    override func tearDown() async throws {
        await MainActor.run {
            CleanupStagingService.shared.clearAll()
        }
        try await super.tearDown()
    }
    
    @MainActor
    func testStageValidNodeAddsToStagingService() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("valid_cache_\(UUID().uuidString).cache")
        try? "cache content".data(using: .utf8)?.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let node = StorageNode(
            url: fileURL,
            name: fileURL.lastPathComponent,
            logicalSizeBytes: 1024,
            allocatedSizeBytes: 4096,
            category: .systemAndCache
        )
        
        let result = CleanupStagingService.shared.stageNode(node)
        
        switch result {
        case .success(let item):
            XCTAssertEqual(item.url.standardizedFileURL, fileURL.standardizedFileURL)
            XCTAssertFalse(item.isSelected, "A staged node must never arrive pre-selected")
            XCTAssertEqual(item.details, "Staged from Storage Map (\(node.category.rawValue))")
        case .failure(let error):
            XCTFail("Valid file should have been staged successfully: \(error)")
        }
    }
    
    @MainActor
    func testStageSystemProtectedPathFailsWithSafetyGateError() {
        let systemURL = URL(fileURLWithPath: "/System/Library/CoreServices")
        let systemNode = StorageNode(
            url: systemURL,
            name: "CoreServices",
            category: .systemAndCache
        )
        
        let result = CleanupStagingService.shared.stageNode(systemNode)
        
        switch result {
        case .success:
            XCTFail("System protected path must NEVER be staged for cleanup!")
        case .failure(let error):
            if case .pathIsDenylisted = error {
                // Expected
            } else {
                XCTFail("Expected pathIsDenylisted error, got: \(error)")
            }
        }
    }
    
    @MainActor
    func testStageResolveProjectDatabaseFailsWithSafetyGateError() {
        let resolveDbURL = FileManager.default.temporaryDirectory.appendingPathComponent("Resolve Projects/Project.db")
        try? FileManager.default.createDirectory(at: resolveDbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "db".data(using: .utf8)?.write(to: resolveDbURL)
        defer { try? FileManager.default.removeItem(at: resolveDbURL.deletingLastPathComponent()) }
        
        let dbNode = StorageNode(
            url: resolveDbURL,
            name: "Project.db",
            category: .videoAndRender
        )
        
        let result = CleanupStagingService.shared.stageNode(dbNode)
        
        switch result {
        case .success:
            XCTFail("DaVinci Resolve project database must NEVER be staged for cleanup!")
        case .failure(let error):
            if case .resolveProjectDataProtected = error {
                // Expected
            } else {
                XCTFail("Expected resolveProjectDataProtected error, got: \(error)")
            }
        }
    }
    
    @MainActor
    func testStageMasterRawMediaFailsWithSafetyGateError() {
        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("Shoot/Master_001.CR3")
        try? FileManager.default.createDirectory(at: rawURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "raw".data(using: .utf8)?.write(to: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL.deletingLastPathComponent()) }
        
        let rawNode = StorageNode(
            url: rawURL,
            name: "Master_001.CR3",
            category: .photoAndRaw
        )
        
        let result = CleanupStagingService.shared.stageNode(rawNode)
        
        switch result {
        case .success:
            XCTFail("Master RAW photo must NEVER be staged for cleanup!")
        case .failure(let error):
            if case .photoAppMasterDataProtected = error {
                // Expected
            } else {
                XCTFail("Expected photoAppMasterDataProtected error, got: \(error)")
            }
        }
    }
    
    func testStagedItemsCanBeProcessedThroughTrashServiceAndLogged() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "test_staging_trash") { tempDir in
            let logDir = tempDir.appendingPathComponent("logs")
            let customLog = OperationLog(customLogDirectory: logDir)
            let trashService = TrashService(operationLog: customLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash")))
            
            let cacheFile = tempDir.appendingPathComponent("staged_render_cache.tmp")
            try "rendered frames".data(using: .utf8)?.write(to: cacheFile)
            
            let node = StorageNode(
                url: cacheFile,
                name: "staged_render_cache.tmp",
                logicalSizeBytes: 15,
                allocatedSizeBytes: 4096,
                category: .videoAndRender
            )
            
            let stageResult = await MainActor.run {
                CleanupStagingService.shared.stageNode(node)
            }
            guard case .success(let item) = stageResult else {
                XCTFail("Failed to stage item")
                return
            }
            
            // Perform trash batch
            let trashResult = try await trashService.trashBatch(urls: [item.url], scanRoot: tempDir)
            XCTAssertEqual(trashResult.succeededCount, 1)
            XCTAssertEqual(trashResult.skippedCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
            
            // Verify operation was logged
            let entries = customLog.readEntries()
            XCTAssertFalse(entries.isEmpty)
            XCTAssertEqual(entries.first?.outcome.uppercased(), "SUCCESS")
            XCTAssertEqual(entries.first?.action.uppercased(), "TRASH")
        }
    }
}

// MARK: - Staged tier honesty

extension StorageMapSafetyIntegrationTests {
    /// A node the storage scanner could not identify as a cache must not inherit a
    /// cache label: that mislabelling is what previously allowed a Documents folder
    /// to be presented as safe to delete.
    @MainActor
    func testStagingUserDataDoesNotInheritCacheTier() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("thesis_\(UUID().uuidString).pages")
        try "user document".data(using: .utf8)?.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let node = StorageNode(
            url: fileURL,
            name: fileURL.lastPathComponent,
            logicalSizeBytes: 2048,
            allocatedSizeBytes: 4096,
            category: .documents
        )

        switch CleanupStagingService.shared.stageNode(node) {
        case .success(let item):
            XCTAssertEqual(item.category, .stagedUserData)
            XCTAssertEqual(item.riskTier, .destructive)
            XCTAssertFalse(item.isSelected)
        case .failure(let error):
            XCTFail("Staging user data should succeed but be tiered honestly: \(error)")
        }
    }

    /// Even a genuine cache node is never staged below `.rebuildCost`: the storage
    /// scanner classifies by heuristics, so a one-click "select safe" sweep must not
    /// be able to pick up whatever it guessed.
    @MainActor
    func testStagedCacheNodeIsNeverTieredSafe() throws {
        let dirURL = FileManager.default.temporaryDirectory.appendingPathComponent("cache_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let node = StorageNode(
            url: dirURL,
            name: dirURL.lastPathComponent,
            logicalSizeBytes: 1024,
            allocatedSizeBytes: 4096,
            category: .systemAndCache
        )

        switch CleanupStagingService.shared.stageNode(node) {
        case .success(let item):
            XCTAssertGreaterThanOrEqual(item.riskTier, .rebuildCost)
        case .failure(let error):
            XCTFail("Staging a cache directory should succeed: \(error)")
        }
    }
}
