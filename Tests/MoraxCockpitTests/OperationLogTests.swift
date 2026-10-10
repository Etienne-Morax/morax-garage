import XCTest
import Foundation
@testable import MoraxCockpitKit

final class OperationLogTests: XCTestCase {
    
    func testAppendAndReadLog() {
        TestFixtures.withTempDirectory(prefix: "op_log_test") { tempDir in
            let log = OperationLog(customLogDirectory: tempDir)
            
            let entry1 = OperationLogEntry(
                absolutePath: "/path/one.txt",
                action: "trash",
                outcome: "success",
                details: "test"
            )
            let entry2 = OperationLogEntry(
                absolutePath: "/path/two.txt",
                action: "trash",
                outcome: "failed",
                details: "permission denied",
                isError: true
            )
            
            log.append(entry: entry1)
            log.append(entry: entry2)
            
            let allEntries = log.readEntries()
            XCTAssertEqual(allEntries.count, 2)
            
            let errorsOnly = log.readEntries(errorsOnly: true)
            XCTAssertEqual(errorsOnly.count, 1)
            XCTAssertEqual(errorsOnly.first?.absolutePath, "/path/two.txt")
        }
    }
}
