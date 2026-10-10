import XCTest
import Foundation
@testable import MoraxCockpitKit

@MainActor
final class StorageMapPersistenceTests: XCTestCase {
    
    func testStorageNodeCodableHierarchyAndParentRestoration() throws {
        let rootURL = URL(fileURLWithPath: "/Users/tester/Projects")
        let subDirURL = rootURL.appendingPathComponent("AppProject")
        let file1URL = subDirURL.appendingPathComponent("main.swift")
        let file2URL = subDirURL.appendingPathComponent("render.mov")
        
        let file1 = StorageNode(
            url: file1URL,
            name: "main.swift",
            logicalSizeBytes: 4_000,
            allocatedSizeBytes: 4_096,
            isDirectory: false,
            category: .devAndBuild
        )
        
        let file2 = StorageNode(
            url: file2URL,
            name: "render.mov",
            logicalSizeBytes: 50_000_000,
            allocatedSizeBytes: 50_003_968,
            isDirectory: false,
            category: .videoAndRender
        )
        
        let subDir = StorageNode(
            url: subDirURL,
            name: "AppProject",
            isDirectory: true,
            children: [file1, file2]
        )
        subDir.recalculateAggregates()
        
        let root = StorageNode(
            url: rootURL,
            name: "Projects",
            isDirectory: true,
            children: [subDir]
        )
        root.recalculateAggregates()
        
        // Encode using PropertyListEncoder (binary format used for fast disk caching)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(root)
        XCTAssertFalse(data.isEmpty)
        
        // Decode
        let decoder = PropertyListDecoder()
        let decodedRoot = try decoder.decode(StorageNode.self, from: data)
        
        // Validate root
        XCTAssertEqual(decodedRoot.id, root.id)
        XCTAssertEqual(decodedRoot.url.path, rootURL.path)
        XCTAssertEqual(decodedRoot.children.count, 1)
        XCTAssertNil(decodedRoot.parent)
        
        // Validate subDir & parent reconstruction
        let decodedSubDir = decodedRoot.children.first
        XCTAssertNotNil(decodedSubDir)
        XCTAssertEqual(decodedSubDir?.name, "AppProject")
        XCTAssertTrue(decodedSubDir?.parent === decodedRoot, "Decoded child's parent reference must point to decoded root")
        XCTAssertEqual(decodedSubDir?.children.count, 2)
        
        // Validate leaf children & parent reconstruction
        let decodedFile1 = decodedSubDir?.children.first(where: { $0.name == "main.swift" })
        let decodedFile2 = decodedSubDir?.children.first(where: { $0.name == "render.mov" })
        
        XCTAssertNotNil(decodedFile1)
        XCTAssertEqual(decodedFile1?.category, .devAndBuild)
        XCTAssertTrue(decodedFile1?.parent === decodedSubDir, "Leaf node parent must point to subDir")
        
        XCTAssertNotNil(decodedFile2)
        XCTAssertEqual(decodedFile2?.category, .videoAndRender)
        XCTAssertTrue(decodedFile2?.parent === decodedSubDir, "Leaf node parent must point to subDir")
        
        // Validate Breadcrumbs
        let breadcrumbs = decodedFile1?.breadcrumbs ?? []
        XCTAssertEqual(breadcrumbs.count, 3)
        XCTAssertEqual(breadcrumbs[0].id, decodedRoot.id)
        XCTAssertEqual(breadcrumbs[1].id, decodedSubDir?.id)
        XCTAssertEqual(breadcrumbs[2].id, decodedFile1?.id)
    }
    
    func testStorageMapSnapshotCodable() throws {
        let targetURL = URL(fileURLWithPath: "/Users/tester")
        let scanDate = Date()
        let root = StorageNode(
            url: targetURL,
            name: "tester",
            logicalSizeBytes: 1024,
            allocatedSizeBytes: 4096,
            isDirectory: true
        )
        
        let snapshot = StorageMapSnapshot(
            targetURL: targetURL,
            lastScanDate: scanDate,
            maxDepth: 3,
            rootNode: root
        )
        
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(snapshot)
        
        let decoder = PropertyListDecoder()
        let decoded = try decoder.decode(StorageMapSnapshot.self, from: data)
        
        XCTAssertEqual(decoded.targetURL.path, targetURL.path)
        XCTAssertEqual(decoded.maxDepth, 3)
        XCTAssertEqual(decoded.rootNode.name, "tester")
        XCTAssertEqual(Int(decoded.lastScanDate.timeIntervalSince1970), Int(scanDate.timeIntervalSince1970))
    }
    
    func testStorageMapStateServicePersistentCacheLifecycle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_storage_cache_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 1. Initial State (No cache on disk)
        let service1 = StorageMapStateService(customCacheDirectory: tempDir)
        await service1.restoreCacheFromDisk()
        XCTAssertNil(service1.rootNode)
        XCTAssertNil(service1.lastScanDate)
        XCTAssertFalse(service1.hasLoadedOnce)
        
        // 2. Set root node and save cache
        let rootURL = URL(fileURLWithPath: "/Users/tester/Documents")
        let sampleNode = StorageNode(
            url: rootURL,
            name: "Documents",
            logicalSizeBytes: 2048,
            allocatedSizeBytes: 4096,
            isDirectory: true
        )
        service1.rootNode = sampleNode
        service1.targetURL = rootURL
        service1.lastScanDate = Date()
        service1.saveCacheToDisk(synchronously: true)
        
        let cacheFile = tempDir.appendingPathComponent("storage_map_cache.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path), "Cache file should exist on disk")
        
        // 3. New service instance simulating app restart
        let service2 = StorageMapStateService(customCacheDirectory: tempDir)
        XCTAssertNil(service2.rootNode, "Construction alone must not decode the snapshot on the main actor")
        await service2.restoreCacheFromDisk()
        XCTAssertTrue(service2.hasLoadedOnce, "Service should restore previous scan state from disk")
        XCTAssertNotNil(service2.rootNode)
        XCTAssertEqual(service2.rootNode?.name, "Documents")
        XCTAssertEqual(service2.targetURL.path, rootURL.path)
        XCTAssertNotNil(service2.lastScanDate)
        XCTAssertNotNil(service2.formattedLastScanDate)
        
        // 4. Clear cache
        service2.clearCache()
        XCTAssertNil(service2.rootNode)
        XCTAssertNil(service2.lastScanDate)
        
        // Wait for file deletion task
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path), "Cache file should be deleted on clearCache")
        
        // 5. Subsequent service instance should find nothing
        let service3 = StorageMapStateService(customCacheDirectory: tempDir)
        await service3.restoreCacheFromDisk()
        XCTAssertNil(service3.rootNode)
        XCTAssertNil(service3.lastScanDate)
        XCTAssertFalse(service3.hasLoadedOnce)
    }

    func testOversizedCacheIsDiscardedWithoutDecoding() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_storage_cache_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cacheFile = tempDir.appendingPathComponent("storage_map_cache.plist")
        let oversized = Data(count: Int(StorageMapStateService.maxCacheFileBytes) + 1)
        try oversized.write(to: cacheFile)

        let service = StorageMapStateService(customCacheDirectory: tempDir)
        await service.restoreCacheFromDisk()

        XCTAssertNil(service.rootNode, "A snapshot past the budget must never be decoded")
        XCTAssertTrue(service.hasAttemptedRestore)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: cacheFile.path),
            "The oversized snapshot should be removed so it cannot stall a later visit"
        )
    }

    func testCollapseToCacheBudgetPreservesTotalsWhileCuttingNodes() throws {
        let rootURL = URL(fileURLWithPath: "/Users/tester/Budget")
        var children: [StorageNode] = []
        // Each entry clears the scanner floor, so only the budget itself can fold them.
        for index in 0..<400 {
            children.append(
                StorageNode(
                    url: rootURL.appendingPathComponent("file\(index).bin"),
                    name: "file\(index).bin",
                    logicalSizeBytes: 2 * 1024 * 1024,
                    allocatedSizeBytes: 2 * 1024 * 1024,
                    isDirectory: false,
                    category: .other
                )
            )
        }

        let root = StorageNode(
            url: rootURL,
            name: "Budget",
            isDirectory: true,
            children: children
        )
        root.recalculateAggregates()

        let expectedAllocated = root.allocatedSizeBytes
        let expectedLogical = root.logicalSizeBytes
        let expectedItemCount = root.itemCount

        // Folding below a threshold above every entry leaves a single aggregate behind.
        root.collapseEntries(belowAllocatedBytes: 4 * 1024 * 1024, maxDepth: StorageMapStateService.maxCachedDepth)
        root.recalculateAggregates()

        XCTAssertEqual(root.children.count, 1, "The long tail should fold into one aggregate")
        XCTAssertTrue(root.children[0].isAggregate)
        XCTAssertEqual(root.allocatedSizeBytes, expectedAllocated, "Folding must not change occupied bytes")
        XCTAssertEqual(root.logicalSizeBytes, expectedLogical, "Folding must not change logical bytes")
        XCTAssertEqual(root.itemCount, expectedItemCount, "Folding must not change the item count")
    }

    func testCollapseToCacheBudgetKeepsTreeUnderNodeCeiling() throws {
        let rootURL = URL(fileURLWithPath: "/Users/tester/Wide")
        var children: [StorageNode] = []
        for index in 0..<(StorageMapStateService.maxCachedNodeCount + 500) {
            children.append(
                StorageNode(
                    url: rootURL.appendingPathComponent("entry\(index).bin"),
                    name: "entry\(index).bin",
                    logicalSizeBytes: Int64(1_500_000 + index),
                    allocatedSizeBytes: Int64(1_500_000 + index),
                    isDirectory: false,
                    category: .other
                )
            )
        }

        let root = StorageNode(url: rootURL, name: "Wide", isDirectory: true, children: children)
        root.recalculateAggregates()
        let expectedAllocated = root.allocatedSizeBytes

        StorageMapStateService.collapseToCacheBudget(root)
        root.recalculateAggregates()

        XCTAssertLessThanOrEqual(root.nodeCount, StorageMapStateService.maxCachedNodeCount)
        XCTAssertEqual(root.allocatedSizeBytes, expectedAllocated, "The budget must not lose bytes")
    }
}
