import XCTest
@testable import MoraxCockpitKit

final class TelemetryHistoryStoreCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TelemetryHistoryStore.clearCacheForTesting()
    }

    private func makeStore() throws -> (TelemetryHistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (TelemetryHistoryStore(fileURL: directory.appendingPathComponent("history.json")), directory)
    }

    func testStoreServesCachedFile() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let t = Date(timeIntervalSince1970: 10_000)
        let record = TelemetryHistoryRecord(timestamp: t, cpuUsage: 42.0, ramUsed: 1024)
        XCTAssertTrue(store.append(record, now: t))

        let loaded1 = store.load()
        XCTAssertEqual(loaded1.records.count, 1)
        XCTAssertEqual(loaded1.records.first?.cpuUsage, 42.0)

        // Multiple consecutive reads return the same content without errors
        let loaded2 = store.load()
        XCTAssertEqual(loaded2.records.count, 1)
        XCTAssertEqual(loaded2.records.first?.ramUsed, 1024)
    }

    func testStoreInvalidatesCacheWhenFileModifiedExternally() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let t1 = Date(timeIntervalSince1970: 10_000)
        let record1 = TelemetryHistoryRecord(timestamp: t1, cpuUsage: 10.0)
        XCTAssertTrue(store.append(record1, now: t1))
        XCTAssertEqual(store.load().records.first?.cpuUsage, 10.0)
        store.flush()

        // External modification
        let t2 = Date(timeIntervalSince1970: 20_000)
        let file = TelemetryHistoryFile(records: [
            TelemetryHistoryRecord(timestamp: t2, cpuUsage: 99.0)
        ])
        let encoded = try JSONEncoder().encode(file)
        try FileManager.default.removeItem(at: store.fileURL)
        try encoded.write(to: store.fileURL)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.cpuUsage, 99.0)
    }

    @MainActor
    func testDiagnosticServiceIngestDoesNotThrowAndMaintainsHistory() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = DiagnosticService(history: store)
        XCTAssertEqual(service.historyRecordCount, 0)
        XCTAssertFalse(service.historyAvailable)

        let start = Date(timeIntervalSince1970: 1_000)
        let snap1 = SystemSnapshot(timestamp: start, ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .normal)
        service.ingest(snap1)

        XCTAssertEqual(service.historyRecordCount, 1)
        XCTAssertTrue(service.historyAvailable)

        // Second tick 1 second later (under minimum write interval of 60s)
        let snap2 = SystemSnapshot(timestamp: start.addingTimeInterval(1), ramTotal: 16_000, ramUsed: 8_200, memoryPressure: .normal)
        service.ingest(snap2)

        // Record count remains 1 and is not erroneously incremented or reloaded
        XCTAssertEqual(service.historyRecordCount, 1)
        XCTAssertTrue(service.historyAvailable)
    }
}
