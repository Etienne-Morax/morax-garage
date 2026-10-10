import XCTest
@testable import MoraxCockpitKit

final class PermissionsServiceTests: XCTestCase {
    
    @MainActor
    func testPermissionTypesDefinitions() {
        let allTypes = PermissionType.allCases
        XCTAssertEqual(allTypes.count, 7)
        
        for type in allTypes {
            XCTAssertFalse(type.id.isEmpty)
            XCTAssertFalse(type.iconName.isEmpty)
            XCTAssertFalse(type.roleDescription.isEmpty)
            XCTAssertTrue(type.settingsURLString.starts(with: "x-apple.systempreferences:"))
        }
        
        XCTAssertTrue(PermissionType.fullDiskAccess.isCritical)
        XCTAssertTrue(PermissionType.downloadsFolder.isCritical)
        XCTAssertTrue(PermissionType.desktopFolder.isCritical)
        XCTAssertFalse(PermissionType.documentsFolder.isCritical)
        XCTAssertFalse(PermissionType.removableVolumes.isCritical)
        XCTAssertFalse(PermissionType.automation.isCritical)
        XCTAssertFalse(PermissionType.accessibility.isCritical)
    }
    
    @MainActor
    func testPermissionsServiceCheckAll() async {
        let service = PermissionsService()
        await service.refreshPermissions()
        
        XCTAssertEqual(service.permissions.count, PermissionType.allCases.count)
        XCTAssertFalse(service.isChecking)
        
        for record in service.permissions {
            XCTAssertFalse(record.details.isEmpty)
        }
    }
    
    /// Folder probes can block on a TCC consent prompt, so they must never run
    /// synchronously on the main actor (that froze launch before the first window).
    @MainActor
    func testInitAndCheckAllDoNotProbeSynchronously() async {
        let service = PermissionsService()
        XCTAssertTrue(service.permissions.isEmpty)

        service.checkAllPermissions()
        XCTAssertTrue(service.permissions.isEmpty)

        await service.refreshPermissions()
        XCTAssertEqual(service.permissions.count, PermissionType.allCases.count)
    }

    @MainActor
    func testCheckSinglePermissionReturnsValidStatus() {
        let service = PermissionsService()
        let (status, details) = service.checkPermission(.automation)
        
        XCTAssertEqual(status, .granted)
        XCTAssertFalse(details.isEmpty)
    }
}
