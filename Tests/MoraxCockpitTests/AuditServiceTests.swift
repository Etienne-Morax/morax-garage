import XCTest
import Foundation
@testable import MoraxCockpitKit

final class AuditServiceTests: XCTestCase {
    
    func testParseValidAndOrphanedPlist() throws {
        try TestFixtures.withTempDirectory { tempDir in
            let auditService = AuditService()
            
            // 1. Valid plist referencing existing binary
            let validPlist = tempDir.appendingPathComponent("com.valid.agent.plist")
            let validDict: [String: Any] = [
                "Label": "com.valid.agent",
                "Program": "/bin/sh",
                "RunAtLoad": true
            ]
            let validData = try PropertyListSerialization.data(fromPropertyList: validDict, format: .xml, options: 0)
            try validData.write(to: validPlist)
            
            let validItem = auditService.parsePlist(at: validPlist, location: .userLaunchAgents)
            XCTAssertNotNil(validItem)
            XCTAssertEqual(validItem?.label, "com.valid.agent")
            XCTAssertTrue(validItem?.binaryExists ?? false)
            XCTAssertFalse(validItem?.isOrphaned ?? true)
            XCTAssertTrue(validItem?.runAtLoad ?? false)
            
            // 2. Orphaned plist referencing non-existent binary
            let orphanPlist = tempDir.appendingPathComponent("com.orphan.agent.plist")
            let orphanDict: [String: Any] = [
                "Label": "com.orphan.agent",
                "ProgramArguments": ["/opt/removed_app/bin/ghost", "--start"],
                "RunAtLoad": false
            ]
            let orphanData = try PropertyListSerialization.data(fromPropertyList: orphanDict, format: .xml, options: 0)
            try orphanData.write(to: orphanPlist)
            
            let orphanItem = auditService.parsePlist(at: orphanPlist, location: .userLaunchAgents)
            XCTAssertNotNil(orphanItem)
            XCTAssertEqual(orphanItem?.label, "com.orphan.agent")
            XCTAssertFalse(orphanItem?.binaryExists ?? true)
            XCTAssertTrue(orphanItem?.isOrphaned ?? false)
        }
    }
}
