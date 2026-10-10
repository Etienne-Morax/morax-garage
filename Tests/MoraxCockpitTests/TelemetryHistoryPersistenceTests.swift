import Foundation
import XCTest
@testable import MoraxCockpitKit

final class TelemetryHistoryPersistenceTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    private func makeStore(writeCoalescingDelay: TimeInterval = 3_600) throws -> (TelemetryHistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("telemetry_history_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TelemetryHistoryStore(fileURL: directory.appendingPathComponent("history.json"), writeCoalescingDelay: writeCoalescingDelay)
        return (store, directory)
    }

    private func cleanUp(_ store: TelemetryHistoryStore, _ directory: URL) {
        store.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Pruning

    func testLegacyFrozenHistoryShrinksBelowCapOnNextAppend() throws {
        let (store, directory) = try makeStore(); defer { cleanUp(store, directory) }
        let now = Date(timeIntervalSince1970: 100_000_000)
        // Shape found on disk: ~10k two-sample records at 2-minute spacing that were never re-bucketed.
        let legacy = (1...9_980).map { index in
            TelemetryHistoryRecord(timestamp: now.addingTimeInterval(-Double(index) * 120), cpuUsage: 10, ramUsed: 1_000, sampleCount: 2)
        }.reversed()
        try JSONEncoder().encode(TelemetryHistoryFile(records: Array(legacy))).write(to: store.fileURL)

        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: now, cpuUsage: 10, ramUsed: 1_000), now: now))

        let records = store.load().records
        // 24 h at 1 per 2 min (720) + 6 days of 5-min buckets (1,728) + ~6.9 days of hourly buckets (~166).
        XCTAssertLessThan(records.count, 2_700)
        XCTAssertEqual(records.reduce(0) { $0 + $1.sampleCount }, 9_980 * 2 + 1, "Compaction must not drop samples")
        XCTAssertTrue(records.filter { $0.timestamp < now.addingTimeInterval(-7 * day) }
            .allSatisfy { $0.timestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: TelemetryHistoryStore.aggregateBucket) == 0 })
    }

    func testMinuteAppendsAcrossEightDaysKeepTiersBounded() throws {
        let (store, directory) = try makeStore(); defer { cleanUp(store, directory) }
        let start = Date(timeIntervalSince1970: 100_000_000)
        let sampleCount = 8 * 24 * 60
        for minute in 0...sampleCount {
            let timestamp = start.addingTimeInterval(Double(minute) * 60)
            XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: timestamp, ramUsed: 1_000), now: timestamp))
        }
        let now = start.addingTimeInterval(Double(sampleCount) * 60)
        let records = store.load().records
        let intermediate = records.filter { $0.timestamp < now.addingTimeInterval(-day) && $0.timestamp >= now.addingTimeInterval(-7 * day) }

        // Designed retention: 1,441 detailed + 1,728 five-minute + 24 hourly records, plus
        // at most one prune interval of not-yet-compacted samples.
        XCTAssertLessThan(records.count, 3_250)
        XCTAssertLessThanOrEqual(intermediate.count, 1_728 + Int(TelemetryHistoryStore.pruneInterval / 60))
        XCTAssertEqual(records.reduce(0) { $0 + $1.sampleCount }, sampleCount + 1, "Compaction must not drop samples")
        XCTAssertTrue(records.allSatisfy { $0.ramUsed == 1_000 })
        XCTAssertEqual(records, records.sorted { $0.timestamp < $1.timestamp })
    }

    func testCompactionWeightsAveragesBySampleCount() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let bucketStart = Date(timeIntervalSince1970: (now.addingTimeInterval(-2 * day).timeIntervalSince1970 / 300).rounded(.down) * 300)
        let records = [
            TelemetryHistoryRecord(timestamp: bucketStart, cpuUsage: 10, ramUsed: 100, sampleCount: 3),
            TelemetryHistoryRecord(timestamp: bucketStart.addingTimeInterval(60), cpuUsage: 50, ramUsed: 500)
        ]
        let compacted = TelemetryHistoryStore.pruned(records, now: now)
        XCTAssertEqual(compacted.count, 1)
        XCTAssertEqual(compacted.first?.sampleCount, 4)
        XCTAssertEqual(compacted.first?.cpuUsage, 20)
        XCTAssertEqual(compacted.first?.ramUsed, 200)
        XCTAssertEqual(TelemetryHistoryStore.pruned(compacted, now: now), compacted)
    }

    // MARK: - Corrupt file

    func testDecodeFailureKeepsCorruptBackupAndStartsFresh() throws {
        let (store, directory) = try makeStore(); defer { cleanUp(store, directory) }
        let garbage = Data("{\"version\":1,\"records\":[trunc".utf8)
        try garbage.write(to: store.fileURL)

        XCTAssertTrue(store.load().records.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".corrupt-") }
        XCTAssertEqual(backups.count, 1)
        let backupURL = directory.appendingPathComponent(try XCTUnwrap(backups.first))
        XCTAssertEqual(try Data(contentsOf: backupURL), garbage)

        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t, ramUsed: 7), now: t))
        store.flush()
        let written = try JSONDecoder().decode(TelemetryHistoryFile.self, from: Data(contentsOf: store.fileURL))
        XCTAssertEqual(written.records.map(\.ramUsed), [7])
        XCTAssertEqual(try Data(contentsOf: backupURL), garbage, "The backup must survive later writes")
    }

    // MARK: - Background writes

    func testAppendsFromAllStreamsAreCoalescedIntoOneWrite() throws {
        let (store, directory) = try makeStore(); defer { cleanUp(store, directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t, ramUsed: 1), now: t))
        XCTAssertTrue(store.appendProcessSnapshot(ProcessHistoryRecord(timestamp: t, entries: [
            ProcessHistoryEntry(identity: "app", name: "App", bundlePath: nil, cpuPercent: 1, ramBytes: 2)
        ]), now: t))
        XCTAssertTrue(store.appendCacheSnapshot(CacheHistoryRecord(timestamp: t, categories: ["resolve": 3]), now: t))

        XCTAssertEqual(store.writeStatisticsForTesting().diskWriteCount, 0, "Appends must not write synchronously")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))

        store.flush()
        XCTAssertEqual(store.writeStatisticsForTesting().diskWriteCount, 1)
        let decoded = try JSONDecoder().decode(TelemetryHistoryFile.self, from: Data(contentsOf: store.fileURL))
        XCTAssertEqual(decoded, store.load(), "Disk content must match the in-memory history")
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.processRecords.count, 1)
        XCTAssertEqual(decoded.cacheRecords.count, 1)
    }

    @MainActor
    func testWriteRunsOffTheMainThread() throws {
        let (store, directory) = try makeStore(writeCoalescingDelay: 0); defer { cleanUp(store, directory) }
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(store.append(TelemetryHistoryRecord(timestamp: t, ramUsed: 1), now: t))
        store.flush()
        let stats = store.writeStatisticsForTesting()
        XCTAssertEqual(stats.diskWriteCount, 1)
        XCTAssertEqual(stats.lastWriteWasOnMainThread, false)
    }

    // MARK: - Two processes

    func testTwoProcessesSharingTheFileKeepEachOthersRecords() throws {
        let (_, directory) = try makeStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        // Separate caches stand in for the main app and the menu helper.
        let mainApp = TelemetryHistoryStore(fileURL: url, writeCoalescingDelay: 3_600, cache: TelemetryHistoryCache())
        let helper = TelemetryHistoryStore(fileURL: url, writeCoalescingDelay: 3_600, cache: TelemetryHistoryCache())
        let t = Date().addingTimeInterval(-600)
        func process(_ name: String, at date: Date) -> ProcessHistoryRecord {
            ProcessHistoryRecord(timestamp: date, entries: [ProcessHistoryEntry(identity: name, name: name, bundlePath: nil, cpuPercent: 1, ramBytes: 1)])
        }

        // Both load the (missing) file and append before either one writes.
        XCTAssertTrue(mainApp.append(TelemetryHistoryRecord(timestamp: t, ramUsed: 1), now: t))
        XCTAssertTrue(mainApp.appendProcessSnapshot(process("main", at: t), now: t))
        XCTAssertTrue(helper.append(TelemetryHistoryRecord(timestamp: t.addingTimeInterval(30), ramUsed: 2), now: t.addingTimeInterval(30)))
        XCTAssertTrue(helper.appendCacheSnapshot(CacheHistoryRecord(timestamp: t, categories: ["helper": 1]), now: t))
        mainApp.flush()
        // The main app is dirty again, with a copy that will predate the helper's write.
        XCTAssertTrue(mainApp.append(TelemetryHistoryRecord(timestamp: t.addingTimeInterval(90), ramUsed: 3), now: t.addingTimeInterval(90)))
        helper.flush()
        mainApp.flush()

        let decoded = try JSONDecoder().decode(TelemetryHistoryFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.records.compactMap(\.ramUsed), [1, 2, 3])
        XCTAssertEqual(decoded.processRecords.map(\.entries.first?.identity), ["main"])
        XCTAssertEqual(decoded.cacheRecords.map(\.categories), [["helper": 1]])
        XCTAssertEqual(mainApp.load(), decoded, "The writer's memory must include the merged records")
    }

    // MARK: - DiagnosticService

    @MainActor
    func testServiceDecodesExistingHistoryOffMainAndKeepsEarlySamples() async throws {
        let (store, directory) = try makeStore(); defer { cleanUp(store, directory) }
        let t = Date(timeIntervalSince1970: 10_000)
        let existing = (0..<3).map { TelemetryHistoryRecord(timestamp: t.addingTimeInterval(Double($0) * 60), ramUsed: 1) }
        try JSONEncoder().encode(TelemetryHistoryFile(records: existing)).write(to: store.fileURL)

        let service = DiagnosticService(history: store)
        XCTAssertEqual(service.historyRecordCount, 0, "init must not decode the file on the main actor")
        service.ingest(SystemSnapshot(timestamp: t.addingTimeInterval(180), ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .normal))

        await service.waitForHistoryLoad()
        XCTAssertEqual(service.historyRecordCount, 4, "A sample received during the load is persisted afterwards")
        XCTAssertTrue(service.historyAvailable)
    }
}
