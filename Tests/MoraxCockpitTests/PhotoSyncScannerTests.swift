import XCTest
@testable import MoraxCockpitKit

final class PhotoSyncScannerTests: XCTestCase {
    private let scanner = PhotoSyncScanner()

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    // MARK: - Discovery

    func testListProjectsSkipsLibrariesWorkingFoldersAndIgnoredNames() throws {
        try TestFixtures.withTempDirectory { root in
            for name in ["Coco Headshots 2026", "Hugo Wedding ", "Export", "Photos Library.photoslibrary", "Old job"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            try write("x", to: root.appendingPathComponent("loose.png"))

            let projects = scanner.listProjects(in: root, excluding: ["old job"])

            XCTAssertEqual(Set(projects.keys), ["coco headshots 2026", "hugo wedding"])
        }
    }

    func testIndexNASFindsProjectsInsideCategoriesAndPrefersShallowestMatch() throws {
        try TestFixtures.withTempDirectory { root in
            let fm = FileManager.default
            try fm.createDirectory(at: root.appendingPathComponent("04 - Corporate/01 - Business Corpo/Coco Headshots 2026"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("06 - Music/Eaupale/RAW"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("06 - Music/Other band/Eaupale"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("#recycle/Deleted job"), withIntermediateDirectories: true)

            let index = scanner.indexNAS(root: root)

            XCTAssertEqual(index["coco headshots 2026"]?.lastPathComponent, "Coco Headshots 2026")
            XCTAssertEqual(index["eaupale"]?.deletingLastPathComponent().lastPathComponent, "06 - Music")
            XCTAssertNil(index["deleted job"])
        }
    }

    func testProjectKeyMatchesDecomposedAccentsTrailingSpacesAndCase() {
        let decomposed = "Cafe\u{301} Mariage "
        XCTAssertEqual(PhotoSyncNaming.projectKey(decomposed), PhotoSyncNaming.projectKey("café mariage"))
    }

    // MARK: - Verification

    func testCompareReportsSyncedWhenEveryReferenceFileMatchesAndIgnoresExtras() {
        let reference = FolderFingerprint(files: ["a.cr3": 10, "sub/b.jpg": 5])
        let destination = FolderFingerprint(files: ["a.cr3": 10, "sub/b.jpg": 5, "extra.xmp": 1])

        XCTAssertEqual(scanner.compare(reference: reference, destination: destination), .synced)
    }

    func testCompareCountsMissingAndResizedFiles() {
        let reference = FolderFingerprint(files: ["a.cr3": 10, "b.cr3": 20, "c.cr3": 30])
        let destination = FolderFingerprint(files: ["a.cr3": 10, "b.cr3": 7])

        XCTAssertEqual(
            scanner.compare(reference: reference, destination: destination),
            .incomplete(missingFiles: 2, missingBytes: 50)
        )
    }

    func testCompareReportsMissingDestinationAndMissingSource() {
        XCTAssertEqual(scanner.compare(reference: FolderFingerprint(files: [:]), destination: nil), .missing)
        XCTAssertEqual(scanner.compare(reference: nil, destination: nil), .noSource)
    }

    func testFingerprintSkipsHiddenAndSystemFiles() throws {
        try TestFixtures.withTempDirectory { root in
            try write("12345", to: root.appendingPathComponent("sub/photo.jpg"))
            try write("x", to: root.appendingPathComponent(".DS_Store"))
            try write("x", to: root.appendingPathComponent("._photo.jpg"))
            try write("x", to: root.appendingPathComponent("Thumbs.db"))

            let print = try XCTUnwrap(scanner.fingerprint(of: root))

            XCTAssertEqual(print.files, ["sub/photo.jpg": 5])
        }
    }

    func testStatusChainsMacToSSDAndSSDToNAS() throws {
        try TestFixtures.withTempDirectory { root in
            let mac = root.appendingPathComponent("mac/Job")
            let ssd = root.appendingPathComponent("ssd/Job")
            try write("abc", to: mac.appendingPathComponent("1.jpg"))
            try write("abcd", to: mac.appendingPathComponent("2.jpg"))
            try write("abc", to: ssd.appendingPathComponent("1.jpg"))

            let status = scanner.status(name: "Job", mac: mac, ssd: ssd, nas: nil, isSSDOnline: true, isNASOnline: true)

            XCTAssertEqual(status.macToSSD, .incomplete(missingFiles: 1, missingBytes: 4))
            XCTAssertEqual(status.ssdToNAS, .missing)
            XCTAssertEqual(status.referenceFileCount, 2)
            XCTAssertEqual(status.stage(retentionDays: 60), .needsSSDCopy)
        }
    }

    func testStatusReportsOfflineVolumes() throws {
        try TestFixtures.withTempDirectory { root in
            let mac = root.appendingPathComponent("mac/Job")
            try write("abc", to: mac.appendingPathComponent("1.jpg"))

            let status = scanner.status(name: "Job", mac: mac, ssd: nil, nas: nil, isSSDOnline: false, isNASOnline: false)

            XCTAssertEqual(status.macToSSD, .volumeOffline)
            XCTAssertEqual(status.ssdToNAS, .volumeOffline)
            XCTAssertEqual(status.stage(retentionDays: 60), .unknown)
        }
    }

    // MARK: - Stages

    private func makeStatus(ssdPath: String?, ssdCopyDate: Date?, macToSSD: CopyStatus = .noSource, ssdToNAS: CopyStatus = .synced) -> PhotoProjectStatus {
        PhotoProjectStatus(
            key: "job", name: "Job", macPath: nil, ssdPath: ssdPath, nasPath: "/nas/Job",
            referenceBytes: 0, referenceFileCount: 0, macToSSD: macToSSD, ssdToNAS: ssdToNAS,
            ssdCopyDate: ssdCopyDate, lastModified: nil, checkedAt: Date()
        )
    }

    func testStageFlagsSSDCopyReadyToFreeAfterRetention() {
        let now = Date()
        let old = now.addingTimeInterval(-61 * 86_400)
        let recent = now.addingTimeInterval(-10 * 86_400)

        XCTAssertEqual(makeStatus(ssdPath: "/ssd/Job", ssdCopyDate: old).stage(retentionDays: 60, now: now), .readyToFreeSSD)
        XCTAssertEqual(makeStatus(ssdPath: "/ssd/Job", ssdCopyDate: recent).stage(retentionDays: 60, now: now), .retainedOnSSD)
        XCTAssertEqual(makeStatus(ssdPath: nil, ssdCopyDate: nil).stage(retentionDays: 60, now: now), .archivedOnly)
    }

    func testStageNeverFreesSSDWhenNASIsIncomplete() {
        let old = Date().addingTimeInterval(-90 * 86_400)
        let status = makeStatus(ssdPath: "/ssd/Job", ssdCopyDate: old, ssdToNAS: .incomplete(missingFiles: 1, missingBytes: 1))

        XCTAssertEqual(status.stage(retentionDays: 60), .needsNASArchive)
    }

    // MARK: - Copy plan

    func testCopyPlanIsAdditiveAndCopiesFolderContents() {
        let plan = PhotoSyncCopyPlan(
            projectKey: "job", leg: .macToSSD,
            source: URL(fileURLWithPath: "/Users/me/Pictures/My Job"),
            destination: URL(fileURLWithPath: "/Volumes/SSD/Photos/My Job")
        )

        XCTAssertFalse(plan.arguments.contains { $0.hasPrefix("--delete") })
        XCTAssertEqual(plan.arguments.suffix(2), ["/Users/me/Pictures/My Job/", "/Volumes/SSD/Photos/My Job"])
    }

    func testCopyPlanValidationRejectsMissingDestinationParentAndSelfNesting() throws {
        try TestFixtures.withTempDirectory { root in
            let source = root.appendingPathComponent("Job")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

            let offline = PhotoSyncCopyPlan(projectKey: "job", leg: .macToSSD, source: source, destination: root.appendingPathComponent("unplugged/Job"))
            XCTAssertThrowsError(try offline.validate()) { error in
                XCTAssertEqual(error as? PhotoSyncCopyError, .destinationParentMissing(root.appendingPathComponent("unplugged").standardizedFileURL.path))
            }

            let nested = PhotoSyncCopyPlan(projectKey: "job", leg: .macToSSD, source: source, destination: source.appendingPathComponent("Job"))
            XCTAssertThrowsError(try nested.validate())

            let valid = PhotoSyncCopyPlan(projectKey: "job", leg: .macToSSD, source: source, destination: root.appendingPathComponent("Copy"))
            XCTAssertNoThrow(try valid.validate())
        }
    }

    func testTransferredFileLineParsing() {
        XCTAssertTrue(PhotoSyncCopyPlan.isTransferredFileLine("sub/IMG_0001.CR3"))
        XCTAssertFalse(PhotoSyncCopyPlan.isTransferredFileLine("sub/"))
        XCTAssertFalse(PhotoSyncCopyPlan.isTransferredFileLine("Transfer starting: 3 files"))
        XCTAssertFalse(PhotoSyncCopyPlan.isTransferredFileLine("sent 147 bytes  received 54 bytes  95714 bytes/sec"))
        XCTAssertFalse(PhotoSyncCopyPlan.isTransferredFileLine("total size is 3  speedup is 0.01"))
        XCTAssertFalse(PhotoSyncCopyPlan.isTransferredFileLine(""))
    }

    // MARK: - End to end copy

    func testRsyncPlanCopiesProjectAndStatusBecomesSynced() async throws {
        try await TestFixtures.withTempDirectoryAsync { root in
            let mac = root.appendingPathComponent("mac/Job é")
            let ssdRoot = root.appendingPathComponent("ssd")
            try write("abc", to: mac.appendingPathComponent("raw/1.cr3"))
            try write("x", to: mac.appendingPathComponent(".DS_Store"))
            try FileManager.default.createDirectory(at: ssdRoot, withIntermediateDirectories: true)

            let plan = PhotoSyncCopyPlan(projectKey: "job é", leg: .macToSSD, source: mac, destination: ssdRoot.appendingPathComponent("Job é"))
            try plan.validate()
            let result = try await ProcessRunner.shared.run(executableURL: PhotoSyncCopyPlan.rsyncURL, arguments: plan.arguments)
            XCTAssertTrue(result.isSuccess, result.standardError)

            let status = scanner.status(name: "Job é", mac: mac, ssd: plan.destination, nas: nil, isSSDOnline: true, isNASOnline: true)
            XCTAssertEqual(status.macToSSD, .synced)
            XCTAssertFalse(FileManager.default.fileExists(atPath: plan.destination.appendingPathComponent(".DS_Store").path))
        }
    }
}

@MainActor
final class PhotoSyncStateServiceTests: XCTestCase {
    private func makeService(root: URL) -> PhotoSyncStateService {
        let defaults = UserDefaults(suiteName: "photo_sync_tests_\(UUID().uuidString)")!
        let service = PhotoSyncStateService(customCacheDirectory: root.appendingPathComponent("cache"), defaults: defaults)
        service.updateConfiguration(PhotoSyncConfiguration(
            macRoot: root.appendingPathComponent("mac").path,
            ssdRoot: root.appendingPathComponent("ssd").path,
            nasRoot: root.appendingPathComponent("nas").path,
            ssdRetentionDays: 60,
            ignoredProjectKeys: []
        ))
        return service
    }

    func testNASPlanRequiresAParentInsideTheNASRoot() throws {
        try TestFixtures.withTempDirectory { root in
            let service = makeService(root: root)
            let project = PhotoProjectStatus(
                key: "job", name: "Job", macPath: nil, ssdPath: root.appendingPathComponent("ssd/Job").path, nasPath: nil,
                referenceBytes: 1, referenceFileCount: 1, macToSSD: .noSource, ssdToNAS: .missing,
                ssdCopyDate: nil, lastModified: nil, checkedAt: Date()
            )

            XCTAssertThrowsError(try service.makePlan(for: project, leg: .ssdToNAS, nasParent: nil))
            XCTAssertThrowsError(try service.makePlan(for: project, leg: .ssdToNAS, nasParent: "/tmp"))

            let plan = try service.makePlan(for: project, leg: .ssdToNAS, nasParent: root.appendingPathComponent("nas/04 - Corporate").path)
            XCTAssertEqual(plan.destination.lastPathComponent, "Job")
            XCTAssertEqual(plan.destination.deletingLastPathComponent().lastPathComponent, "04 - Corporate")
        }
    }

    func testScanListsProjectsFromMacAndSSDWithNASMatches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photo_sync_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let fm = FileManager.default
            try Data("abc".utf8).writeCreatingDirectories(to: root.appendingPathComponent("mac/New job/1.jpg"))
            try Data("abc".utf8).writeCreatingDirectories(to: root.appendingPathComponent("ssd/Old job/1.jpg"))
            try Data("abc".utf8).writeCreatingDirectories(to: root.appendingPathComponent("nas/04 - Corporate/01 - Corpo/Old job/1.jpg"))
            try fm.createDirectory(at: root.appendingPathComponent("nas/#recycle"), withIntermediateDirectories: true)
            let service = makeService(root: root)

            await service.scan(force: true)

            let byKey = Dictionary(uniqueKeysWithValues: service.projects.map { ($0.key, $0) })
            XCTAssertEqual(byKey["new job"]?.macToSSD, .missing)
            XCTAssertEqual(byKey["old job"]?.ssdToNAS, .synced)
            XCTAssertEqual(byKey["old job"]?.stage(retentionDays: 60), .retainedOnSSD)
            XCTAssertEqual(service.destinations.map(\.name), ["04 - Corporate"])
        }
    }
}

private extension Data {
    func writeCreatingDirectories(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(to: url)
    }
}

final class PhotoSyncReferenceTests: XCTestCase {
    private let scanner = PhotoSyncScanner()

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testFingerprintSkipsCaptureOneCacheButKeepsSettings() throws {
        try TestFixtures.withTempDirectory { root in
            try write("proxy", to: root.appendingPathComponent("Capture/CaptureOne/Cache/Proxies/1.cop"))
            try write("cos", to: root.appendingPathComponent("Capture/CaptureOne/Settings1680/1.cos"))

            let print = try XCTUnwrap(scanner.fingerprint(of: root))

            XCTAssertEqual(print.files, ["Capture/CaptureOne/Settings1680/1.cos": 3])
        }
    }

    func testNASMustHoldFilesStillOnlyOnTheMac() throws {
        try TestFixtures.withTempDirectory { root in
            let mac = root.appendingPathComponent("mac/Job")
            let ssd = root.appendingPathComponent("ssd/Job")
            let nas = root.appendingPathComponent("nas/Job")
            for folder in [mac, ssd, nas] {
                try write("abc", to: folder.appendingPathComponent("1.jpg"))
            }
            try write("new edit", to: mac.appendingPathComponent("2.jpg"))

            let status = scanner.status(name: "Job", mac: mac, ssd: ssd, nas: nas, isSSDOnline: true, isNASOnline: true)

            XCTAssertEqual(status.ssdToNAS, .incomplete(missingFiles: 1, missingBytes: 8))
        }
    }
}
