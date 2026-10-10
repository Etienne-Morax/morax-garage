import XCTest
@testable import MoraxCockpitKit

@MainActor
private final class RecordingFeedControl: TelemetryFeedControlling {
    private(set) var startCount = 0

    func startMonitoring() { startCount += 1 }
    func stopMonitoring() {}
}

@MainActor
final class MiniCockpitStoreChangeDetectionTests: XCTestCase {

    /// A store wired to its own coordinator whose feeds are spies, so `start()` never
    /// launches `macmon`, `ps` or the Keychain-backed usage and OpenAI pollers.
    private func makeIsolatedStore() -> (MiniCockpitStore, [TelemetryFeed: RecordingFeedControl]) {
        let spies = Dictionary(uniqueKeysWithValues: TelemetryFeed.allCases.map { ($0, RecordingFeedControl()) })
        let coordinator = TelemetryCoordinator(controls: spies, stopGracePeriod: 0)
        return (MiniCockpitStore(telemetryCoordinator: coordinator), spies)
    }

    private func makeSystemSnapshot(timestamp: Date, cpu: Double = 0.25, gpu: Double = 0.40) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: timestamp,
            status: .live(source: "macmon"),
            cpuUsage: cpu,
            gpuUsage: gpu,
            ramTotal: 32 * 1024 * 1024 * 1024,
            ramUsed: 16 * 1024 * 1024 * 1024
        )
    }

    private func makeProcessSnapshot(timestamp: Date) -> ProcessSnapshot {
        let app = ProcessResourceUsage(
            name: "Xcode",
            bundlePath: "/Applications/Xcode.app",
            cpuPercent: 12.5,
            ramBytes: 1024 * 1024 * 1024
        )
        return ProcessSnapshot(
            timestamp: timestamp,
            topCpuApps: [app],
            topRamApps: [app],
            totalRamBytes: 32 * 1024 * 1024 * 1024,
            status: .active
        )
    }

    func testSameSystemSampleReadTwiceAddsOneSparklinePoint() {
        let store = MiniCockpitStore()
        let sample = makeSystemSnapshot(timestamp: Date(timeIntervalSince1970: 1_000))
        let process = makeProcessSnapshot(timestamp: Date(timeIntervalSince1970: 1_000))

        store.updateMetrics(system: sample, process: process)
        let cpuCountAfterFirstRead = store.cpuSparkline.count
        let gpuCountAfterFirstRead = store.gpuSparkline.count

        store.updateMetrics(system: sample, process: process)

        XCTAssertEqual(store.cpuSparkline.count, cpuCountAfterFirstRead)
        XCTAssertEqual(store.gpuSparkline.count, gpuCountAfterFirstRead)
    }

    func testNewSystemSampleWithUnchangedValuesStillAddsSparklinePoint() {
        let store = MiniCockpitStore()
        let process = makeProcessSnapshot(timestamp: Date(timeIntervalSince1970: 1_000))

        store.updateMetrics(system: makeSystemSnapshot(timestamp: Date(timeIntervalSince1970: 1_000)), process: process)
        let countAfterFirstSample = store.cpuSparkline.count

        store.updateMetrics(system: makeSystemSnapshot(timestamp: Date(timeIntervalSince1970: 1_001.5)), process: process)

        XCTAssertEqual(store.cpuSparkline.count, countAfterFirstSample + 1)
        XCTAssertEqual(store.gpuSparkline.count, countAfterFirstSample + 1)
    }

    func testProcessSnapshotWithOnlyNewTimestampDoesNotReplaceDisplayedSnapshot() {
        let store = MiniCockpitStore()
        let sample = makeSystemSnapshot(timestamp: Date(timeIntervalSince1970: 1_000))
        let firstProcess = makeProcessSnapshot(timestamp: Date(timeIntervalSince1970: 1_000))
        store.updateMetrics(system: sample, process: firstProcess)

        let sameContentLater = makeProcessSnapshot(timestamp: Date(timeIntervalSince1970: 1_005))
        store.updateMetrics(system: sample, process: sameContentLater)

        XCTAssertEqual(store.processSnapshot.timestamp, firstProcess.timestamp)
    }

    func testRereadingOneSaturatedSampleDoesNotEscalateHealth() {
        let store = MiniCockpitStore()
        let process = makeProcessSnapshot(timestamp: Date(timeIntervalSince1970: 1_000))
        let saturatedSample = makeSystemSnapshot(timestamp: Date(timeIntervalSince1970: 1_000), cpu: 0.99, gpu: 0.10)

        store.updateMetrics(system: saturatedSample, process: process)
        let healthAfterOneSample = store.healthState

        // The same sample read again, e.g. because only the process list was published.
        for _ in 0..<5 {
            store.updateMetrics(system: saturatedSample, process: process)
        }

        XCTAssertEqual(store.healthState, healthAfterOneSample)
    }

    /// Upper bound for the store to pick up a published sample; well under the old 1 s poll.
    private static let publishPickupDeadline: TimeInterval = 0.5
    private static let settleDelayNanoseconds: UInt64 = 100_000_000
    private static let pollStepNanoseconds: UInt64 = 10_000_000

    func testStartedStoreFollowsPublishedSystemSampleWithoutWaitingForATimer() async throws {
        let service = SystemMetricsService.shared
        let originalSnapshot = service.currentSnapshot
        let (store, _) = makeIsolatedStore()
        defer {
            store.stop()
            service.currentSnapshot = originalSnapshot
        }

        store.start()
        // Let any start-up read happen before publishing, so only a push can deliver the sample.
        try await Task.sleep(nanoseconds: Self.settleDelayNanoseconds)

        let markerCpu = 0.8765
        service.currentSnapshot = makeSystemSnapshot(timestamp: Date(), cpu: markerCpu)

        let deadline = Date().addingTimeInterval(Self.publishPickupDeadline)
        while store.cpuSparkline.values.last != markerCpu, Date() < deadline {
            try await Task.sleep(nanoseconds: Self.pollStepNanoseconds)
        }

        XCTAssertEqual(store.cpuSparkline.values.last, markerCpu)
    }

    func testStoppedStoreIgnoresPublishedSamples() async throws {
        let service = SystemMetricsService.shared
        let originalSnapshot = service.currentSnapshot
        let (stoppedStore, _) = makeIsolatedStore()
        // A running store observes the same publication: once it has picked the
        // sample up, any callback the stopped store might still have armed has run too.
        let (runningStore, _) = makeIsolatedStore()
        defer {
            runningStore.stop()
            service.currentSnapshot = originalSnapshot
        }

        stoppedStore.start()
        stoppedStore.stop()
        runningStore.start()
        let countAfterStop = stoppedStore.cpuSparkline.count

        let markerCpu = 0.6543
        service.currentSnapshot = makeSystemSnapshot(timestamp: Date(), cpu: markerCpu)

        let deadline = Date().addingTimeInterval(Self.publishPickupDeadline)
        while runningStore.cpuSparkline.values.last != markerCpu, Date() < deadline {
            try await Task.sleep(nanoseconds: Self.pollStepNanoseconds)
        }

        XCTAssertEqual(runningStore.cpuSparkline.values.last, markerCpu, "The publication never reached a running store")
        XCTAssertEqual(stoppedStore.cpuSparkline.count, countAfterStop)
    }

    func testStartedStoreDeclaresItsFeedsOnTheInjectedCoordinator() {
        let (store, spies) = makeIsolatedStore()
        defer { store.stop() }

        store.start()

        let startedFeeds = Set(spies.filter { $0.value.startCount > 0 }.keys)
        XCTAssertEqual(startedFeeds, store.displayMode.telemetryFeeds)
    }
}
