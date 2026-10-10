import XCTest
import Foundation
import os
@testable import MoraxCockpitKit

/// Exercises `CleanupStateService.executeTrash`, the real deletion flow, on isolated
/// instances: temp cache directory, fake trasher (never the user's ~/.Trash), private
/// staging service and stub scanners.
@MainActor
final class CleanupExecuteTrashTests: XCTestCase {
    private static let waitTimeout: TimeInterval = 5
    private static let pollInterval: UInt64 = 10_000_000 // 10 ms

    private var rootDir: URL!
    private var cacheDir: URL!
    private var scanDir: URL!

    override func setUp() async throws {
        rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanupExecuteTrash-\(UUID().uuidString)")
        cacheDir = rootDir.appendingPathComponent("cache")
        scanDir = rootDir.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let rootDir {
            try? FileManager.default.removeItem(at: rootDir)
        }
    }

    // MARK: - Helpers

    private func makeService(failing: Set<String> = [], scanRunner: CleanupStateService.ScanRunner? = nil) -> CleanupStateService {
        CleanupStateService(
            customCacheDirectory: cacheDir,
            trashService: TestFixtures.isolatedTrashService(in: rootDir, failing: failing),
            stagingService: CleanupStagingService(),
            scanRunner: scanRunner
        )
    }

    /// Creates a file and a selected FileItem whose modification date matches the disk,
    /// so the stale-item gate lets it through.
    private func makeItem(_ name: String, tier: RiskTier = .safe, in directory: URL? = nil) throws -> FileItem {
        let url = (directory ?? scanDir).appendingPathComponent(name)
        try Data("cache \(name)".utf8).write(to: url)
        return try item(for: url, tier: tier)
    }

    private func item(for url: URL, tier: RiskTier = .safe) throws -> FileItem {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = try XCTUnwrap(attributes[.modificationDate] as? Date)
        return FileItem(
            url: url,
            sizeBytes: 16,
            modifiedDate: modified,
            category: .resolveRenderCache,
            riskTier: tier,
            isSelected: true
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(Self.waitTimeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: Self.pollInterval)
        }
    }

    private func waitForTrashToFinish(_ service: CleanupStateService) async throws {
        try await waitUntil {
            if case .trashing = service.flowState { return false }
            return true
        }
    }

    private func completedResult(_ service: CleanupStateService) throws -> TrashBatchResult {
        guard case .completed(let result) = service.flowState else {
            XCTFail("Expected .completed, got \(service.flowState)")
            throw XCTSkip("flow did not complete")
        }
        return result
    }

    // MARK: - Partial failure

    func testRemovesOnlySuccessfullyTrashedItemsAndKeepsFailedOnesListed() async throws {
        let service = makeService(failing: ["locked.cache"])
        let ok1 = try makeItem("a.cache")
        let failed = try makeItem("locked.cache")
        let ok2 = try makeItem("b.cache")
        service.scannedItems = [ok1, failed, ok2]
        service.flowState = .results

        service.executeTrash()
        try await waitForTrashToFinish(service)

        let result = try completedResult(service)
        XCTAssertEqual(result.succeededCount, 2)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(result.errors.contains { $0.contains("locked.cache") }, "The failure must be reported")

        XCTAssertEqual(service.scannedItems.map(\.url), [failed.url], "The failed item must stay listed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ok1.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ok2.url.path))
        XCTAssertEqual(service.cachedSnapshots[ScannerType.resolve.id]?.items.map(\.url), [failed.url])

        // The persisted cache keeps the failed item too (writes are asynchronous).
        let resolveID = ScannerType.resolve.id
        let cacheDir = self.cacheDir!
        try await waitUntil {
            CleanupStateService(customCacheDirectory: cacheDir).cachedSnapshots[resolveID]?.items.map(\.url) == [failed.url]
        }
    }

    func testBatchRefusedAsAWholeReportsErrorAndKeepsEveryItem() async throws {
        let service = makeService()
        // A sparse file whose logical size exceeds the 20 GB batch cap: no real disk use.
        let hugeURL = scanDir.appendingPathComponent("huge.cache")
        XCTAssertTrue(FileManager.default.createFile(atPath: hugeURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: hugeURL)
        try handle.truncate(atOffset: UInt64(SafetyGate.maxBatchSizeBytes) + 1)
        try handle.close()
        let huge = try item(for: hugeURL)
        service.scannedItems = [huge]
        service.flowState = .results

        service.executeTrash()
        try await waitUntil { service.flowState == .results && service.lastTrashErrorMessage != nil }

        XCTAssertEqual(service.scannedItems.map(\.url), [hugeURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: hugeURL.path))
        let message = try XCTUnwrap(service.lastTrashErrorMessage)
        XCTAssertTrue(message.contains("exceeds the safety cap"), message)
    }

    // MARK: - Symlink escape

    func testRefusesItemThatResolvesOutsideItsScanRoot() async throws {
        let service = makeService()
        let outsideDir = rootDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        let precious = outsideDir.appendingPathComponent("precious.txt")
        try Data("user data".utf8).write(to: precious)

        // The scanned "cache" entry was replaced by a link pointing outside its directory.
        let linkURL = scanDir.appendingPathComponent("escaped.cache")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: precious)
        let escaped = try item(for: linkURL)
        let regular = try makeItem("regular.cache")
        service.scannedItems = [escaped, regular]
        service.flowState = .results

        service.executeTrash()
        try await waitForTrashToFinish(service)

        let result = try completedResult(service)
        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(result.errors.contains { $0.contains("Symlink escape detected") }, "\(result.errors)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.path))
        let linkStillThere = (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) != nil
        XCTAssertTrue(linkStillThere, "The refused link must not be moved")
        XCTAssertEqual(service.scannedItems.map(\.url), [linkURL], "The refused item stays listed")
    }

    // MARK: - Gates

    func testRefusesDestructiveItemsWithoutConfirmation() async throws {
        let service = makeService()
        let destructive = try makeItem("db.cache", tier: .destructive)
        service.scannedItems = [destructive]
        service.flowState = .confirming

        service.executeTrash(confirmDestructive: false)

        XCTAssertEqual(service.flowState, .results)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destructive.url.path))
        XCTAssertEqual(service.scannedItems.count, 1)
    }

    func testSkipsItemsModifiedSinceScan() async throws {
        let service = makeService()
        let fresh = try makeItem("fresh.cache")
        let changedURL = scanDir.appendingPathComponent("changed.cache")
        try Data("x".utf8).write(to: changedURL)
        let changed = FileItem(
            url: changedURL,
            sizeBytes: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            category: .resolveRenderCache,
            riskTier: .safe,
            isSelected: true
        )
        service.scannedItems = [fresh, changed]

        service.executeTrash()
        try await waitForTrashToFinish(service)

        XCTAssertEqual(service.staleSkippedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: changedURL.path))
        XCTAssertEqual(service.scannedItems.map(\.url), [changedURL])
    }

    func testStagedItemsAreClearedOnlyWhenTrashed() async throws {
        let staging = CleanupStagingService()
        let service = CleanupStateService(
            customCacheDirectory: cacheDir,
            trashService: TestFixtures.isolatedTrashService(in: rootDir, failing: ["keep.tmp"]),
            stagingService: staging
        )
        let gone = try makeItem("gone.tmp")
        let kept = try makeItem("keep.tmp")
        for item in [gone, kept] {
            staging.stageNode(StorageNode(url: item.url, name: item.name, logicalSizeBytes: 16, allocatedSizeBytes: 16, category: .other))
        }
        XCTAssertEqual(staging.stagedItems.count, 2)
        service.scannedItems = [gone, kept]

        service.executeTrash()
        try await waitForTrashToFinish(service)

        XCTAssertEqual(staging.stagedItems.map(\.url), [kept.url])
    }

    // MARK: - Instance isolation (no writes through the singleton)

    func testEstimateWritesIntoTheInstanceThatRanIt() async throws {
        let stub = try makeItem("estimated.cache")
        let service = makeService(scanRunner: { _, _ in [stub] })

        service.estimate(scanner: .resolve)
        try await waitUntil { !service.isEstimating }

        XCTAssertEqual(service.cachedSnapshots[ScannerType.resolve.id]?.items.map(\.url), [stub.url])
        XCTAssertEqual(service.scannedItems.map(\.url), [stub.url])
    }

    func testCancelledScanDoesNotPublishLateResults() async throws {
        let stub = try makeItem("late.cache")
        let runnerReturned = OSAllocatedUnfairLock(initialState: false)
        let service = makeService(scanRunner: { _, _ in
            try? await Task.sleep(nanoseconds: 50_000_000)
            defer { runnerReturned.withLock { $0 = true } }
            return [stub]
        })

        service.startScan()
        service.cancelScan()
        // Join on the runner handing its late results back; only a main-actor hop
        // separates that from a (wrong) publication.
        try await waitUntil { runnerReturned.withLock { $0 } }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(service.flowState, .idle)
        XCTAssertFalse(service.isScanning)
        XCTAssertTrue(service.scannedItems.isEmpty)
    }

    func testOlderEstimateDoesNotOverwriteFresherScan() async throws {
        let estimated = try makeItem("old-estimate.cache")
        let scanned = try makeItem("fresh-scan.cache")
        // Estimation runs at .utility priority and is slow; the scan runs at .userInitiated.
        let service = makeService(scanRunner: { _, _ in
            if Task.currentPriority == .utility {
                try? await Task.sleep(nanoseconds: 150_000_000)
                return [estimated]
            }
            return [scanned]
        })

        service.estimate(scanner: .resolve)
        service.startScan()
        try await waitUntil { service.flowState == .results && !service.isEstimating }

        XCTAssertEqual(service.scannedItems.map(\.url), [scanned.url])
        XCTAssertEqual(service.cachedSnapshots[ScannerType.resolve.id]?.items.map(\.url), [scanned.url])
    }
}
