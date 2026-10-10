import XCTest
import Foundation
@testable import MoraxCockpitKit

final class TrashServiceTests: XCTestCase {
    
    func testTrashSingleFixtureFile() throws {
        try TestFixtures.withTempDirectory(prefix: "trash_test") { tempDir in
            let logDir = tempDir.appendingPathComponent("logs")
            let customLog = OperationLog(customLogDirectory: logDir)
            let trashService = TrashService(operationLog: customLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash")))
            
            let fileURL = tempDir.appendingPathComponent("victim.txt")
            let testContent = "data to be moved to trash safely"
            try testContent.data(using: .utf8)?.write(to: fileURL)
            
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            
            let result = try trashService.trashItem(url: fileURL, scanRoot: tempDir)
            
            XCTAssertTrue(result.isSuccess)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertNotNil(result.trashedURL)
            XCTAssertGreaterThan(result.sizeBytes, 0)
            
            // Check that log entry was written
            let entries = customLog.readEntries()
            XCTAssertFalse(entries.isEmpty)
            XCTAssertEqual(entries.first?.action, "TRASH")
            XCTAssertEqual(entries.first?.outcome, "SUCCESS")
        }
    }
    
    func testTrashProtectedPathFailsAndLogs() throws {
        try TestFixtures.withTempDirectory(prefix: "trash_safety_test") { tempDir in
            let logDir = tempDir.appendingPathComponent("logs")
            let customLog = OperationLog(customLogDirectory: logDir)
            let trashService = TrashService(operationLog: customLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash")))
            
            let systemURL = URL(fileURLWithPath: "/System/Library")
            
            XCTAssertThrowsError(try trashService.trashItem(url: systemURL, scanRoot: nil))
            
            let entries = customLog.readEntries(errorsOnly: true)
            XCTAssertFalse(entries.isEmpty)
            XCTAssertEqual(entries.first?.outcome, "BLOCKED")
        }
    }
    
    func testTrashBatchProcessing() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "trash_batch_test") { tempDir in
            let logDir = tempDir.appendingPathComponent("logs")
            let customLog = OperationLog(customLogDirectory: logDir)
            let trashService = TrashService(operationLog: customLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash")))
            
            var urls: [URL] = []
            for i in 1...10 {
                let fileURL = tempDir.appendingPathComponent("file_\(i).dat")
                try "test data \(i)".data(using: .utf8)?.write(to: fileURL)
                urls.append(fileURL)
            }
            
            final class Counter: @unchecked Sendable {
                var updates: [(Int, Int)] = []
                let lock = NSLock()
                func add(_ done: Int, _ total: Int) {
                    lock.lock()
                    defer { lock.unlock() }
                    updates.append((done, total))
                }
            }
            let counter = Counter()
            let batchResult = try await trashService.trashBatch(urls: urls, scanRoot: tempDir) { done, total in
                counter.add(done, total)
            }
            
            XCTAssertEqual(batchResult.attemptedCount, 10)
            XCTAssertEqual(batchResult.succeededCount, 10)
            XCTAssertEqual(batchResult.skippedCount, 0)
            XCTAssertGreaterThan(batchResult.totalReclaimedBytes, 0)
            XCTAssertFalse(counter.updates.isEmpty)
            
            for url in urls {
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }
}
