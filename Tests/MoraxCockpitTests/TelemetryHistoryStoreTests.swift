import XCTest
@testable import MoraxCockpitKit

final class TelemetryHistoryStoreTests: XCTestCase {
    private func makeStore() throws -> (TelemetryHistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (TelemetryHistoryStore(fileURL: directory.appendingPathComponent("history.json")), directory)
    }

    func testProcessAndCacheHistoryRemainBoundedAcrossSixtyDays() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 100_000)
        let processRecords = (0..<(60 * 24 * 60)).map { minute in
            let timestamp = start.addingTimeInterval(Double(minute) * 60)
            return ProcessHistoryRecord(timestamp: timestamp, entries: [
                ProcessHistoryEntry(identity: "encoder", name: "Encoder", bundlePath: nil, cpuPercent: 90, ramBytes: Int64(minute + 1))
            ])
        }
        let cacheRecords = (0..<(60 * 24 * 60)).map { minute in
            let timestamp = start.addingTimeInterval(Double(minute) * 60)
            return CacheHistoryRecord(timestamp: timestamp, categories: ["resolve": Int64(minute + 1)])
        }
        let file = TelemetryHistoryFile(processRecords: processRecords, cacheRecords: cacheRecords)
        try JSONEncoder().encode(file).write(to: store.fileURL)
        XCTAssertTrue(store.purge(now: start.addingTimeInterval(60 * 24 * 60 * 60)))

        let purged = store.load()
        XCTAssertLessThanOrEqual(purged.processRecords.count, TelemetryHistoryStore.maxProcessRecords)
        XCTAssertLessThanOrEqual(purged.cacheRecords.count, TelemetryHistoryStore.maxCacheRecords)
        XCTAssertGreaterThan(purged.processRecords.first?.timestamp ?? .distantPast, start.addingTimeInterval(30 * 24 * 60 * 60))
        XCTAssertGreaterThan(purged.cacheRecords.first?.timestamp ?? .distantPast, start.addingTimeInterval(30 * 24 * 60 * 60))
    }

    func testInsertReadAndChronologicalOrder() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t, ramUsed: 2), now: t.addingTimeInterval(60)))
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t.addingTimeInterval(60), ramUsed: 4), now: t.addingTimeInterval(60)))
        XCTAssertEqual(store.load().records.map(\.ramUsed), [2, 4])
    }

    func testWriteCadenceBoundsDuplicateSamples() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t, cpuUsage: 1), now: t))
        XCTAssertFalse(store.append(TelemetryHistoryRecord(timestamp: t.addingTimeInterval(1), cpuUsage: 2), now: t.addingTimeInterval(1)))
        XCTAssertEqual(store.load().records.count, 1)
    }

    func testPurgeRemovesRecordsOlderThanThirtyDays() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 100_000_000)
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: now.addingTimeInterval(-31 * 24 * 60 * 60), ramUsed: 1), now: now))
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: now, ramUsed: 2), now: now))
        XCTAssertEqual(store.load().records.map(\.ramUsed), [2])
    }

    func testCorruptFileLoadsAsEmpty() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(to: store.fileURL)
        XCTAssertTrue(store.load().records.isEmpty)
    }

    func testStatisticsReturnAverageMedianMaximumAndDelta() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        for (offset, value) in [(0, 2), (60, 4), (120, 8)] {
            XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t.addingTimeInterval(TimeInterval(offset)), ramUsed: Int64(value)), now: t.addingTimeInterval(TimeInterval(offset))))
        }
        let stats = store.statistics(since: t, keyPath: \.ramUsed, now: t.addingTimeInterval(120))
        XCTAssertEqual(stats.count, 3); XCTAssertEqual(stats.average, 14.0 / 3.0)
        XCTAssertEqual(stats.median, 4); XCTAssertEqual(stats.maximum, 8); XCTAssertEqual(stats.delta, 6)
    }

    func testCompactionKeepsRecentDetailAndReachesThirtyDays() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let records = stride(from: -43_200, through: 0, by: 1).map { minute -> TelemetryHistoryRecord in
            let offset = TimeInterval(minute) * 60
            return TelemetryHistoryRecord(timestamp: now.addingTimeInterval(offset), ramUsed: Int64(abs(minute)))
        }
        let compacted = TelemetryHistoryStore.pruned(records, now: now)
        XCTAssertLessThan(compacted.count, records.count)
        XCTAssertTrue(compacted.contains { $0.timestamp == now })
        XCTAssertTrue(compacted.contains { $0.timestamp <= now.addingTimeInterval(-29 * 24 * 60 * 60) })
        XCTAssertTrue(compacted.contains { $0.sampleCount > 1 })
    }

    func testCompactionIsIdempotentAndOrdered() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let records = stride(from: -12_960, through: 0, by: 1).map { minute -> TelemetryHistoryRecord in
            TelemetryHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(minute) * 60), cpuUsage: 10)
        }
        let once = TelemetryHistoryStore.pruned(records, now: now)
        let twice = TelemetryHistoryStore.pruned(once, now: now)
        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice, twice.sorted { $0.timestamp < $1.timestamp })
    }

    func testVersionOneFileMigratesWithoutDroppingRecords() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let legacy = "{\"version\":1,\"records\":[{\"timestamp\":\(timestamp.timeIntervalSince1970),\"ramUsed\":42}]}"
        try Data(legacy.utf8).write(to: store.fileURL)
        let file = store.load()
        XCTAssertEqual(file.version, TelemetryHistoryFile.currentVersion)
        XCTAssertEqual(file.records.first?.ramUsed, 42)
    }

    func testProcessAndCacheBaselinesAreBoundedAndCadenced() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        let entry = ProcessHistoryEntry(identity: "com.example.app", name: "Example", bundlePath: nil, cpuPercent: 2, ramBytes: 100)
        XCTAssertTrue(store.appendProcessSnapshot(ProcessHistoryRecord(timestamp: t, entries: [entry]), now: t))
        XCTAssertFalse(store.appendProcessSnapshot(ProcessHistoryRecord(timestamp: t.addingTimeInterval(1), entries: [entry]), now: t.addingTimeInterval(1)))
        XCTAssertTrue(store.appendCacheSnapshot(CacheHistoryRecord(timestamp: t, categories: ["resolve": 5]), now: t))
        XCTAssertEqual(store.load().processRecords.count, 1)
        XCTAssertEqual(store.load().cacheRecords.first?.categories["resolve"], 5)
    }

    func testCacheStatisticsExposeGrowthDelta() throws {
        let (store, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.appendCacheSnapshot(CacheHistoryRecord(timestamp: t, categories: ["resolve": 2_000_000_000]), now: t))
        XCTAssertTrue(store.appendCacheSnapshot(CacheHistoryRecord(timestamp: t.addingTimeInterval(60), categories: ["resolve": 4_000_000_000]), now: t.addingTimeInterval(60)))
        let stats = store.cacheStatistics(category: "resolve", since: t, now: t.addingTimeInterval(60))
        XCTAssertEqual(stats.count, 2); XCTAssertEqual(stats.delta, 2_000_000_000)
    }
}
