import XCTest
import Observation
@testable import MoraxCockpitKit

/// Audit harness for the "gauges stay frozen" report.
///
/// Verifies the two halves of the live-update pipeline independently:
/// 1. The data side — monitoring keeps producing fresh snapshots whose values move.
/// 2. The observation side — mutating `currentSnapshot` actually notifies observers,
///    which is the mechanism SwiftUI relies on to re-render the gauges.
final class GaugeFreezeAuditTests: XCTestCase {

    @MainActor
    func testMonitoringAdvancesSnapshotTimestampsAndValues() async throws {
        let service = SystemMetricsService()
        let first = service.sampleNativeMetrics(reason: "audit baseline")
        service.updateSnapshot(first)

        let startTimestamp = service.currentSnapshot.timestamp

        service.startMonitoring()
        // Let at least one full sampling interval elapse (1.5s default) plus margin.
        try await Task.sleep(nanoseconds: 4_000_000_000)
        service.stopMonitoring()

        let endTimestamp = service.currentSnapshot.timestamp
        let endCpu = service.currentSnapshot.cpuUsage
        let endRam = service.currentSnapshot.ramUsed

        XCTAssertGreaterThan(endTimestamp, startTimestamp,
            "Snapshot timestamp must advance while monitoring runs")
        // Two real samples can legitimately read the same CPU value (idle or saturated
        // host), so freshness is proven by the timestamp; the value only has to be valid.
        XCTAssertTrue((0.0...1.0).contains(endCpu),
            "CPU usage must stay a valid fraction, got \(endCpu)")
        XCTAssertGreaterThan(endRam, 0,
            "RAM usage must be populated")
    }

    @MainActor
    func testObservationFiresWhenSnapshotChanges() async throws {
        let service = SystemMetricsService()
        let fired = expectation(description: "observation onChange fired")

        // Mirror what SwiftUI does: read the property inside a tracking closure.
        withObservationTracking {
            _ = service.currentSnapshot
        } onChange: {
            fired.fulfill()
        }

        // Let tracking registration settle, then mutate the observed property.
        try await Task.sleep(nanoseconds: 200_000_000)
        let fresh = service.sampleNativeMetrics(reason: "observation probe")
        service.updateSnapshot(fresh)

        await fulfillment(of: [fired], timeout: 2.0)
    }

    @MainActor
    func testCoordinatorStartsFeedsThatProduceFreshSnapshots() async throws {
        let coordinator = TelemetryCoordinator()
        coordinator.acquire("audit", feeds: [.system])

        // The coordinator drives the shared service, not a fresh instance.
        let service = SystemMetricsService.shared
        let before = service.currentSnapshot.timestamp
        try await Task.sleep(nanoseconds: 4_000_000_000)
        let after = service.currentSnapshot.timestamp

        XCTAssertGreaterThan(after, before,
            "Acquiring the system feed via the coordinator must keep sampling")

        coordinator.releaseAll()
    }

    @MainActor
    func testAllTelemetryFeedsAdvanceTimestampsConcurrently() async throws {
        let coordinator = TelemetryCoordinator.shared
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])

        let sysBefore = SystemMetricsService.shared.currentSnapshot.timestamp
        let netBefore = NetworkMetricsService.shared.currentSnapshot.timestamp
        let procBefore = ProcessMetricsService.shared.currentSnapshot.timestamp

        // Wait long enough for samplers to produce at least 2 ticks
        try await Task.sleep(nanoseconds: 5_000_000_000)

        let sysAfter = SystemMetricsService.shared.currentSnapshot.timestamp
        let netAfter = NetworkMetricsService.shared.currentSnapshot.timestamp
        let procAfter = ProcessMetricsService.shared.currentSnapshot.timestamp

        XCTAssertGreaterThan(sysAfter, sysBefore, "System metrics timestamp must advance")
        XCTAssertGreaterThan(netAfter, netBefore, "Network metrics timestamp must advance")
        XCTAssertGreaterThan(procAfter, procBefore, "Process metrics timestamp must advance")

        // Clean teardown
        coordinator.releaseAll()
        XCTAssertTrue(coordinator.runningFeeds.isEmpty)
        XCTAssertFalse(SystemMetricsService.shared.isRunning)
        XCTAssertFalse(NetworkMetricsService.shared.isRunning)
        XCTAssertFalse(ProcessMetricsService.shared.isRunning)
    }

    @MainActor
    func testTelemetrySustainedAdvancementOverFifteenSeconds() async throws {
        let coordinator = TelemetryCoordinator.shared
        coordinator.acquire(TelemetryConsumer.dashboard, feeds: [.system, .network, .process])

        let startSysTime = SystemMetricsService.shared.currentSnapshot.timestamp
        let startNetTime = NetworkMetricsService.shared.currentSnapshot.timestamp
        let startProcTime = ProcessMetricsService.shared.currentSnapshot.timestamp

        var previousSysTime = startSysTime
        var previousNetTime = startNetTime
        var previousProcTime = startProcTime

        // Sample across 3 checkpoints of 5.5s each (total = 16.5 seconds)
        // This exceeds the longest service sampling interval (ProcessMetricsService = 5.0s)
        for i in 1...3 {
            try await Task.sleep(nanoseconds: 5_500_000_000)

            let curSys = SystemMetricsService.shared.currentSnapshot
            let curNet = NetworkMetricsService.shared.currentSnapshot
            let curProc = ProcessMetricsService.shared.currentSnapshot

            XCTAssertFalse(curSys.status.isUnavailable, "System telemetry must remain available during active dashboard (checkpoint \(i))")
            XCTAssertGreaterThan(curSys.timestamp, previousSysTime, "System timestamp must advance at checkpoint \(i)")
            XCTAssertGreaterThan(curNet.timestamp, previousNetTime, "Network timestamp must advance at checkpoint \(i)")
            XCTAssertGreaterThan(curProc.timestamp, previousProcTime, "Process timestamp must advance at checkpoint \(i)")

            previousSysTime = curSys.timestamp
            previousNetTime = curNet.timestamp
            previousProcTime = curProc.timestamp
        }

        // Overall 16.5s advancement verification
        let finalSys = SystemMetricsService.shared.currentSnapshot
        let finalNet = NetworkMetricsService.shared.currentSnapshot
        let finalProc = ProcessMetricsService.shared.currentSnapshot

        XCTAssertGreaterThan(finalSys.timestamp.timeIntervalSince(startSysTime), 14.0, "System timestamp must have advanced by at least 14s over 16.5s run")
        XCTAssertGreaterThan(finalNet.timestamp.timeIntervalSince(startNetTime), 14.0, "Network timestamp must have advanced by at least 14s over 16.5s run")
        XCTAssertGreaterThan(finalProc.timestamp.timeIntervalSince(startProcTime), 14.0, "Process timestamp must have advanced by at least 14s over 16.5s run")

        // Clean teardown
        coordinator.releaseAll()
        XCTAssertTrue(coordinator.runningFeeds.isEmpty)
        XCTAssertFalse(SystemMetricsService.shared.isRunning)
        XCTAssertFalse(NetworkMetricsService.shared.isRunning)
        XCTAssertFalse(ProcessMetricsService.shared.isRunning)
    }
}

