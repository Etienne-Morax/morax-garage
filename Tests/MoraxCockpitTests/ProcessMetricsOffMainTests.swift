import XCTest
@testable import MoraxCockpitKit

/// Thread-safe recorder for calls made by an injected sampling source.
private final class SamplingProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _psCalls = 0
    private var _gpuCalls = 0
    private var _ranOnMain = false
    private var _ranOffSamplingQueue = false

    var psCalls: Int { lock.withLock { _psCalls } }
    var gpuCalls: Int { lock.withLock { _gpuCalls } }
    var ranOnMain: Bool { lock.withLock { _ranOnMain } }
    var ranOffSamplingQueue: Bool { lock.withLock { _ranOffSamplingQueue } }

    private static var isOnSamplingQueue: Bool {
        String(cString: __dispatch_queue_get_label(nil)) == ProcessMetricsService.samplingQueueLabel
    }

    func recordPs() {
        lock.withLock {
            _psCalls += 1
            _ranOnMain = _ranOnMain || Thread.isMainThread
            _ranOffSamplingQueue = _ranOffSamplingQueue || !Self.isOnSamplingQueue
        }
    }

    func recordGpu() {
        lock.withLock {
            _gpuCalls += 1
            _ranOnMain = _ranOnMain || Thread.isMainThread
            _ranOffSamplingQueue = _ranOffSamplingQueue || !Self.isOnSamplingQueue
        }
    }

    /// Accumulated GPU time that grows by `step` on every IORegistry read.
    func nextGpuTime(step: UInt64) -> UInt64 {
        lock.withLock { UInt64(_gpuCalls) * step }
    }
}

final class ProcessMetricsOffMainTests: XCTestCase {
    private static let cannedPs = """
      PID  %CPU    RSS COMM
     999991  42.0 100000 /Applications/MoraxFakeProbe.app/Contents/MacOS/MoraxFakeProbe
    """
    private static let gateTimeout: TimeInterval = 5.0
    private static let publishTimeout: TimeInterval = 3.0
    private static let nonBlockingBudget: TimeInterval = 0.5
    /// Long enough that the loop never ticks a second time during a test.
    private static let idleInterval: Double = 600
    /// Keeps the start-up GPU baseline short so tests stay fast.
    private static let testBaselineDelay: Double = 0.05
    private static let fakeGpuPid: pid_t = 999_992
    /// 100 ms of GPU time per read: far above 0 % over any test-sized interval.
    private static let gpuTimeStepNs: UInt64 = 100_000_000

    private static func makeSource(probe: SamplingProbe, gate: DispatchSemaphore? = nil) -> ProcessSamplingSource {
        ProcessSamplingSource(
            readProcessTable: {
                probe.recordPs()
                if let gate { _ = gate.wait(timeout: .now() + gateTimeout) }
                return cannedPs
            },
            readGpuEntries: {
                probe.recordGpu()
                return []
            }
        )
    }

    private static func makeBusyGpuSource(probe: SamplingProbe) -> ProcessSamplingSource {
        ProcessSamplingSource(
            readProcessTable: {
                probe.recordPs()
                return cannedPs
            },
            readGpuEntries: {
                probe.recordGpu()
                return [RawGpuProcessEntry(
                    pid: fakeGpuPid,
                    name: "MoraxFakeGpuProbe",
                    accumulatedGpuTimeNs: probe.nextGpuTime(step: gpuTimeStepNs)
                )]
            }
        )
    }

    @MainActor
    private func makeService(source: ProcessSamplingSource) -> ProcessMetricsService {
        let service = ProcessMetricsService(source: source, ingestDiagnostics: { _ in })
        service.updateIntervalSeconds = Self.idleInterval
        service.gpuBaselineDelaySeconds = Self.testBaselineDelay
        return service
    }

    @MainActor
    private func waitForPublishedSample(_ service: ProcessMetricsService, after date: Date) async throws {
        let deadline = Date().addingTimeInterval(Self.publishTimeout)
        while service.currentSnapshot.timestamp <= date || service.currentSnapshot.status != .active {
            guard Date() < deadline else {
                XCTFail("No snapshot published within \(Self.publishTimeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    func testInitDoesNotSample() {
        let probe = SamplingProbe()
        let service = ProcessMetricsService(source: Self.makeSource(probe: probe), ingestDiagnostics: { _ in })

        XCTAssertEqual(probe.psCalls, 0, "init must not spawn ps")
        XCTAssertEqual(probe.gpuCalls, 0, "init must not walk the IORegistry")
        XCTAssertEqual(service.currentSnapshot.status, .noData)
    }

    @MainActor
    func testStartMonitoringReturnsWithoutBlockingAndPublishesFromBackground() async throws {
        let probe = SamplingProbe()
        let gate = DispatchSemaphore(value: 0)
        let service = makeService(source: Self.makeSource(probe: probe, gate: gate))
        let before = Date()

        // The ps reader blocks until the gate opens: a synchronous sample on the
        // main actor would stall startMonitoring for the whole gate timeout.
        let started = Date()
        service.startMonitoring()
        let elapsed = Date().timeIntervalSince(started)
        gate.signal()
        defer { service.stopMonitoring() }

        XCTAssertLessThan(elapsed, Self.nonBlockingBudget, "startMonitoring blocked for \(elapsed)s")

        try await waitForPublishedSample(service, after: before)

        XCTAssertFalse(probe.ranOnMain, "ps / IORegistry sampling must run off the main thread")
        XCTAssertFalse(probe.ranOffSamplingQueue, "blocking readers must not run on the cooperative pool")
        XCTAssertEqual(service.currentSnapshot.topCpuApps.first?.cpuPercent ?? 0, 42.0, accuracy: 0.01)
        XCTAssertEqual(probe.psCalls, 1)
        XCTAssertEqual(probe.gpuCalls, 2, "one GPU baseline read, then one sampled read")
    }

    @MainActor
    func testEachStartSamplesExactlyOnce() async throws {
        let probe = SamplingProbe()
        let service = makeService(source: Self.makeSource(probe: probe))

        let firstStart = Date()
        service.startMonitoring()
        try await waitForPublishedSample(service, after: firstStart)
        XCTAssertEqual(probe.psCalls, 1, "first start must spawn ps once, not twice")
        service.stopMonitoring()

        // Dashboard revisit after the grace period: the feed restarts.
        let secondStart = Date()
        service.startMonitoring()
        try await waitForPublishedSample(service, after: secondStart)
        service.stopMonitoring()

        XCTAssertEqual(probe.psCalls, 2, "restart must spawn ps once, not twice")
        XCTAssertEqual(probe.gpuCalls, 4, "each start reads a GPU baseline, then samples once")
    }

    @MainActor
    func testFirstSnapshotAfterEachStartReportsGpuUsage() async throws {
        let probe = SamplingProbe()
        let service = makeService(source: Self.makeBusyGpuSource(probe: probe))

        let firstStart = Date()
        service.startMonitoring()
        try await waitForPublishedSample(service, after: firstStart)
        let firstGpu = service.currentSnapshot.topGpuApps.first?.gpuPercent ?? 0

        // Occlusion pause then immediate resume: the restart must rebaseline, not
        // publish 0 % for a whole interval.
        service.stopMonitoring()
        let secondStart = Date()
        service.startMonitoring()
        try await waitForPublishedSample(service, after: secondStart)
        let secondGpu = service.currentSnapshot.topGpuApps.first?.gpuPercent ?? 0
        service.stopMonitoring()

        XCTAssertGreaterThan(firstGpu, 0, "first snapshot after start must carry GPU deltas")
        XCTAssertGreaterThan(secondGpu, 0, "first snapshot after a quick restart must carry GPU deltas")
    }

    func testRunCapturingOutputReturnsStdout() {
        let output = ProcessMetricsService.runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["morax"],
            timeout: 5
        )
        XCTAssertEqual(output, "morax\n")
    }

    func testRunCapturingOutputTerminatesHungChildAfterTimeout() {
        let started = Date()
        let output = ProcessMetricsService.runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            timeout: 0.3
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(output, "")
        XCTAssertLessThan(elapsed, 5, "watchdog must terminate a hung child")
    }
}
