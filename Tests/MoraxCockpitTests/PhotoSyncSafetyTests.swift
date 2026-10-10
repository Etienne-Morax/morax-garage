import XCTest
@testable import MoraxCockpitKit

/// A partial read of any copy must never let a project read as synced or free to delete.
final class PhotoSyncSafetyTests: XCTestCase {
    private let scanner = PhotoSyncScanner()

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Locks `folder` for the duration of `body`, then restores it so the temp dir can be removed.
    private func withUnreadable(_ folder: URL, _ body: () throws -> Void) throws {
        try XCTSkipIf(getuid() == 0, "root ignores permission bits")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        try body()
    }

    func testFingerprintWithUnreadableSubfolderIsIncomplete() throws {
        try TestFixtures.withTempDirectory { root in
            let job = root.appendingPathComponent("Job")
            try write("abc", to: job.appendingPathComponent("1.cr3"))
            try write("abcd", to: job.appendingPathComponent("locked/2.cr3"))

            try withUnreadable(job.appendingPathComponent("locked")) {
                let print = try XCTUnwrap(scanner.fingerprint(of: job))

                XCTAssertFalse(print.isComplete)
                XCTAssertEqual(print.files, ["1.cr3": 3])
            }
        }
    }

    func testReadableFolderFingerprintIsComplete() throws {
        try TestFixtures.withTempDirectory { root in
            try write("abc", to: root.appendingPathComponent("Job/1.cr3"))

            XCTAssertEqual(scanner.fingerprint(of: root.appendingPathComponent("Job"))?.isComplete, true)
        }
    }

    func testUnreadableSSDSubfolderIsNeverSyncedNorReadyToFree() throws {
        try TestFixtures.withTempDirectory { root in
            let ssd = root.appendingPathComponent("ssd/Job")
            let nas = root.appendingPathComponent("nas/Job")
            try write("abc", to: ssd.appendingPathComponent("1.cr3"))
            try write("abcd", to: ssd.appendingPathComponent("locked/2.cr3"))
            // The NAS only holds what was readable on the SSD.
            try write("abc", to: nas.appendingPathComponent("1.cr3"))

            try withUnreadable(ssd.appendingPathComponent("locked")) {
                let status = scanner.status(name: "Job", mac: nil, ssd: ssd, nas: nas, isSSDOnline: true, isNASOnline: true)

                XCTAssertEqual(status.ssdToNAS, .unverifiable)
                XCTAssertFalse(status.ssdToNAS.isSynced)
                XCTAssertNotEqual(status.stage(retentionDays: 0), .readyToFreeSSD)
                XCTAssertEqual(status.stage(retentionDays: 0), .unknown)
            }
        }
    }

    func testSSDVanishedAfterDiscoveryIsUnverifiableNotSynced() throws {
        try TestFixtures.withTempDirectory { root in
            let mac = root.appendingPathComponent("mac/Job")
            let nas = root.appendingPathComponent("nas/Job")
            try write("abc", to: mac.appendingPathComponent("1.cr3"))
            try write("abc", to: nas.appendingPathComponent("1.cr3"))
            // Listed while mounted, unplugged before its fingerprint was taken.
            let unpluggedSSD = root.appendingPathComponent("unplugged/Job")

            let status = scanner.status(name: "Job", mac: mac, ssd: unpluggedSSD, nas: nas, isSSDOnline: true, isNASOnline: true)

            XCTAssertEqual(status.macToSSD, .unverifiable)
            XCTAssertEqual(status.ssdToNAS, .unverifiable)
            XCTAssertEqual(status.stage(retentionDays: 0), .unknown)
        }
    }

    func testCompareIsUnverifiableWhenEitherSideIsIncomplete() {
        let complete = FolderFingerprint(files: ["a.cr3": 1])
        let partial = FolderFingerprint(files: ["a.cr3": 1], isComplete: false)

        XCTAssertEqual(scanner.compare(reference: partial, destination: complete), .unverifiable)
        XCTAssertEqual(scanner.compare(reference: complete, destination: partial), .unverifiable)
        XCTAssertEqual(scanner.compare(reference: complete, destination: complete), .synced)
        XCTAssertFalse(CopyStatus.unverifiable.needsSync)
    }

    func testUnionOfPartialAndCompleteIsPartial() {
        let union = PhotoSyncScanner.union(FolderFingerprint(files: ["a": 1]), FolderFingerprint(files: ["b": 2], isComplete: false))

        XCTAssertEqual(union?.isComplete, false)
        XCTAssertEqual(union?.files, ["a": 1, "b": 2])
    }

    func testStageIsUnknownWhenAnyLegIsUnverifiable() {
        let old = Date().addingTimeInterval(-90 * 86_400)
        func status(macToSSD: CopyStatus, ssdToNAS: CopyStatus) -> PhotoProjectStatus {
            PhotoProjectStatus(
                key: "job", name: "Job", macPath: "/mac/Job", ssdPath: "/ssd/Job", nasPath: "/nas/Job",
                referenceBytes: 1, referenceFileCount: 1, macToSSD: macToSSD, ssdToNAS: ssdToNAS,
                ssdCopyDate: old, lastModified: nil, checkedAt: Date()
            )
        }

        XCTAssertEqual(status(macToSSD: .synced, ssdToNAS: .unverifiable).stage(retentionDays: 60), .unknown)
        XCTAssertEqual(status(macToSSD: .unverifiable, ssdToNAS: .synced).stage(retentionDays: 60), .unknown)
        XCTAssertEqual(status(macToSSD: .synced, ssdToNAS: .synced).stage(retentionDays: 60), .readyToFreeSSD)
    }
}
