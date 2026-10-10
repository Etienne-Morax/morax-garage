import XCTest
@testable import MoraxCockpitKit

/// Volume probe that can make chosen paths hang like a stale SMB mount.
private final class StaleMounts: @unchecked Sendable {
    private let lock = NSLock()
    private var stalled: Set<String> = []
    /// Paths that hang only for their next few probes, then answer normally again.
    private var remainingStalls: [String: Int] = [:]
    private var probeCounts: [String: Int] = [:]
    private var isReleased = false
    private var blockedCount = 0
    private let gate = DispatchSemaphore(value: 0)

    func stall(_ url: URL) {
        lock.withLock { _ = stalled.insert(url.standardizedFileURL.path) }
    }

    func stall(_ url: URL, times: Int) {
        lock.withLock { remainingStalls[url.standardizedFileURL.path] = times }
    }

    func probeCount(_ url: URL) -> Int {
        lock.withLock { probeCounts[url.standardizedFileURL.path, default: 0] }
    }

    func probe(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let mustBlock = lock.withLock { () -> Bool in
            probeCounts[path, default: 0] += 1
            guard !isReleased else { return false }
            if let remaining = remainingStalls[path], remaining > 0 {
                remainingStalls[path] = remaining - 1
            } else if !stalled.contains(path) {
                return false
            }
            blockedCount += 1
            return true
        }
        if mustBlock {
            gate.wait()
            return false
        }
        return PhotoSyncScanner().isVolumeAvailable(url)
    }

    /// Unblocks every hung probe so no GCD thread outlives the test.
    func releaseAll() {
        let count = lock.withLock { () -> Int in
            isReleased = true
            defer { blockedCount = 0 }
            return blockedCount
        }
        for _ in 0..<count { gate.signal() }
    }
}

/// Stands in for rsync: each copy stays open until the test completes it.
private final class FakeRsync: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<String>.Continuation] = []
    private var arguments: [[String]] = []
    private var exits: [AsyncStream<Void>.Continuation] = []
    private var terminations = 0
    private var isIgnoringTermination = false

    var startCount: Int { lock.withLock { arguments.count } }
    var terminationCount: Int { lock.withLock { terminations } }

    /// Simulates an rsync stuck in uninterruptible I/O: SIGTERM does not make it exit.
    func ignoreTermination() {
        lock.withLock { isIgnoringTermination = true }
    }

    func stream(_ executable: URL, _ args: [String]) -> StreamingProcess {
        let (exited, exitContinuation) = AsyncStream<Void>.makeStream()
        let index = lock.withLock { () -> Int in
            exits.append(exitContinuation)
            return exits.count - 1
        }
        let lines = AsyncStream<String> { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                let exitsOnTermination = lock.withLock { () -> Bool in
                    terminations += 1
                    return !isIgnoringTermination
                }
                if exitsOnTermination { exit(index) }
            }
            lock.withLock {
                continuations.append(continuation)
                arguments.append(args)
            }
        }
        // Like a real process exit, the wait ignores the caller's cancellation.
        let waiter = Task { for await _ in exited {} }
        return StreamingProcess(lines: lines, waitUntilExit: { await waiter.value })
    }

    /// Lets the process of copy `index` exit.
    func exit(_ index: Int) {
        lock.withLock { exits[index] }.finish()
    }

    /// Ends copy `index`, optionally copying the source files first like rsync would.
    func complete(_ index: Int, copying: Bool, lines: [String] = []) throws {
        let (continuation, args) = lock.withLock { (continuations[index], arguments[index]) }
        if copying {
            let source = URL(fileURLWithPath: args[args.count - 2])
            let destination = URL(fileURLWithPath: args[args.count - 1])
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for item in try FileManager.default.contentsOfDirectory(atPath: source.path) {
                try FileManager.default.copyItem(at: source.appendingPathComponent(item), to: destination.appendingPathComponent(item))
                continuation.yield(item)
            }
        }
        lines.forEach { continuation.yield($0) }
        continuation.finish()
        exit(index)
    }

    func finishAll() {
        lock.withLock { continuations }.forEach { $0.finish() }
        lock.withLock { exits }.forEach { $0.finish() }
    }
}

@MainActor
final class PhotoSyncJobQueueTests: XCTestCase {
    private var root: URL!
    private var mounts: StaleMounts!
    private var rsync: FakeRsync!

    private static let fastTimeouts = PhotoSyncTimeouts(volumeProbe: 0.2, listing: 5, projectCheck: 0.3, volumeWatch: 60)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("photo_jobs_\(UUID().uuidString)")
        mounts = StaleMounts()
        rsync = FakeRsync()
        for job in ["Job A", "Job B"] {
            try Data("abc".utf8).writeFile(to: root.appendingPathComponent("ssd/\(job)/1.jpg"))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("mac"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nasCategory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        mounts.releaseAll()
        rsync.finishAll()
        try? FileManager.default.removeItem(at: root)
    }

    private var nasCategory: URL { root.appendingPathComponent("nas/04 - Corporate") }

    private func makeService(timeouts: PhotoSyncTimeouts = fastTimeouts) -> PhotoSyncStateService {
        let defaults = UserDefaults(suiteName: "photo_jobs_\(UUID().uuidString)")!
        let mounts = mounts!
        let rsync = rsync!
        let service = PhotoSyncStateService(
            customCacheDirectory: root.appendingPathComponent("cache"),
            defaults: defaults,
            timeouts: timeouts,
            probeVolume: { mounts.probe($0) },
            streamLines: { rsync.stream($0, $1) }
        )
        service.updateConfiguration(PhotoSyncConfiguration(
            macRoot: root.appendingPathComponent("mac").path,
            ssdRoot: root.appendingPathComponent("ssd").path,
            nasRoot: root.appendingPathComponent("nas").path,
            ssdRetentionDays: 60,
            ignoredProjectKeys: []
        ))
        return service
    }

    private func project(_ key: String, in service: PhotoSyncStateService) throws -> PhotoProjectStatus {
        try XCTUnwrap(service.projects.first { $0.key == key })
    }

    private func enqueueToNAS(_ keys: [String], in service: PhotoSyncStateService) throws {
        for key in keys {
            try service.enqueueSync(for: project(key, in: service), leg: .ssdToNAS, nasParent: nasCategory.path)
        }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Condition not met in time", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Queue

    func testSecondJobWaitsForTheFirstAndBothFinishOnceVerified() async throws {
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a", "job b"], in: service)

        try await waitUntil { rsync.startCount == 1 }
        XCTAssertEqual(service.jobs.map(\.state), [.running, .queued])

        try rsync.complete(0, copying: true)
        try await waitUntil { rsync.startCount == 2 }
        XCTAssertEqual(service.jobs[0].state, .finished)
        XCTAssertEqual(service.jobs[0].transferredFiles, 1)

        try rsync.complete(1, copying: true)
        try await waitUntil { service.jobs[1].state == .finished }
        XCTAssertEqual(try project("job a", in: service).ssdToNAS, .synced)
    }

    func testJobFailsWithTheRsyncErrorWhenTheDestinationDoesNotVerify() async throws {
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a"], in: service)

        try await waitUntil { rsync.startCount == 1 }
        try rsync.complete(0, copying: false, lines: ["rsync: write failed: No space left on device"])

        try await waitUntil { !service.hasActiveJobs }
        XCTAssertEqual(service.jobs[0].state, .failed("rsync: write failed: No space left on device"))
    }

    func testCancellingARunningJobTerminatesTheCopyAndStartsTheNext() async throws {
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a", "job b"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        service.cancelJob(service.jobs[0])

        try await waitUntil { service.jobs[0].state == .cancelled && rsync.startCount == 2 }
        XCTAssertGreaterThanOrEqual(rsync.terminationCount, 1)
    }

    func testNextJobWaitsUntilTheCancelledCopyHasExited() async throws {
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a", "job b"], in: service)
        try await waitUntil { rsync.startCount == 1 }
        rsync.ignoreTermination()

        service.cancelJob(service.jobs[0])
        try await waitUntil { service.jobs[0].state == .cancelled && rsync.terminationCount == 1 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(rsync.startCount, 1)
        XCTAssertEqual(service.jobs[1].state, .queued)

        rsync.exit(0)
        try await waitUntil { rsync.startCount == 2 }
        XCTAssertEqual(service.jobs[1].state, .running)
    }

    func testCancellingAQueuedJobNeverStartsIt() async throws {
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a", "job b"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        service.cancelJob(service.jobs[1])
        try rsync.complete(0, copying: true)

        try await waitUntil { !service.hasActiveJobs }
        XCTAssertEqual(service.jobs.map(\.state), [.finished, .cancelled])
        XCTAssertEqual(rsync.startCount, 1)
    }

    // MARK: - Stale volumes

    func testEnqueueDoesNotStatTheDiskAndAMissingParentFailsTheJob() async throws {
        let service = makeService()
        await service.scan(force: true)
        let missingParent = root.appendingPathComponent("nas/99 - Gone").path

        XCTAssertNoThrow(try service.enqueueSync(for: project("job a", in: service), leg: .ssdToNAS, nasParent: missingParent))

        try await waitUntil { !service.hasActiveJobs }
        guard case .failed(let message) = service.jobs[0].state else {
            return XCTFail("Expected a failed job, got \(service.jobs[0].state)")
        }
        XCTAssertTrue(message.contains("99 - Gone"))
        XCTAssertEqual(rsync.startCount, 0)
    }

    func testVerificationOnAStaleNASTimesOutAndFreesTheQueue() async throws {
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a", "job b"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        mounts.stall(nasCategory.appendingPathComponent("Job A"))
        try rsync.complete(0, copying: true)

        try await waitUntil { rsync.startCount == 2 }
        XCTAssertEqual(service.jobs[0].state, .failed(PhotoSyncStateService.verificationTimedOutMessage))
        XCTAssertNotEqual(try project("job a", in: service).stage(retentionDays: 0), .readyToFreeSSD)
    }

    func testNASCopyIsNotVerifiedAgainstTheMacAloneWhenTheSSDSourceVanishes() async throws {
        let ssdJob = root.appendingPathComponent("ssd/Job A")
        try Data("abc".utf8).writeFile(to: root.appendingPathComponent("mac/Job A/1.jpg"))
        try Data("only on the SSD".utf8).writeFile(to: ssdJob.appendingPathComponent("2.jpg"))
        let service = makeService()
        await service.scan(force: true)
        try enqueueToNAS(["job a"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        // The NAS only received what the Mac also has, then the SSD was unplugged.
        try Data("abc".utf8).writeFile(to: nasCategory.appendingPathComponent("Job A/1.jpg"))
        try FileManager.default.removeItem(at: ssdJob)
        try rsync.complete(0, copying: false)

        try await waitUntil { !service.hasActiveJobs }
        XCTAssertNotEqual(service.jobs[0].state, .finished)
        XCTAssertNotEqual(try project("job a", in: service).ssdToNAS, .synced)
    }

    func testWatchdogFailsACopyWhoseDestinationStopsAnswering() async throws {
        let service = makeService(timeouts: PhotoSyncTimeouts(volumeProbe: 0.1, listing: 5, projectCheck: 5, volumeWatch: 0.05))
        await service.scan(force: true)
        try enqueueToNAS(["job a"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        mounts.stall(nasCategory)

        try await waitUntil { !service.hasActiveJobs }
        XCTAssertEqual(service.jobs[0].state, .failed(PhotoSyncStateService.volumeNotAnsweringMessage))
        XCTAssertEqual(rsync.terminationCount, 1)
    }

    func testWatchdogKeepsACopyRunningAfterOneSlowProbe() async throws {
        let service = makeService(timeouts: PhotoSyncTimeouts(volumeProbe: 0.1, listing: 5, projectCheck: 5, volumeWatch: 0.05))
        await service.scan(force: true)
        try enqueueToNAS(["job a"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        mounts.stall(nasCategory, times: 1)
        let probesBefore = mounts.probeCount(nasCategory)

        try await waitUntil { mounts.probeCount(nasCategory) >= probesBefore + 5 }
        XCTAssertEqual(service.jobs[0].state, .running)
        XCTAssertEqual(rsync.terminationCount, 0)

        try rsync.complete(0, copying: true)
        try await waitUntil { !service.hasActiveJobs }
        XCTAssertEqual(service.jobs[0].state, .finished)
    }

    func testWatchdogFailsACopyAfterThreeConsecutiveFailedProbes() async throws {
        let service = makeService(timeouts: PhotoSyncTimeouts(volumeProbe: 0.1, listing: 5, projectCheck: 5, volumeWatch: 0.05))
        await service.scan(force: true)
        try enqueueToNAS(["job a"], in: service)
        try await waitUntil { rsync.startCount == 1 }

        mounts.stall(nasCategory, times: PhotoSyncStateService.volumeWatchFailuresBeforeCancel)

        try await waitUntil { !service.hasActiveJobs }
        XCTAssertEqual(service.jobs[0].state, .failed(PhotoSyncStateService.volumeNotAnsweringMessage))
        XCTAssertEqual(rsync.terminationCount, 1)
    }

    func testScanTreatsAStaleNASAsOfflineAndWarns() async throws {
        mounts.stall(root.appendingPathComponent("nas"))
        let service = makeService()

        await service.scan(force: true)

        XCTAssertFalse(service.isNASOnline)
        XCTAssertTrue(service.isSSDOnline)
        XCTAssertNotNil(service.scanWarning)
        XCTAssertEqual(try project("job a", in: service).ssdToNAS, .volumeOffline)
        XCTAssertNotEqual(try project("job a", in: service).stage(retentionDays: 0), .readyToFreeSSD)
    }

    func testOpeningTheTabWithAStaleNASReturnsWithinTheProbeDeadline() async throws {
        let service = makeService()
        await service.scan(force: true)
        XCTAssertTrue(service.isNASOnline)
        mounts.stall(root.appendingPathComponent("nas"))

        let start = Date()
        await service.scan(force: false)

        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertFalse(service.isNASOnline)
    }

    // MARK: - Cache

    func testAFreshEmptyScanIsServedFromCacheInsteadOfRescanning() async throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent("ssd"))
        let service = makeService()
        await service.scan(force: true)
        XCTAssertTrue(service.projects.isEmpty)
        let firstScan = try XCTUnwrap(service.lastScanDate)

        await service.scan(force: false)

        XCTAssertEqual(service.lastScanDate, firstScan)
    }
}

private extension Data {
    func writeFile(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(to: url)
    }
}
