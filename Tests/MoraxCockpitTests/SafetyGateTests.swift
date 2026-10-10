import XCTest
import Foundation
@testable import MoraxCockpitKit

final class SafetyGateTests: XCTestCase {
    
    func testSystemDenylistRejections() {
        let protectedPaths = [
            "/System",
            "/System/Library",
            "/usr/bin",
            "/bin/sh",
            "/sbin/mount",
            "/private/var/db",
            "/var/db",
            "/Library/Apple",
            "/Library/SystemExtensions"
        ]
        
        for path in protectedPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try SafetyGate.validateForTrash(url: url)) { error in
                guard let safetyErr = error as? SafetyGateError else {
                    XCTFail("Expected SafetyGateError but got \(error)")
                    return
                }
                switch safetyErr {
                case .pathIsDenylisted:
                    break // Expected
                default:
                    XCTFail("Expected .pathIsDenylisted for \(path), got \(safetyErr)")
                }
            }
        }
    }
    
    func testRootFilesystemProtection() {
        let rootURL = URL(fileURLWithPath: "/")
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: rootURL)) { error in
            XCTAssertEqual(error as? SafetyGateError, .rootFilesystemProtected)
        }
    }
    
    func testUserHomeRootProtection() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: homeURL)) { error in
            XCTAssertEqual(error as? SafetyGateError, .homeRootProtected)
        }
    }
    
    func testKeychainsAndMobileSyncProtection() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keychainsURL = home.appendingPathComponent("Library/Keychains/login.keychain-db")
        let mobileSyncURL = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/uuid")
        
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: keychainsURL))
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: mobileSyncURL))
    }
    
    func testDaVinciResolveSafety() throws {
        try TestFixtures.withFakeResolveTree { cacheClip, gallery, projectDb, root in
            // CacheClip and Gallery SHOULD pass DaVinci safety check
            XCTAssertNoThrow(try SafetyGate.checkDaVinciResolveSafety(canonicalPath: cacheClip.path))
            XCTAssertNoThrow(try SafetyGate.checkDaVinciResolveSafety(canonicalPath: gallery.path))
            
            // Project Database MUST throw
            XCTAssertThrowsError(try SafetyGate.checkDaVinciResolveSafety(canonicalPath: projectDb.path))
            
            // .drp Export file MUST throw
            let drpPath = root.appendingPathComponent("MyTimeline.drp").path
            XCTAssertThrowsError(try SafetyGate.checkDaVinciResolveSafety(canonicalPath: drpPath))
            
            // Resolve Project Library directory MUST throw
            let libDir = root.appendingPathComponent("Resolve Project Library").path
            XCTAssertThrowsError(try SafetyGate.checkDaVinciResolveSafety(canonicalPath: libDir))
            
            // Project Backups MUST throw
            let backupDir = root.appendingPathComponent("Resolve Project Backups").path
            XCTAssertThrowsError(try SafetyGate.checkDaVinciResolveSafety(canonicalPath: backupDir))
        }
    }
    
    func testSymlinkEscapeDetection() throws {
        try TestFixtures.withTempDirectory(prefix: "symlink_test") { root in
            let scanRoot = root.appendingPathComponent("ScanRoot")
            let outsideRoot = root.appendingPathComponent("OutsideSecret")
            
            try? FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
            
            let outsideFile = outsideRoot.appendingPathComponent("passwords.txt")
            try? "secret".data(using: .utf8)?.write(to: outsideFile)
            
            let symlinkInRoot = scanRoot.appendingPathComponent("innocent_link.txt")
            try? FileManager.default.createSymbolicLink(at: symlinkInRoot, withDestinationURL: outsideFile)
            
            // Symlink points outside scanRoot -> MUST throw pathEscapesScanRoot
            XCTAssertThrowsError(try SafetyGate.validateForTrash(url: symlinkInRoot, scanRoot: scanRoot)) { error in
                guard let safetyErr = error as? SafetyGateError else {
                    XCTFail("Expected SafetyGateError but got \(error)")
                    return
                }
                switch safetyErr {
                case .pathEscapesScanRoot:
                    break // Expected
                default:
                    XCTFail("Expected .pathEscapesScanRoot, got \(safetyErr)")
                }
            }
            
            // Valid file inside scanRoot -> MUST succeed
            let validFile = scanRoot.appendingPathComponent("safe_file.txt")
            try? "safe".data(using: .utf8)?.write(to: validFile)
            XCTAssertNoThrow(try SafetyGate.validateForTrash(url: validFile, scanRoot: scanRoot))
        }
    }
    
    func testFirmlinkCanonicalization() {
        let tmpURL = URL(fileURLWithPath: "/tmp")
        let canon = SafetyGate.canonicalize(url: tmpURL)
        XCTAssertTrue(canon.path.hasPrefix("/private/tmp") || canon.path.hasPrefix("/tmp"))
    }
    
    func testNullByteRejection() {
        XCTAssertThrowsError(try SafetyGate.validateForTrash(path: "/tmp/evil\0file.txt")) { error in
            XCTAssertEqual(error as? SafetyGateError, .nullByteInPath)
        }
        
        let encodedURL = URL(string: "file:///tmp/evil%00file.txt")!
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: encodedURL)) { error in
            XCTAssertEqual(error as? SafetyGateError, .nullByteInPath)
        }
    }
    
    func testItemCapEnforcement() {
        let dummyURLs = (0...10_005).map { URL(fileURLWithPath: "/tmp/item_\($0)") }
        XCTAssertThrowsError(try SafetyGate.validateBatch(urls: dummyURLs, scanRoot: URL(fileURLWithPath: "/tmp"))) { error in
            guard let safetyErr = error as? SafetyGateError else {
                XCTFail("Expected SafetyGateError")
                return
            }
            switch safetyErr {
            case .itemCapExceeded(let count, let cap):
                XCTAssertEqual(count, 10006)
                XCTAssertEqual(cap, 10000)
            default:
                XCTFail("Expected .itemCapExceeded, got \(safetyErr)")
            }
        }
    }
    
    func testValidationIdempotence() throws {
        try TestFixtures.withTempDirectory { tempDir in
            let testFile = tempDir.appendingPathComponent("temp_test.txt")
            try "test".data(using: .utf8)?.write(to: testFile)
            
            // Repeated calls produce same result
            XCTAssertNoThrow(try SafetyGate.validateForTrash(url: testFile, scanRoot: tempDir))
            XCTAssertNoThrow(try SafetyGate.validateForTrash(url: testFile, scanRoot: tempDir))
            XCTAssertNoThrow(try SafetyGate.validateForTrash(url: testFile, scanRoot: tempDir))
        }
    }
    
    func testPhotoAppSafetyProtection() throws {
        // Master Catalog Databases MUST throw
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Lightroom/Lightroom Catalog.lrcat"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Lightroom/Lightroom Catalog.lrcat-data"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Lightroom/Backups/2026/Catalog.lrcat"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Old Lightroom Catalogs/Catalog.lrcat"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Preset.lrtemplate"))
        
        // Capture One Master Databases & Adjustments MUST throw
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Wedding.cocatalog/CaptureOne.cocatalogdb"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Shoot/Shoot.cosessiondb"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Shoot/CaptureOne/Settings140/IMG_001.cos"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Shoot/CaptureOne/Settings160/IMG_001.comask"))
        
        // Master RAW and Project Files MUST throw
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/RAW/photo.cr3"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/RAW/photo.arw"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/RAW/photo.nef"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/RAW/photo.dng"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Edit/retouch.psd"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Edit/retouch.psb"))
        XCTAssertThrowsError(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Presets/action.atn"))
        
        // Safe Preview and Proxy Caches SHOULD NOT throw
        XCTAssertNoThrow(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Lightroom/Lightroom Catalog Previews.lrdata"))
        XCTAssertNoThrow(try SafetyGate.checkPhotoAppSafety(canonicalPath: "/Users/test/Pictures/Shoot/CaptureOne/Cache"))
    }
}

// MARK: - User data containers, iCloud and Claude memory

extension SafetyGateTests {
    /// The container directories themselves are refused, while the artefacts the
    /// scanners legitimately find inside them stay deletable.
    func testUserDataContainersAreProtectedButTheirContentsAreNot() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser

        for subpath in ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Library", "Library/Application Support"] {
            let container = home.appendingPathComponent(subpath)
            XCTAssertThrowsError(try SafetyGate.validateForTrash(url: container), "\(subpath) must be refused") { error in
                guard case SafetyGateError.userDataProtected = error else {
                    return XCTFail("Expected userDataProtected for \(subpath), got \(error)")
                }
            }
        }

        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: URL(fileURLWithPath: "/Applications")))

        // An artefact inside a container is still offered.
        let insideDocuments = home.appendingPathComponent("Documents/SomeProject/node_modules")
        XCTAssertNoThrow(try SafetyGate.validateForTrash(url: insideDocuments))
    }

    /// iCloud Drive containers are refused because trashing them removes the files
    /// from every device on the account, not only from this Mac.
    func testCloudDriveContainersAreProtected() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mobileDocuments = home.appendingPathComponent("Library/Mobile Documents")

        for path in [mobileDocuments, mobileDocuments.appendingPathComponent("com~apple~CloudDocs"),
                     mobileDocuments.appendingPathComponent("com~apple~CloudDocs/Desktop")] {
            XCTAssertThrowsError(try SafetyGate.validateForTrash(url: path)) { error in
                guard case SafetyGateError.cloudSyncedContainerProtected = error else {
                    return XCTFail("Expected cloudSyncedContainerProtected for \(path.path), got \(error)")
                }
            }
        }

        // A single file deeper in the tree stays deletable, but is reported as synced.
        let deepFile = mobileDocuments.appendingPathComponent("com~apple~CloudDocs/Desktop/Installer.dmg")
        XCTAssertNoThrow(try SafetyGate.validateForTrash(url: deepFile))
        XCTAssertTrue(SafetyGate.isCloudSynced(url: deepFile))
    }

    /// Claude persistent memory lives inside the transcript folders the cleanup
    /// scanner offers, and unlike transcripts it never regenerates.
    func testClaudeMemoryDirectoriesAreProtected() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let memory = home.appendingPathComponent(".claude/projects/-Users-someone-project/memory")

        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: memory)) { error in
            guard case SafetyGateError.userDataProtected(_, let reason) = error else {
                return XCTFail("Expected userDataProtected, got \(error)")
            }
            XCTAssertEqual(reason, "Claude persistent memory")
        }
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: memory.appendingPathComponent("MEMORY.md")))

        // The transcripts next to it remain deletable.
        let transcript = home.appendingPathComponent(".claude/projects/-Users-someone-project/session.jsonl")
        XCTAssertNoThrow(try SafetyGate.validateForTrash(url: transcript))
    }

    /// The whole transcript root is a container: clearing one project is supported,
    /// clearing every project and its memory in one item is not.
    func testClaudeProjectsRootIsProtected() {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        XCTAssertThrowsError(try SafetyGate.validateForTrash(url: root))
    }
}
