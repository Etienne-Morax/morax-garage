import Foundation
import Observation

/// One queued or running copy of a project to the next volume.
public struct PhotoSyncJob: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case queued
        case running
        case finished
        case failed(String)
        case cancelled
    }

    public let id = UUID()
    public let plan: PhotoSyncCopyPlan
    public let projectName: String
    public let expectedFiles: Int
    public var transferredFiles: Int = 0
    public var state: State = .queued

    public var isActive: Bool { state == .queued || state == .running }

    public var progress: Double {
        guard expectedFiles > 0 else { return state == .finished ? 1 : 0 }
        return min(1, Double(transferredFiles) / Double(expectedFiles))
    }
}

@Observable
@MainActor
public final class PhotoSyncStateService {
    public static let shared = PhotoSyncStateService()

    /// A full check lists every file on the NAS (minutes on SMB), so opening the tab
    /// reuses results for six hours; the Vérifier button always forces a fresh pass.
    public static let cacheTimeToLive: TimeInterval = 6 * 3_600
    private static let configurationKey = "morax_photo_sync_configuration"

    public private(set) var projects: [PhotoProjectStatus] = []
    public private(set) var destinations: [PhotoSyncDestination] = []
    public private(set) var isScanning = false
    public private(set) var scanProgress: (checked: Int, total: Int) = (0, 0)
    public private(set) var lastScanDate: Date?
    public private(set) var isSSDOnline = false
    public private(set) var isNASOnline = false
    public private(set) var jobs: [PhotoSyncJob] = []
    public private(set) var configuration: PhotoSyncConfiguration
    /// Set when the last check had to stop because a volume stopped answering.
    public private(set) var scanWarning: String?

    /// Checks that a volume root is mounted. Injected so tests can simulate a stale mount.
    public typealias VolumeProbe = @Sendable (URL) -> Bool
    /// Starts rsync, streams its output and reports its exit. Injected so tests can drive a fake copy.
    public typealias LineStreamer = @Sendable (URL, [String]) -> StreamingProcess

    private let scanner = PhotoSyncScanner()
    private let cache: CachedScanStore<PhotoProjectStatus>
    private let defaults: UserDefaults
    private let probeVolume: VolumeProbe
    private let streamLines: LineStreamer
    private let timeouts: PhotoSyncTimeouts
    private var scanTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    /// Running jobs the volume watchdog stopped because a disk stopped answering.
    private var lostVolumeJobIDs: Set<UUID> = []
    /// True from rsync launch until its process has exited, so two copies never overlap
    /// (a cancelled rsync stuck on a hung volume can outlive its job).
    private var isCopyProcessRunning = false

    public init(
        customCacheDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        timeouts: PhotoSyncTimeouts = .default,
        probeVolume: @escaping VolumeProbe = { PhotoSyncScanner().isVolumeAvailable($0) },
        streamLines: @escaping LineStreamer = { ProcessRunner.shared.streamProcess(executableURL: $0, arguments: $1) }
    ) {
        self.defaults = defaults
        self.timeouts = timeouts
        self.probeVolume = probeVolume
        self.streamLines = streamLines
        self.cache = CachedScanStore(
            fileName: "photo_sync_cache.plist",
            timeToLive: Self.cacheTimeToLive,
            directory: customCacheDirectory
        )
        self.configuration = Self.loadConfiguration(from: defaults)
        if let snapshot = cache.load() {
            self.projects = snapshot.items
            self.lastScanDate = snapshot.scanDate
        }
    }

    // MARK: - Derived state

    public var hasFreshCache: Bool { cache.isFresh(lastScanDate) }

    public var sortedProjects: [PhotoProjectStatus] {
        let retention = configuration.ssdRetentionDays
        return projects.sorted { lhs, rhs in
            let lhsStage = lhs.stage(retentionDays: retention)
            let rhsStage = rhs.stage(retentionDays: retention)
            if lhsStage != rhsStage { return lhsStage < rhsStage }
            return (lhs.lastModified ?? .distantPast) > (rhs.lastModified ?? .distantPast)
        }
    }

    public func count(of stage: PhotoSyncStage) -> Int {
        projects.filter { $0.stage(retentionDays: configuration.ssdRetentionDays) == stage }.count
    }

    public func activeJob(for projectKey: String) -> PhotoSyncJob? {
        jobs.last { $0.plan.projectKey == projectKey && $0.isActive }
    }

    public var hasActiveJobs: Bool { jobs.contains { $0.isActive } }

    // MARK: - Configuration

    public func updateConfiguration(_ newValue: PhotoSyncConfiguration) {
        guard newValue != configuration else { return }
        configuration = newValue
        if let data = try? JSONEncoder().encode(newValue) {
            defaults.set(data, forKey: Self.configurationKey)
        }
    }

    public func ignoreProject(_ project: PhotoProjectStatus) {
        var updated = configuration
        updated.ignoredProjectKeys.append(project.key)
        updateConfiguration(updated)
        projects.removeAll { $0.key == project.key }
        cache.save(items: projects, scanDate: lastScanDate ?? Date())
    }

    public func restoreIgnoredProjects() {
        var updated = configuration
        updated.ignoredProjectKeys = []
        updateConfiguration(updated)
        Task { await scan(force: true) }
    }

    private static func loadConfiguration(from defaults: UserDefaults) -> PhotoSyncConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let stored = try? JSONDecoder().decode(PhotoSyncConfiguration.self, from: data) else {
            return .default
        }
        return stored
    }

    // MARK: - Scanning

    /// Verifies every project on the Mac and the SSD against the next volume.
    /// Every blocking file-system call runs off the main actor under a deadline, so a
    /// stale SMB mount degrades to "offline" instead of freezing the tab.
    public func scan(force: Bool = false) async {
        // A fresh cache is served even when the last pass found nothing: an empty
        // result is still a result, and re-walking the roots on every visit is exactly
        // what the cache is for. The Vérifier button forces a new pass.
        if !force && hasFreshCache {
            await refreshVolumeState()
            return
        }
        guard !isScanning else { return }

        isScanning = true
        scanProgress = (0, 0)
        scanWarning = nil
        let config = configuration
        let scanner = scanner
        let probe = probeVolume
        let timeouts = timeouts

        scanTask = Task.detached(priority: .utility) { [weak self] in
            let macRoot = URL(fileURLWithPath: config.macRoot)
            let ssdRoot = URL(fileURLWithPath: config.ssdRoot)
            let nasRoot = URL(fileURLWithPath: config.nasRoot)
            let ignored = Set(config.ignoredProjectKeys)
            var warnings: [String] = []

            let ssdAnswer = await BlockingDeadline.run(timeout: timeouts.volumeProbe) { probe(ssdRoot) }
            let nasAnswer = await BlockingDeadline.run(timeout: timeouts.volumeProbe) { probe(nasRoot) }
            if Task.isCancelled {
                await self?.finishScan(results: [], wasCancelled: true)
                return
            }
            if ssdAnswer == nil { warnings.append("Le SSD ne répond pas : il est traité comme débranché.") }
            if nasAnswer == nil { warnings.append("Le NAS ne répond pas : il est traité comme débranché.") }
            let ssdOnline = ssdAnswer ?? false
            let nasOnline = nasAnswer ?? false

            let listing = await BlockingDeadline.run(timeout: timeouts.listing) {
                ScanListing(
                    macProjects: scanner.listProjects(in: macRoot, excluding: ignored),
                    ssdProjects: ssdOnline ? scanner.listProjects(in: ssdRoot, excluding: ignored) : [:],
                    nasIndex: nasOnline ? scanner.indexNAS(root: nasRoot) : [:],
                    destinations: nasOnline ? scanner.nasDestinations(root: nasRoot) : []
                )
            }
            guard let listing else {
                let warning = Task.isCancelled ? nil : "Liste des projets interrompue : un disque ne répond plus. Résultats précédents conservés."
                await self?.finishScan(results: [], wasCancelled: true, warning: warning)
                return
            }

            let keys = Set(listing.macProjects.keys).union(listing.ssdProjects.keys).sorted()
            await self?.beginScan(total: keys.count, ssdOnline: ssdOnline, nasOnline: nasOnline, destinations: listing.destinations)

            var results: [PhotoProjectStatus] = []
            var checked = 0
            for key in keys {
                if Task.isCancelled { break }
                let mac = listing.macProjects[key]
                let ssd = listing.ssdProjects[key]
                let nas = listing.nasIndex[key]
                let name = (mac ?? ssd)?.lastPathComponent ?? key
                let status = await BlockingDeadline.run(timeout: timeouts.projectCheck) {
                    scanner.status(name: name, mac: mac, ssd: ssd, nas: nas, isSSDOnline: ssdOnline, isNASOnline: nasOnline)
                }
                guard let status else {
                    // A project that cannot be read in time means a volume stopped answering:
                    // every following project would hang the same way, so stop here.
                    let warning = Task.isCancelled ? nil : "Vérification de « \(name) » interrompue : un disque ne répond plus. Résultats précédents conservés."
                    await self?.finishScan(results: [], wasCancelled: true, warning: warning)
                    return
                }
                // Empty placeholder folders are not jobs; an unreadable copy stays visible.
                if status.referenceFileCount > 0 || status.hasUnverifiableCopy {
                    results.append(status)
                }
                checked += 1
                await self?.advanceScan(checked: checked)
            }
            let warning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
            await self?.finishScan(results: results, wasCancelled: Task.isCancelled, warning: warning)
        }
        await scanTask?.value
    }

    public func cancelScan() {
        scanTask?.cancel()
    }

    /// Everything a scan lists before checking projects one by one.
    private struct ScanListing: Sendable {
        let macProjects: [String: URL]
        let ssdProjects: [String: URL]
        let nasIndex: [String: URL]
        let destinations: [PhotoSyncDestination]
    }

    /// Updates the volume chips without touching the disk from the main actor.
    private func refreshVolumeState() async {
        let probe = probeVolume
        let timeouts = timeouts
        let ssdRoot = URL(fileURLWithPath: configuration.ssdRoot)
        let nasRoot = URL(fileURLWithPath: configuration.nasRoot)
        async let ssdAnswer = BlockingDeadline.run(timeout: timeouts.volumeProbe) { probe(ssdRoot) }
        async let nasAnswer = BlockingDeadline.run(timeout: timeouts.volumeProbe) { probe(nasRoot) }
        let (ssd, nas) = await (ssdAnswer, nasAnswer)
        isSSDOnline = ssd ?? false
        isNASOnline = nas ?? false
        guard isNASOnline && destinations.isEmpty else { return }
        let scanner = scanner
        if let found = await BlockingDeadline.run(timeout: timeouts.listing, { scanner.nasDestinations(root: nasRoot) }) {
            destinations = found
        }
    }

    private func beginScan(total: Int, ssdOnline: Bool, nasOnline: Bool, destinations: [PhotoSyncDestination]) {
        scanProgress = (0, total)
        isSSDOnline = ssdOnline
        isNASOnline = nasOnline
        self.destinations = destinations
    }

    private func advanceScan(checked: Int) {
        scanProgress = (checked, scanProgress.total)
    }

    private func finishScan(results: [PhotoProjectStatus], wasCancelled: Bool, warning: String? = nil) {
        isScanning = false
        scanWarning = warning
        guard !wasCancelled else { return }
        let now = Date()
        projects = results
        lastScanDate = now
        cache.save(items: results, scanDate: now)
    }

    // MARK: - Copy jobs

    /// Queues the copy that brings `project` to the next stage of the workflow.
    /// `nasParent` is only required when the project does not exist on the NAS yet.
    public func enqueueSync(for project: PhotoProjectStatus, leg: PhotoSyncLeg, nasParent: String? = nil) throws {
        // The file-system checks (`validate`) run in the job, off the main actor:
        // stat-ing a stale NAS mount here would freeze the UI.
        let plan = try makePlan(for: project, leg: leg, nasParent: nasParent)
        let status = leg == .macToSSD ? project.macToSSD : project.ssdToNAS
        let expected: Int
        if case .incomplete(let missingFiles, _) = status {
            expected = missingFiles
        } else {
            expected = project.referenceFileCount
        }
        jobs.append(PhotoSyncJob(plan: plan, projectName: project.name, expectedFiles: expected))
        startNextJobIfIdle()
    }

    public func cancelJob(_ job: PhotoSyncJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        if jobs[index].state == .running {
            jobTask?.cancel()
        } else if jobs[index].state == .queued {
            jobs[index].state = .cancelled
        }
    }

    public func clearFinishedJobs() {
        jobs.removeAll { !$0.isActive }
    }

    func makePlan(for project: PhotoProjectStatus, leg: PhotoSyncLeg, nasParent: String?) throws -> PhotoSyncCopyPlan {
        switch leg {
        case .macToSSD:
            guard let macPath = project.macPath else { throw PhotoSyncCopyError.sourceMissing(project.name) }
            let destination = project.ssdPath.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: configuration.ssdRoot).appendingPathComponent(project.name)
            return PhotoSyncCopyPlan(projectKey: project.key, leg: leg, source: URL(fileURLWithPath: macPath), destination: destination)
        case .ssdToNAS:
            guard let sourcePath = project.ssdPath ?? project.macPath else { throw PhotoSyncCopyError.sourceMissing(project.name) }
            let destination: URL
            if let nasPath = project.nasPath {
                destination = URL(fileURLWithPath: nasPath)
            } else if let nasParent {
                destination = URL(fileURLWithPath: nasParent).appendingPathComponent(project.name)
            } else {
                throw PhotoSyncCopyError.destinationParentMissing(configuration.nasRoot)
            }
            guard destination.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: configuration.nasRoot).standardizedFileURL.path + "/") else {
                throw PhotoSyncCopyError.unsafeDestination(destination.path)
            }
            return PhotoSyncCopyPlan(projectKey: project.key, leg: leg, source: URL(fileURLWithPath: sourcePath), destination: destination)
        }
    }

    private func startNextJobIfIdle() {
        guard !isCopyProcessRunning, !jobs.contains(where: { $0.state == .running }),
              let index = jobs.firstIndex(where: { $0.state == .queued }) else { return }
        jobs[index].state = .running
        let job = jobs[index]
        let streamLines = streamLines
        let probeTimeout = timeouts.volumeProbe

        jobTask = Task { [weak self] in
            let preflight = await BlockingDeadline.run(timeout: probeTimeout) { Self.validationFailure(of: job.plan) }
            if Task.isCancelled {
                self?.endJob(job.id, state: .cancelled)
                return
            }
            switch preflight {
            case .none:
                self?.endJob(job.id, state: .failed(Self.volumeNotAnsweringMessage))
                return
            case .some(.some(let failure)):
                self?.endJob(job.id, state: .failed(failure))
                return
            case .some(.none):
                break
            }

            let watchdog = Task { [weak self] in await self?.watchVolumes(during: job) }
            var transferred = 0
            self?.isCopyProcessRunning = true
            let copy = streamLines(PhotoSyncCopyPlan.rsyncURL, job.plan.arguments)
            var lastError: String?
            // Cancelling this task ends the iteration, which terminates rsync.
            for await line in copy.lines {
                if line.hasPrefix("rsync:") || line.hasPrefix("rsync error") {
                    lastError = line
                    TelemetryLogger.process.error("Photo sync rsync: \(line, privacy: .public)")
                } else if PhotoSyncCopyPlan.isTransferredFileLine(line) {
                    transferred += 1
                    self?.updateJob(job.id) { $0.transferredFiles = transferred }
                }
            }
            watchdog.cancel()
            await self?.completeJob(job, wasCancelled: Task.isCancelled, rsyncError: lastError)
            await copy.waitUntilExit()
            self?.isCopyProcessRunning = false
            self?.startNextJobIfIdle()
        }
    }

    static let volumeNotAnsweringMessage = "Le disque ne répond plus (débranché ou NAS injoignable) : relance la copie quand il est de retour."
    static let verificationTimedOutMessage = "Vérification impossible : le disque ne répond plus. Relance Vérifier quand il est de retour."

    /// The plan's file-system checks, as a message, or `nil` when the copy can start.
    nonisolated private static func validationFailure(of plan: PhotoSyncCopyPlan) -> String? {
        do {
            try plan.validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Consecutive failed watch rounds before a copy is stopped. A saturated SMB link can
    /// answer one metadata call late while rsync writes, which must not kill a long copy.
    static let volumeWatchFailuresBeforeCancel = 3

    /// Stops a running copy whose source or destination stops answering, so one dead
    /// volume cannot leave the whole queue "running" forever. A round fails when a probe
    /// answers "missing" or misses its deadline; a healthy round resets the count.
    private func watchVolumes(during job: PhotoSyncJob) async {
        let probe = probeVolume
        let timeouts = timeouts
        let roots = [job.plan.source, job.plan.destination.deletingLastPathComponent()]
        var consecutiveFailures = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(timeouts.volumeWatch))
            var isRoundHealthy = true
            for root in roots {
                let answer = await BlockingDeadline.run(timeout: timeouts.volumeProbe) { probe(root) }
                guard !Task.isCancelled else { return }
                if answer != true {
                    isRoundHealthy = false
                    break
                }
            }
            consecutiveFailures = isRoundHealthy ? 0 : consecutiveFailures + 1
            guard consecutiveFailures >= Self.volumeWatchFailuresBeforeCancel else { continue }
            guard jobs.first(where: { $0.id == job.id })?.state == .running else { return }
            lostVolumeJobIDs.insert(job.id)
            jobTask?.cancel()
            return
        }
    }

    private func updateJob(_ id: UUID, _ change: (inout PhotoSyncJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func endJob(_ id: UUID, state: PhotoSyncJob.State) {
        updateJob(id) { $0.state = state }
        startNextJobIfIdle()
    }

    /// The copy only counts as done once the destination re-verifies as identical.
    private func completeJob(_ job: PhotoSyncJob, wasCancelled: Bool, rsyncError: String?) async {
        if lostVolumeJobIDs.remove(job.id) != nil {
            // Re-verifying a volume that just stopped answering would only wait for the deadline.
            endJob(job.id, state: .failed(Self.volumeNotAnsweringMessage))
            return
        }
        if wasCancelled {
            updateJob(job.id) { $0.state = .cancelled }
        }
        let outcome = await reverify(projectKey: job.plan.projectKey, copiedTo: job.plan)
        if !wasCancelled {
            updateJob(job.id) {
                guard case .refreshed(let refreshed) = outcome else {
                    $0.state = .failed(outcome == .timedOut ? Self.verificationTimedOutMessage : (rsyncError ?? "La copie est incomplète après vérification."))
                    return
                }
                let status = job.plan.leg == .macToSSD ? refreshed.macToSSD : refreshed.ssdToNAS
                if status.isSynced {
                    $0.state = .finished
                } else if status == .unverifiable {
                    $0.state = .failed(rsyncError ?? "Vérification impossible : une copie n'a pu être lue qu'en partie.")
                } else {
                    $0.state = .failed(rsyncError ?? "La copie est incomplète après vérification.")
                }
            }
        }
        startNextJobIfIdle()
    }

    private enum Reverification: Equatable {
        case refreshed(PhotoProjectStatus)
        case projectGone
        /// A copy did not answer before the deadline (stale mount): nothing is known.
        case timedOut
    }

    private func reverify(projectKey: String, copiedTo plan: PhotoSyncCopyPlan) async -> Reverification {
        guard let current = projects.first(where: { $0.key == projectKey }) else { return .projectGone }
        let scanner = scanner
        let probe = probeVolume
        let ssdRoot = URL(fileURLWithPath: configuration.ssdRoot)
        let nasRoot = URL(fileURLWithPath: configuration.nasRoot)
        let mac = current.macPath.map { URL(fileURLWithPath: $0) }
        let ssd = plan.leg == .macToSSD ? plan.destination : current.ssdPath.map { URL(fileURLWithPath: $0) }
        let nas = plan.leg == .ssdToNAS ? plan.destination : current.nasPath.map { URL(fileURLWithPath: $0) }
        let name = current.name
        // A copy that is missing reads as "missing" (safe: it asks for a copy), except the
        // SSD when it is the source of a NAS copy: dropping it would shrink the reference
        // and could pass a partial archive as synced, so it stays and reads as unreadable.
        let dropsMissingSSD = plan.leg == .macToSSD

        let refreshed = await BlockingDeadline.run(timeout: timeouts.projectCheck) {
            scanner.status(
                name: name,
                mac: mac,
                ssd: dropsMissingSSD ? ssd.flatMap { probe($0) ? $0 : nil } : ssd,
                nas: nas.flatMap { probe($0) ? $0 : nil },
                isSSDOnline: probe(ssdRoot),
                isNASOnline: probe(nasRoot)
            )
        }
        guard let refreshed else { return .timedOut }

        if let index = projects.firstIndex(where: { $0.key == projectKey }) {
            projects[index] = refreshed
            cache.save(items: projects, scanDate: lastScanDate ?? Date())
        }
        return .refreshed(refreshed)
    }
}
