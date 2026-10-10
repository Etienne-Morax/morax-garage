import XCTest
@testable import MoraxCockpitKit

/// The disk purges caches continuously, so these assert on structure and relationships,
/// never on a byte total.
final class VolumeSpaceAuditTests: XCTestCase {
    
    func testMountTableIsReadable() throws {
        let mounts = VolumeSpaceAudit.mountedFilesystems()
        
        XCTAssertFalse(mounts.isEmpty)
        XCTAssertTrue(mounts.contains { $0.mountPoint == "/" })
    }
    
    /// Regression: `statfs` reports container-wide block counts for every APFS volume, so
    /// deriving usage from it credited each sibling with the entire disk.
    func testSiblingVolumesDoNotEachReportTheWholeContainer() throws {
        let audit = try XCTUnwrap(VolumeSpaceAudit.audit(
            pathOnVolume: "/System/Volumes/Data",
            reachableMountPoints: ["/", "/System/Volumes/Data"]
        ))
        
        XCTAssertGreaterThan(audit.totalBytes, 0)
        XCTAssertGreaterThan(audit.usedBytes, 0)
        
        for sibling in audit.siblingVolumes {
            XCTAssertLessThan(
                sibling.usedBytes,
                audit.usedBytes,
                "\(sibling.mountPoint) reports the container total instead of its own usage"
            )
        }
        XCTAssertLessThanOrEqual(audit.siblingVolumeBytes, audit.usedBytes)
    }
    
    func testPerVolumeUsageIsSmallerThanTheContainer() throws {
        let containerUsed = try XCTUnwrap(VolumeSpaceAudit.audit(
            pathOnVolume: "/",
            reachableMountPoints: ["/"]
        )).usedBytes
        let systemVolumeUsed = try XCTUnwrap(VolumeSpaceAudit.volumeSpaceUsed(atPath: "/"))
        
        XCTAssertGreaterThan(systemVolumeUsed, 0)
        XCTAssertLessThan(systemVolumeUsed, containerUsed)
    }
    
    func testReachableMountPointsAreNotCountedAsSiblings() throws {
        let audit = try XCTUnwrap(VolumeSpaceAudit.audit(
            pathOnVolume: "/System/Volumes/Data",
            reachableMountPoints: ["/", "/System/Volumes/Data"]
        ))
        
        let siblingPaths = Set(audit.siblingVolumes.map(\.mountPoint))
        XCTAssertFalse(siblingPaths.contains("/"))
        XCTAssertFalse(siblingPaths.contains("/System/Volumes/Data"))
    }
    
    func testContainerIdentifierGroupsSlicesOfTheSameDisk() {
        XCTAssertEqual(VolumeSpaceAudit.containerIdentifier(ofDeviceNode: "/dev/disk3s5s1"), "disk3")
        XCTAssertEqual(VolumeSpaceAudit.containerIdentifier(ofDeviceNode: "/dev/disk3s1"), "disk3")
        XCTAssertEqual(VolumeSpaceAudit.containerIdentifier(ofDeviceNode: "/dev/disk10s2"), "disk10")
        XCTAssertNotEqual(
            VolumeSpaceAudit.containerIdentifier(ofDeviceNode: "/dev/disk3s1"),
            VolumeSpaceAudit.containerIdentifier(ofDeviceNode: "/dev/disk5s1")
        )
        XCTAssertNil(VolumeSpaceAudit.containerIdentifier(ofDeviceNode: "map auto_home"))
    }
    
    func testPurgeableSpaceIsNotAddedToTheAccountedTotal() {
        // Purgeable bytes are already inside the volume's used figure: counting them again
        // would let a scan claim it explained more than the disk holds.
        let reconciliation = StorageScanReconciliation(
            volumePath: "/",
            volumeTotalBytes: 1_000,
            volumeUsedBytes: 900,
            scannedAllocatedBytes: 700,
            coversWholeVolume: true,
            siblingVolumes: [
                SiblingVolume(mountPoint: "/System/Volumes/VM", deviceNode: "/dev/disk3s6", usedBytes: 100, isReadable: true)
            ],
            purgeableBytes: 50
        )
        
        XCTAssertEqual(reconciliation.accountedBytes, 800)
        XCTAssertEqual(reconciliation.unaccountedBytes, 100)
        XCTAssertEqual(reconciliation.discrepancyRatio, 100.0 / 900.0, accuracy: 0.0001)
        XCTAssertTrue(reconciliation.exceedsTolerance)
    }
    
    /// Regression: the Data volume is visible both through the firmlinks at `/Users` and at
    /// its own mount point, and counting both doubles the reported size of the disk.
    func testDataVolumeMountPointIsSkippedWhenScanningRoot() {
        XCTAssertTrue(StorageScanner.isFirmlinkDuplicate(path: "/System/Volumes/Data", scanRootPath: "/"))
        XCTAssertTrue(StorageScanner.isFirmlinkDuplicate(path: "/System/Volumes/Data/home", scanRootPath: "/"))
        XCTAssertFalse(StorageScanner.isFirmlinkDuplicate(path: "/Users", scanRootPath: "/"))
        XCTAssertFalse(StorageScanner.isFirmlinkDuplicate(path: "/System/Library", scanRootPath: "/"))
    }
    
    func testScanningTheDataVolumeDirectlyStillWorks() {
        // Asking for that volume on purpose must not be treated as a duplicate.
        XCTAssertFalse(StorageScanner.isFirmlinkDuplicate(
            path: "/System/Volumes/Data",
            scanRootPath: "/System/Volumes/Data"
        ))
        XCTAssertFalse(StorageScanner.isFirmlinkDuplicate(
            path: "/System/Volumes/Data",
            scanRootPath: "/System/Volumes/Data/Users/tester"
        ))
    }
}
