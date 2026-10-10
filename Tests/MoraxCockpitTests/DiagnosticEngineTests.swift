import XCTest
@testable import MoraxCockpitKit

final class DiagnosticEngineTests: XCTestCase {
    func testRamUsageAloneDoesNotCreateFinding() {
        let system = SystemSnapshot(ramTotal: 16_000, ramUsed: 15_500)
        let findings = DiagnosticEngine().evaluate(DiagnosticInput(currentSystem: system))
        XCTAssertTrue(findings.isEmpty)
    }

    func testMemoryPressureCreatesExplicitFinding() {
        let findings = DiagnosticEngine().evaluate(DiagnosticInput(memoryPressure: .critical))
        XCTAssertEqual(findings.map(\.id), ["memory.pressure.critical"])
        XCTAssertEqual(findings.first?.confidence, .high)
    }

    func testUnavailablePressureIsConservative() {
        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput()).isEmpty)
    }

    func testNormalPressureAndHighRamIsNotAnAlert() {
        let system = SystemSnapshot(ramTotal: 16_000, ramUsed: 15_999, memoryPressure: .normal)
        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput(memoryPressure: .normal, currentSystem: system)).isEmpty)
    }

    func testWarningPressureMustPersistAcrossSnapshots() {
        let first = SystemSnapshot(timestamp: Date(timeIntervalSince1970: 1), memoryPressure: .normal)
        let now = SystemSnapshot(timestamp: Date(timeIntervalSince1970: 61), memoryPressure: .warning)
        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput(memoryPressure: .warning, currentSystem: now, previousSystem: first)).isEmpty)
        let previousWarning = SystemSnapshot(timestamp: Date(timeIntervalSince1970: 1), memoryPressure: .warning)
        XCTAssertEqual(DiagnosticEngine().evaluate(DiagnosticInput(memoryPressure: .warning, currentSystem: now, previousSystem: previousWarning)).count, 1)
    }

    func testHighSwapWithNormalPressureIsContextOnly() {
        let system = SystemSnapshot(ramTotal: 16_000, ramUsed: 8_000, swapTotal: 8_000, swapUsed: 7_000, memoryPressure: .normal)
        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput(memoryPressure: .normal, currentSystem: system)).isEmpty)
    }

    func testIncoherentMemoryDataDoesNotCreateAlert() {
        let system = SystemSnapshot(ramTotal: 1_000, ramUsed: 2_000, memoryPressure: .critical)
        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput(memoryPressure: .critical, currentSystem: system)).isEmpty)
    }

    func testProcessMustBeSustainedAndPresentInBothSnapshots() {
        let start = Date(timeIntervalSince1970: 1_000)
        let processBefore = ProcessResourceUsage(name: "Encoder", bundlePath: "/tmp/Encoder.app", cpuPercent: 91, ramBytes: 1)
        let processNow = ProcessResourceUsage(name: "Encoder", bundlePath: "/tmp/Encoder.app", cpuPercent: 88, ramBytes: 1)
        let before = ProcessSnapshot(timestamp: start, topCpuApps: [processBefore])
        let now = ProcessSnapshot(timestamp: start.addingTimeInterval(60), topCpuApps: [processNow])

        let findings = DiagnosticEngine().evaluate(DiagnosticInput(currentProcesses: now, previousProcesses: before))
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.category, .process)
    }

    func testShortProcessSpikeIsIgnored() {
        let start = Date(timeIntervalSince1970: 1_000)
        let before = ProcessSnapshot(timestamp: start, topCpuApps: [
            ProcessResourceUsage(name: "Encoder", bundlePath: "/tmp/Encoder.app", cpuPercent: 2, ramBytes: 1)
        ])
        let now = ProcessSnapshot(timestamp: start.addingTimeInterval(10), topCpuApps: [
            ProcessResourceUsage(name: "Encoder", bundlePath: "/tmp/Encoder.app", cpuPercent: 99, ramBytes: 1)
        ])

        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput(currentProcesses: now, previousProcesses: before)).isEmpty)
    }

    func testThermalFindingNeedsDurationAndCpuContext() {
        let start = Date(timeIntervalSince1970: 1_000)
        let before = SystemSnapshot(timestamp: start, cpuUsage: 90, cpuTemp: 92)
        let now = SystemSnapshot(timestamp: start.addingTimeInterval(60), cpuUsage: 91, cpuTemp: 93)
        let findings = DiagnosticEngine().evaluate(DiagnosticInput(currentSystem: now, previousSystem: before))

        XCTAssertEqual(findings.map(\.id), ["thermal.cpu.sustained"])
    }

    func testUnusualProcessMemoryNeedsRichBaseline() {
        let app = ProcessResourceUsage(name: "Example", bundlePath: "/tmp/Example.app", cpuPercent: 2, ramBytes: 1_000)
        let baseline = HistoryStatistics(values: [500, 500, 500, 500, 500], window: 24 * 60 * 60)
        let findings = DiagnosticEngine().evaluate(DiagnosticInput(now: Date(timeIntervalSince1970: 1_000),
            currentProcesses: ProcessSnapshot(timestamp: Date(timeIntervalSince1970: 1_000), topRamApps: [app]),
            processBaselines: ["/tmp/example.app": baseline]))
        XCTAssertEqual(findings.map(\.category), [.process])
        XCTAssertEqual(findings.first?.confidence, .medium)
    }

    func testUnusualProcessMemoryWithInsufficientBaselineIsIgnored() {
        let app = ProcessResourceUsage(name: "Example", bundlePath: "/tmp/Example.app", cpuPercent: 2, ramBytes: 1_000)
        let baseline = HistoryStatistics(values: [500, 500], window: 24 * 60 * 60)
        XCTAssertTrue(DiagnosticEngine().evaluate(DiagnosticInput(currentProcesses: ProcessSnapshot(topRamApps: [app]),
            processBaselines: ["/tmp/example.app": baseline])).isEmpty)
    }

    func testCacheGrowthIsInformationalAndRequiresHistory() {
        let cache = CacheSnapshot(timestamp: Date(timeIntervalSince1970: 1_000), resolveSizeBytes: 4_000_000_000)
        let baseline = HistoryStatistics(values: [1_000_000_000, 2_000_000_000], window: 30 * 24 * 60 * 60)
        let findings = DiagnosticEngine().evaluate(DiagnosticInput(now: cache.timestamp, cacheSnapshot: cache,
            cacheBaselines: ["resolve": baseline]))
        XCTAssertEqual(findings.first?.category, .storage)
        XCTAssertEqual(findings.first?.severity, .info)
        XCTAssertEqual(findings.first?.actions, [.openStorageMap, .showDetails])
    }
}
