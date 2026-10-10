import XCTest
import Foundation
@testable import MoraxCockpitKit

/// Regression coverage for the three ways the walker used to undercount a disk:
/// hidden directories were skipped, dataless cloud placeholders were mixed into the
/// allocated total, and unreadable directories vanished without a trace.
final class StorageScannerCompletenessTests: XCTestCase {
    
    private let dotFolderFileSize = 64_000
    private let datalessLogicalSize: Int64 = 8 * 1024 * 1024
    
    /// Builds: a dotfolder with real bytes, a simulated dataless placeholder under a cloud
    /// provider root (sparse file: a size but no allocated block, exactly like a Google
    /// Drive stub), and a directory the process is not allowed to read.
    private func makeFixture(in rootDir: URL) throws -> (dotFile: URL, dataless: URL, locked: URL) {
        let fileManager = FileManager.default
        
        let dotFolder = rootDir.appendingPathComponent(".ollama/models")
        try fileManager.createDirectory(at: dotFolder, withIntermediateDirectories: true)
        let dotFile = dotFolder.appendingPathComponent("weights.gguf")
        try Data(repeating: 0xAB, count: dotFolderFileSize).write(to: dotFile)
        
        let cloudFolder = rootDir.appendingPathComponent("Library/CloudStorage/GoogleDrive-test")
        try fileManager.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        let dataless = cloudFolder.appendingPathComponent("placeholder.mov")
        XCTAssertTrue(fileManager.createFile(atPath: dataless.path, contents: nil))
        let handle = try FileHandle(forWritingTo: dataless)
        try handle.truncate(atOffset: UInt64(datalessLogicalSize))
        try handle.close()
        
        let locked = rootDir.appendingPathComponent("LockedFolder")
        try fileManager.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 4_096).write(to: locked.appendingPathComponent("hidden.bin"))
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        
        return (dotFile, dataless, locked)
    }
    
    private func restorePermissions(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    
    func testScanCountsHiddenDirectories() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_hidden") { rootDir in
            let fixture = try makeFixture(in: rootDir)
            defer { restorePermissions(fixture.locked) }
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)
            
            let dotNode = result.rootNode.findNode(byURL: fixture.dotFile)
            XCTAssertNotNil(dotNode, "A dotfolder must be walked: hidden directories hold most of a home")
            XCTAssertEqual(dotNode?.logicalSizeBytes, Int64(dotFolderFileSize))
            XCTAssertGreaterThanOrEqual(result.rootNode.allocatedSizeBytes, Int64(dotFolderFileSize))
            XCTAssertEqual(dotNode?.category, .aiAndModels)
        }
    }
    
    func testDatalessPlaceholderIsExcludedFromAllocatedButKeptAsLogical() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_dataless") { rootDir in
            let fixture = try makeFixture(in: rootDir)
            defer { restorePermissions(fixture.locked) }
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)
            
            let datalessNode = try XCTUnwrap(result.rootNode.findNode(byURL: fixture.dataless))
            XCTAssertTrue(datalessNode.isCloudPlaceholder)
            XCTAssertEqual(datalessNode.allocatedSizeBytes, 0, "A placeholder occupies no local block")
            XCTAssertEqual(datalessNode.logicalSizeBytes, datalessLogicalSize)
            XCTAssertEqual(datalessNode.category, .cloudNotDownloaded)
            
            XCTAssertEqual(result.report.datalessLogicalBytes, datalessLogicalSize)
            XCTAssertLessThan(
                result.rootNode.allocatedSizeBytes,
                datalessLogicalSize,
                "Placeholder bytes must never inflate the allocated total"
            )
            XCTAssertGreaterThanOrEqual(result.rootNode.logicalSizeBytes, datalessLogicalSize)
        }
    }
    
    func testUnreadableDirectoryIsReportedInsteadOfSwallowed() async throws {
        try XCTSkipIf(getuid() == 0, "root bypasses POSIX permissions, so nothing would be denied")
        
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_denied") { rootDir in
            let fixture = try makeFixture(in: rootDir)
            defer { restorePermissions(fixture.locked) }
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)
            
            XCTAssertFalse(result.report.isComplete, "A scan that hit a wall must not claim completeness")
            XCTAssertGreaterThanOrEqual(result.report.unreadableCount, 1)
            
            // Temp paths come back through the /var -> /private/var symlink, so the
            // directory is matched on its name rather than on an absolute prefix.
            let deniedPaths = result.report.blockingIssues.map(\.path)
            let lockedIssue = result.report.blockingIssues.first {
                $0.path.hasSuffix("/" + fixture.locked.lastPathComponent)
            }
            XCTAssertNotNil(
                lockedIssue,
                "Expected the chmod 000 directory among \(deniedPaths)"
            )
            XCTAssertEqual(lockedIssue?.kind, .posixDenied, "A user-owned chmod 000 is POSIX, not TCC")
            XCTAssertFalse(result.report.needsFullDiskAccess, "Full Disk Access cannot lift a POSIX refusal")
        }
    }

    func testErrnoClassificationSeparatesTCCFromPOSIX() {
        let me: uid_t = 501
        // Without FDA and on a user-space path, EPERM is TCC permissionDenied
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EPERM, path: "/Users/me/Library/Safari", ownerUID: me, hasFullDiskAccess: false, currentUID: me), .permissionDenied)
        // With FDA active, EPERM is recognized as systemProtected (SIP / Data Vault)
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EPERM, path: "/Library/Caches/com.apple.aned", ownerUID: 0, hasFullDiskAccess: true, currentUID: me), .systemProtected)
        // System Data Vault paths are systemProtected even if hasFullDiskAccess is false
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EPERM, path: "/System/Library/AssetsV2/test", ownerUID: 0, hasFullDiskAccess: false, currentUID: me), .systemProtected)
        // Backward compatibility without path and without FDA specified
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EPERM, ownerUID: 0, currentUID: me), .permissionDenied)
        // POSIX permissions
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EACCES, ownerUID: me, currentUID: me), .posixDenied)
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EACCES, ownerUID: 0, currentUID: me), .systemProtected)
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EACCES, ownerUID: nil, currentUID: me), .posixDenied)
        XCTAssertEqual(StorageScanner.issueKind(forErrno: EIO, ownerUID: 0, currentUID: me), .unreadable)
    }

    func testReclassifyingSystemDataVaultsMovesEPERMToSystemProtected() {
        var log = StorageScanIssueLog()
        log.record(.permissionDenied, path: "/System/Library/AssetsV2/test", message: "Operation not permitted")
        log.record(.permissionDenied, path: "/Library/Caches/com.apple.aned", message: "Operation not permitted")
        log.record(.permissionDenied, path: "/Users/me/Library/Safari", message: "Operation not permitted")

        let report = StorageScanReport(
            issueLog: log,
            scannedItemCount: 10,
            allocatedBytes: 1000,
            logicalBytes: 1000,
            datalessLogicalBytes: 0,
            reconciliation: nil
        )

        // When FDA is active, all 3 become systemProtected
        let reclassifiedWithFDA = report.reclassifyingSystemDataVaults(hasFullDiskAccess: true)
        XCTAssertEqual(reclassifiedWithFDA.count(of: .permissionDenied), 0)
        XCTAssertEqual(reclassifiedWithFDA.count(of: .systemProtected), 3)
        XCTAssertTrue(reclassifiedWithFDA.isComplete)

        // When FDA is not active, only system data vaults become systemProtected
        let reclassifiedWithoutFDA = report.reclassifyingSystemDataVaults(hasFullDiskAccess: false)
        XCTAssertEqual(reclassifiedWithoutFDA.count(of: .permissionDenied), 1) // /Users/me/Library/Safari
        XCTAssertEqual(reclassifiedWithoutFDA.count(of: .systemProtected), 2) // the two system paths
        XCTAssertFalse(reclassifiedWithoutFDA.isComplete)
    }

    func testDiskCacheSnapshotReclassification() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cacheURL = home.appendingPathComponent("Library/Application Support/MoraxGarage/storage_map_cache.plist")
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        guard let snapshot = StorageMapStateService.decodeSnapshot(at: cacheURL),
              let report = snapshot.report else { return }
        
        let reclassified = report.reclassifyingSystemDataVaults(hasFullDiskAccess: true)
        XCTAssertEqual(reclassified.count(of: .permissionDenied), 0, "All 57 data vaults must be reclassified from permissionDenied")
        XCTAssertEqual(reclassified.unreadableCount, 0, "Unreadable count must be 0 after reclassification")
        XCTAssertFalse(reclassified.needsFullDiskAccess, "Should not prompt to grant Full Disk Access when scan is complete")
        XCTAssertTrue(reclassified.isComplete, "Scan must be recognized as complete")
    }

    func testRefusalAfterAFloodOfRecursionLoopsIsStillRetainedAndCounted() {
        var log = StorageScanIssueLog()
        for index in 0..<(StorageScanReport.maxRetainedIssues * 3) {
            log.record(.recursionLoop, path: "/loop/\(index)", message: "loop")
        }
        log.record(.permissionDenied, path: "/Users/me/Library/Mail", message: "Operation not permitted")

        let report = StorageScanReport(
            issueLog: log,
            scannedItemCount: 1,
            allocatedBytes: 0,
            logicalBytes: 0,
            datalessLogicalBytes: 0,
            reconciliation: nil
        )

        XCTAssertFalse(report.isComplete, "A refusal met late in the walk must not be lost")
        XCTAssertEqual(report.unreadableCount, 1)
        XCTAssertTrue(report.needsFullDiskAccess)
        XCTAssertEqual(report.blockingIssues.map(\.path), ["/Users/me/Library/Mail"])
        XCTAssertEqual(report.count(of: .recursionLoop), StorageScanReport.maxRetainedIssues * 3)
        XCTAssertLessThanOrEqual(report.issues.count, StorageScanReport.maxRetainedIssues)
    }

    func testBlockingCountStaysExactBeyondTheRetentionCap() {
        var log = StorageScanIssueLog()
        let deniedCount = StorageScanReport.maxRetainedIssues + 42
        for index in 0..<deniedCount {
            log.record(.posixDenied, path: "/denied/\(index)", message: "Permission denied")
        }

        let report = StorageScanReport(
            issueLog: log,
            scannedItemCount: 1,
            allocatedBytes: 0,
            logicalBytes: 0,
            datalessLogicalBytes: 0,
            reconciliation: nil
        )

        XCTAssertEqual(report.unreadableCount, deniedCount)
        XCTAssertEqual(report.issues.count, StorageScanReport.maxRetainedIssues)
    }

    func testSnapshotWithoutPerKindCountsStillDecodes() throws {
        let legacy = StorageScanReport(
            issues: [StorageScanIssue(path: "/x", kind: .permissionDenied, message: "denied")],
            totalIssueCount: 1,
            scannedItemCount: 1,
            allocatedBytes: 0,
            logicalBytes: 0,
            datalessLogicalBytes: 0,
            reconciliation: nil
        )
        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(StorageScanReport.self, from: data)

        XCTAssertNil(decoded.issueCountsByKind)
        XCTAssertEqual(decoded.unreadableCount, 1, "Counts fall back to the retained issues")
    }

    func testSystemProtectedIssuesDoNotMakeTheScanIncomplete() {
        let report = StorageScanReport(
            issues: [StorageScanIssue(path: "/var/at/tabs", kind: .systemProtected, message: "Permission denied")],
            totalIssueCount: 1,
            scannedItemCount: 10,
            allocatedBytes: 1_024,
            logicalBytes: 1_024,
            datalessLogicalBytes: 0,
            reconciliation: nil
        )

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.unreadableCount, 0)
        XCTAssertEqual(report.systemProtectedIssues.count, 1)
        XCTAssertFalse(report.needsFullDiskAccess)
    }
    
    func testCleanTreeReportsNoBlockingIssues() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_clean") { rootDir in
            let readable = rootDir.appendingPathComponent(".config/app")
            try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true)
            try Data(repeating: 0x01, count: 2_048).write(to: readable.appendingPathComponent("settings.json"))
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)
            
            XCTAssertEqual(result.report.unreadableCount, 0)
            XCTAssertEqual(result.report.blockingIssues.count, 0)
        }
    }
    
    /// The disk purges caches continuously, so reconciliation is asserted on shape, never
    /// on an exact byte total.
    func testReconciliationDescribesTheHostVolumeWithoutAssumingAStableTotal() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_reconcile") { rootDir in
            try Data(repeating: 0x02, count: 1_024).write(to: rootDir.appendingPathComponent("file.bin"))
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)
            let reconciliation = try XCTUnwrap(result.report.reconciliation)
            
            XCTAssertGreaterThan(reconciliation.volumeTotalBytes, 0)
            XCTAssertGreaterThan(reconciliation.volumeUsedBytes, 0)
            XCTAssertFalse(reconciliation.coversWholeVolume, "A temp subfolder is not a whole volume")
            XCTAssertFalse(reconciliation.exceedsTolerance, "Tolerance only applies to whole-volume scans")
        }
    }
    
    func testReconciliationFlagsAWholeVolumeGapAboveTolerance() throws {
        let used: Int64 = 1_000_000_000_000
        let withinTolerance = StorageScanReconciliation(
            volumePath: "/",
            volumeTotalBytes: used * 2,
            volumeUsedBytes: used,
            scannedAllocatedBytes: Int64(Double(used) * 0.97),
            coversWholeVolume: true
        )
        XCTAssertFalse(withinTolerance.exceedsTolerance)
        
        let beyondTolerance = StorageScanReconciliation(
            volumePath: "/",
            volumeTotalBytes: used * 2,
            volumeUsedBytes: used,
            scannedAllocatedBytes: Int64(Double(used) * 0.44),
            coversWholeVolume: true
        )
        XCTAssertTrue(beyondTolerance.exceedsTolerance)
        XCTAssertEqual(beyondTolerance.unaccountedBytes, used - Int64(Double(used) * 0.44))
    }

    /// Pruning is a memory trade, never an accounting one: the folded entries keep
    /// contributing their bytes and their count.
    func testSmallEntriesAreFoldedWithoutLosingBytes() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_pruning") { rootDir in
            let smallCount = 40
            let smallSize = 4_096
            for index in 0..<smallCount {
                try Data(repeating: 0x07, count: smallSize)
                    .write(to: rootDir.appendingPathComponent("small_\(index).txt"))
            }
            let bigSize = 4 * 1024 * 1024
            try Data(repeating: 0x08, count: bigSize).write(to: rootDir.appendingPathComponent("big.bin"))
            
            let pruned = try await StorageScanner().scanWithReport(rootURL: rootDir)
            let complete = try await StorageScanner().scanWithReport(
                rootURL: rootDir,
                options: .retainEverything
            )
            
            XCTAssertEqual(
                pruned.rootNode.allocatedSizeBytes,
                complete.rootNode.allocatedSizeBytes,
                "Folding small entries must not change the total"
            )
            XCTAssertEqual(pruned.rootNode.itemCount, complete.rootNode.itemCount)
            XCTAssertLessThan(pruned.rootNode.children.count, complete.rootNode.children.count)
            
            let aggregate = try XCTUnwrap(pruned.rootNode.children.first(where: \.isAggregate))
            XCTAssertEqual(aggregate.itemCount, smallCount)
            XCTAssertGreaterThanOrEqual(aggregate.allocatedSizeBytes, Int64(smallCount * smallSize))
        }
    }
    
    func testAggregateNodeCannotBeStaged() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_pruning_staging") { rootDir in
            for index in 0..<5 {
                try Data(repeating: 0x09, count: 1_024)
                    .write(to: rootDir.appendingPathComponent("tiny_\(index).txt"))
            }
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir)
            let aggregate = try XCTUnwrap(result.rootNode.children.first(where: \.isAggregate))
            
            let staging = await CleanupStagingService()
            let outcome = await staging.stageNode(aggregate)
            
            switch outcome {
            case .success:
                XCTFail("An aggregate stands for a whole folder: staging it must be refused")
            case .failure:
                break
            }
        }
    }
    
    /// Regression: joining onto a root path produced `//Users`, and every path comparison
    /// the walk makes — mount points, firmlink duplicates, denylists — silently stopped
    /// matching.
    func testChildPathsOfARootDirectoryHaveNoDoubleSeparator() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_paths") { rootDir in
            let child = rootDir.appendingPathComponent("child")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data(repeating: 0x0A, count: 2 * 1024 * 1024)
                .write(to: child.appendingPathComponent("payload.bin"))
            
            let result = try await StorageScanner().scanWithReport(rootURL: rootDir)
            
            func assertNoDoubleSeparator(_ node: StorageNode) {
                XCTAssertFalse(node.path.contains("//"), "Unexpected double separator in \(node.path)")
                node.children.forEach(assertNoDoubleSeparator)
            }
            assertNoDoubleSeparator(result.rootNode)
        }
    }
    
    /// The same join, exercised on the real filesystem root, where the bug actually bit.
    func testRootScanBuildsSingleSeparatorPaths() async throws {
        let scanner = StorageScanner()
        let rootEntries = try FileManager.default.contentsOfDirectory(atPath: "/")
        let sample = try XCTUnwrap(rootEntries.first { entry in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: "/" + entry, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue && entry == "bin"
        })
        
        let result = try await scanner.scanWithReport(rootURL: URL(fileURLWithPath: "/" + sample))
        XCTAssertFalse(result.rootNode.path.contains("//"))
        XCTAssertTrue(result.rootNode.children.allSatisfy { !$0.path.contains("//") })
    }
}
