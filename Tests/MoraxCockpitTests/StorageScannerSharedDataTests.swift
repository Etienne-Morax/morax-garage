import XCTest
import Foundation
@testable import MoraxCockpitKit

/// A file reachable under two names occupies its blocks once. Counting each name used to
/// push a whole-disk total well above what the volume reports as used.
final class StorageScannerSharedDataTests: XCTestCase {

    private let payloadSize = 4 * 1024 * 1024

    private func writePayload(to url: URL) throws {
        try Data(repeating: 0x5A, count: payloadSize).write(to: url)
    }

    func testHardlinkedFileIsCountedOnce() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_hardlink") { rootDir in
            let original = rootDir.appendingPathComponent("a/original.bin")
            let link = rootDir.appendingPathComponent("b/link.bin")
            try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePayload(to: original)
            try FileManager.default.linkItem(at: original, to: link)

            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)

            let allocated = result.rootNode.allocatedSizeBytes
            XCTAssertGreaterThanOrEqual(allocated, Int64(payloadSize))
            XCTAssertLessThan(allocated, Int64(payloadSize) * 2, "The second name must not add the blocks again")
            XCTAssertGreaterThanOrEqual(result.report.sharedData?.hardlinkDuplicateBytes ?? 0, Int64(payloadSize))
        }
    }

    func testPureAPFSCloneIsCountedOnce() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_clone") { rootDir in
            let source = rootDir.appendingPathComponent("source.mov")
            let clone = rootDir.appendingPathComponent("copy/source copy.mov")
            try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePayload(to: source)
            let cloned = source.path.withCString { src in clone.path.withCString { dst in clonefile(src, dst, 0) } }
            try XCTSkipIf(cloned != 0, "Temporary directory is not on a clone-capable volume")
            try XCTSkipIf(StorageScanner.cloneID(path: source.path) == nil, "Volume does not report clone ids")

            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)

            XCTAssertLessThan(result.rootNode.allocatedSizeBytes, Int64(payloadSize) * 2)
            XCTAssertGreaterThanOrEqual(result.report.sharedData?.cloneDuplicateBytes ?? 0, Int64(payloadSize))
        }
    }

    func testIndependentCopiesAreBothCounted() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "scanner_copies") { rootDir in
            try writePayload(to: rootDir.appendingPathComponent("one.bin"))
            try writePayload(to: rootDir.appendingPathComponent("two.bin"))

            let result = try await StorageScanner().scanWithReport(rootURL: rootDir, options: .retainEverything)

            XCTAssertGreaterThanOrEqual(result.rootNode.allocatedSizeBytes, Int64(payloadSize) * 2)
            XCTAssertEqual(result.report.sharedData?.totalBytes, 0)
        }
    }

    func testSmallFilesAreNeverProbedForCloneIDs() {
        var tracker = SharedDataTracker()
        var probeCount = 0
        let isDuplicate = tracker.isDuplicate(
            inode: 1,
            linkCount: 1,
            allocatedBytes: SharedDataTracker.cloneProbeMinBytes - 1,
            cloneID: { probeCount += 1; return 42 }
        )

        XCTAssertFalse(isDuplicate)
        XCTAssertEqual(probeCount, 0)
    }
}
