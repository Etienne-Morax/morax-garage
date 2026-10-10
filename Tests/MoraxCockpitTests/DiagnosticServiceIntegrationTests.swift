import XCTest
@testable import MoraxCockpitKit

@MainActor
final class DiagnosticServiceIntegrationTests: XCTestCase {
    func testIndependentSystemProcessAndCacheFindingsCoexist() throws {
        try TestFixtures.withTempDirectory(prefix: "diagnostic_service") { directory in
            let service = DiagnosticService(history: TelemetryHistoryStore(fileURL: directory.appendingPathComponent("history.json")))
            let start = Date(timeIntervalSince1970: 10_000)

            service.ingest(SystemSnapshot(timestamp: start, ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .critical))
            let systemID = try XCTUnwrap(service.findings.first?.id)

            let process = ProcessResourceUsage(name: "Encoder", bundlePath: "/tmp/Encoder.app", cpuPercent: 92, ramBytes: 1_000)
            service.ingestProcesses(ProcessSnapshot(timestamp: start, topCpuApps: [process]))
            service.ingestProcesses(ProcessSnapshot(timestamp: start.addingTimeInterval(60), topCpuApps: [process]))
            let processID = try XCTUnwrap(service.findings.first(where: { $0.category == .process })?.id)

            service.ingestCache(CacheSnapshot(timestamp: start, resolveSizeBytes: 1_000_000_000))
            service.ingestCache(CacheSnapshot(timestamp: start.addingTimeInterval(60), resolveSizeBytes: 2_000_000_000))
            service.ingestCache(CacheSnapshot(timestamp: start.addingTimeInterval(120), resolveSizeBytes: 4_000_000_000))

            XCTAssertEqual(Set(service.findings.map(\.category)), [.memory, .process, .storage])
            XCTAssertEqual(Set(service.findings.map(\.id)), [systemID, processID, "cache.growth.resolve"])
            XCTAssertEqual(service.findings.map(\.id), service.findings.sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.id < $1.id }.map(\.id))

            service.ingest(SystemSnapshot(timestamp: start.addingTimeInterval(180), ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .normal))
            XCTAssertEqual(Set(service.findings.map(\.id)), [processID, "cache.growth.resolve"])
        }
    }

    func testDismissIndividualFindingHidesFromFindings() throws {
        TestFixtures.withTempDirectory(prefix: "diagnostic_service_dismiss") { directory in
            let service = DiagnosticService(history: TelemetryHistoryStore(fileURL: directory.appendingPathComponent("history.json")))
            let start = Date(timeIntervalSince1970: 10_000)

            service.ingest(SystemSnapshot(timestamp: start, ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .critical))
            XCTAssertEqual(service.findings.count, 1)

            let findingID = service.findings[0].id
            service.dismissFinding(id: findingID)

            XCTAssertEqual(service.findings.count, 0)
            XCTAssertTrue(service.dismissedFindingIDs.contains(findingID))

            // Re-ingest same finding keeps it dismissed
            service.ingest(SystemSnapshot(timestamp: start.addingTimeInterval(10), ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .critical))
            XCTAssertEqual(service.findings.count, 0)
        }
    }

    func testDismissAllFindingsHidesAllActiveFindings() throws {
        TestFixtures.withTempDirectory(prefix: "diagnostic_service_dismiss_all") { directory in
            let service = DiagnosticService(history: TelemetryHistoryStore(fileURL: directory.appendingPathComponent("history.json")))
            let start = Date(timeIntervalSince1970: 10_000)

            service.ingest(SystemSnapshot(timestamp: start, ramTotal: 16_000, ramUsed: 8_000, memoryPressure: .critical))
            service.ingestCache(CacheSnapshot(timestamp: start, resolveSizeBytes: 1_000_000_000))
            service.ingestCache(CacheSnapshot(timestamp: start.addingTimeInterval(60), resolveSizeBytes: 2_000_000_000))
            service.ingestCache(CacheSnapshot(timestamp: start.addingTimeInterval(120), resolveSizeBytes: 4_000_000_000))

            XCTAssertEqual(service.findings.count, 2)

            service.dismissAllFindings()
            XCTAssertEqual(service.findings.count, 0)
        }
    }
}

