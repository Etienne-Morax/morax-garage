import Foundation
import AppKit
import UniformTypeIdentifiers
import Observation

public struct ProcessResourceUsage: Identifiable, Sendable, Equatable {
    public var id: String { bundlePath ?? name }
    public let name: String
    public let bundlePath: String?
    public let cpuPercent: Double
    public let ramBytes: Int64
    public let gpuPercent: Double
    public let gpuTimeNs: UInt64
    public let processCount: Int
    public let mainPid: Int32
    
    public init(
        name: String,
        bundlePath: String?,
        cpuPercent: Double,
        ramBytes: Int64,
        gpuPercent: Double = 0.0,
        gpuTimeNs: UInt64 = 0,
        processCount: Int = 1,
        mainPid: Int32 = 0
    ) {
        self.name = name
        self.bundlePath = bundlePath
        self.cpuPercent = cpuPercent
        self.ramBytes = ramBytes
        self.gpuPercent = gpuPercent
        self.gpuTimeNs = gpuTimeNs
        self.processCount = processCount
        self.mainPid = mainPid
    }
    
    public var formattedRam: String {
        ByteCountFormatter.string(fromByteCount: ramBytes, countStyle: .memory)
    }
    
    public var formattedCpu: String {
        String(format: "%.1f%%", cpuPercent)
    }
    
    public var formattedGpu: String {
        String(format: "%.1f%%", gpuPercent)
    }
}

public struct ProcessSnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let topCpuApps: [ProcessResourceUsage]
    public let topRamApps: [ProcessResourceUsage]
    public let topGpuApps: [ProcessResourceUsage]
    public let totalRamBytes: Int64
    public let status: TopApplicationsStatus
    public let gpuStatus: TopApplicationsStatus
    
    public init(
        timestamp: Date = Date(),
        topCpuApps: [ProcessResourceUsage] = [],
        topRamApps: [ProcessResourceUsage] = [],
        topGpuApps: [ProcessResourceUsage] = [],
        totalRamBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory),
        status: TopApplicationsStatus = .noData,
        gpuStatus: TopApplicationsStatus? = nil
    ) {
        self.timestamp = timestamp
        self.topCpuApps = topCpuApps
        self.topRamApps = topRamApps
        self.topGpuApps = topGpuApps
        self.totalRamBytes = totalRamBytes
        self.status = status
        self.gpuStatus = gpuStatus ?? status
    }
}

public enum ProcessResourceSampler {
    /// Bundle path to display name. Bounded so a long session cannot accumulate an
    /// entry for every process the machine has ever run.
    private nonisolated(unsafe) static let bundleNameCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 256
        return cache
    }()
    
    /// Resolves and caches human-readable application name for a bundle URL
    public static func resolveAppName(for bundleURL: URL) -> String {
        let key = bundleURL.path as NSString
        if let cached = bundleNameCache.object(forKey: key) {
            return cached as String
        }
        
        let name: String
        if let bundle = Bundle(url: bundleURL) {
            name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? bundleURL.deletingPathExtension().lastPathComponent
        } else {
            name = bundleURL.deletingPathExtension().lastPathComponent
        }
        
        bundleNameCache.setObject(name as NSString, forKey: key)
        return name
    }
    
    /// Extracts the main `.app` bundle URL from an executable command or path
    public static func extractAppBundleURL(from pathOrCommand: String) -> URL? {
        let components = (pathOrCommand as NSString).pathComponents
        var currentPath = ""
        for c in components {
            if c == "/" {
                currentPath = "/"
            } else if currentPath == "/" {
                currentPath = "/" + c
            } else {
                currentPath = (currentPath as NSString).appendingPathComponent(c)
            }
            if currentPath.hasSuffix(".app") {
                return URL(fileURLWithPath: currentPath)
            }
        }
        return nil
    }
    
    /// Parses standard `ps -axo pid,%cpu,rss,comm` output string and aggregates by application bundle / process name
    public static func parsePsOutput(
        _ output: String,
        runningApps: [pid_t: (name: String, bundleURL: URL?)] = [:],
        limit: Int = 5
    ) -> (topCpu: [ProcessResourceUsage], topRam: [ProcessResourceUsage]) {
        struct AggregatedApp {
            var name: String
            var bundlePath: String?
            var cpu: Double
            var ram: Int64
            var count: Int
            var mainPid: Int32
        }
        
        var map: [String: AggregatedApp] = [:]
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rssKB = Int64(parts[2]) else { continue }
            
            let comm = String(parts[3])
            let ramBytes = rssKB * 1024
            
            let bundleURL = extractAppBundleURL(from: comm)
            let key: String
            let appName: String
            let bundlePathStr: String?
            
            if let bundleURL = bundleURL {
                key = bundleURL.path.lowercased()
                bundlePathStr = bundleURL.path
                appName = resolveAppName(for: bundleURL)
            } else if let runningApp = runningApps[pid] {
                let bUrl = runningApp.bundleURL
                key = bUrl?.path.lowercased() ?? runningApp.name
                bundlePathStr = bUrl?.path
                appName = runningApp.name
            } else {
                let lastComponent = URL(fileURLWithPath: comm).lastPathComponent
                key = lastComponent.lowercased()
                bundlePathStr = nil
                appName = lastComponent
            }
            
            if var existing = map[key] {
                existing.cpu += cpu
                existing.ram += ramBytes
                existing.count += 1
                if cpu > 0.0 && existing.mainPid == 0 {
                    existing.mainPid = pid
                }
                map[key] = existing
            } else {
                map[key] = AggregatedApp(
                    name: appName,
                    bundlePath: bundlePathStr,
                    cpu: cpu,
                    ram: ramBytes,
                    count: 1,
                    mainPid: pid
                )
            }
        }
        
        let all = map.values.map {
            ProcessResourceUsage(
                name: $0.name,
                bundlePath: $0.bundlePath,
                cpuPercent: max(0.0, $0.cpu),
                ramBytes: max(0, $0.ram),
                processCount: $0.count,
                mainPid: $0.mainPid
            )
        }
        
        let topCpu = Array(all.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
        let topRam = Array(all.sorted { $0.ramBytes > $1.ramBytes }.prefix(limit))
        
        return (topCpu, topRam)
    }
}

/// Blocking data sources used by `ProcessMetricsService`. They are only ever called
/// from a background context, never from the main actor. Injectable for tests.
public struct ProcessSamplingSource: Sendable {
    /// Returns the raw `ps -axo pid,%cpu,rss,comm` output, or "" on failure/timeout.
    public let readProcessTable: @Sendable () -> String
    /// Returns per-process GPU usage read from the IORegistry.
    public let readGpuEntries: @Sendable () -> [RawGpuProcessEntry]

    public init(
        readProcessTable: @escaping @Sendable () -> String,
        readGpuEntries: @escaping @Sendable () -> [RawGpuProcessEntry]
    ) {
        self.readProcessTable = readProcessTable
        self.readGpuEntries = readGpuEntries
    }

    public static let live = ProcessSamplingSource(
        readProcessTable: { ProcessMetricsService.executePs() },
        readGpuEntries: { GpuProcessSampler.collectRawEntries() }
    )
}

@Observable
@MainActor
public final class ProcessMetricsService {
    public static let shared = ProcessMetricsService()
    
    /// Upper bound for a single `/bin/ps` run before it is terminated.
    nonisolated static let psTimeoutSeconds: TimeInterval = 3.0
    /// Label of the queue the blocking ps / IORegistry readers run on.
    nonisolated static let samplingQueueLabel = "com.morax.cockpit.process-sampling"
    /// Blocking readers must not occupy a cooperative-pool thread, so they run here.
    private nonisolated static let samplingQueue = DispatchQueue(label: samplingQueueLabel, qos: .userInitiated)
    
    public var currentSnapshot = ProcessSnapshot()
    public var updateIntervalSeconds: Double = 5.0
    public var isRunning = false
    /// Gap between the GPU baseline taken on start and the first published sample,
    /// so per-app GPU % is real from the first snapshot instead of 0 for an interval.
    var gpuBaselineDelaySeconds: Double = 1.0
    
    private var monitoringTask: Task<Void, Never>?
    /// The last cancelled loop. A restart waits for it so its in-flight sample cannot
    /// land in the GPU tracker after the new baseline.
    private var stoppingTask: Task<Void, Never>?
    private let gpuTracker = GpuProcessStateTracker()
    private let source: ProcessSamplingSource
    private let ingestDiagnostics: @MainActor (ProcessSnapshot) -> Void
    private let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()
    
    /// No sampling happens here: the first sample is taken off the main actor by
    /// the monitoring loop once a consumer starts the feed.
    public init(
        source: ProcessSamplingSource = .live,
        ingestDiagnostics: (@MainActor (ProcessSnapshot) -> Void)? = nil
    ) {
        self.source = source
        self.ingestDiagnostics = ingestDiagnostics ?? { DiagnosticService.shared.ingestProcesses($0) }
    }
    
    public func startMonitoring() {
        guard monitoringTask == nil else { return }
        isRunning = true
        
        // The last snapshot stays displayed until the loop's first sample, taken
        // off the main actor (ps + IORegistry are blocking). A GPU baseline comes
        // first so that sample already carries per-app GPU deltas.
        monitoringTask = Task.detached(priority: .userInitiated) { [weak self, stoppingTask] in
            await stoppingTask?.value
            guard !Task.isCancelled, let delay = await self?.takeGpuBaseline() else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(0.0, delay) * 1_000_000_000))
            
            while !Task.isCancelled {
                let snapshot = await self?.fetchProcessSnapshot()
                if let snapshot = snapshot, !Task.isCancelled {
                    await self?.updateSnapshot(snapshot)
                }
                
                // Re-read the interval every tick so a change in settings applies
                // without restarting monitoring.
                guard let interval = await self?.updateIntervalSeconds else { break }
                let nanoseconds = UInt64(max(1.0, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }
    
    public func stopMonitoring() {
        monitoringTask?.cancel()
        stoppingTask = monitoringTask ?? stoppingTask
        monitoringTask = nil
        isRunning = false
    }
    
    public func refreshNow() async {
        let snapshot = await fetchProcessSnapshot()
        updateSnapshot(snapshot)
    }
    
    /// Resets the GPU tracker to a fresh reading and returns the delay before the
    /// first published sample.
    private nonisolated func takeGpuBaseline() async -> Double {
        let rawGpu = await Self.runOnSamplingQueue(source.readGpuEntries)
        await gpuTracker.rebaseline(rawEntries: rawGpu, now: Date())
        return await gpuBaselineDelaySeconds
    }
    
    private nonisolated static func runOnSamplingQueue<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) async -> Value {
        await withCheckedContinuation { continuation in
            samplingQueue.async { continuation.resume(returning: work()) }
        }
    }
    
    private nonisolated func fetchProcessSnapshot() async -> ProcessSnapshot {
        let runningApps = await MainActor.run {
            Self.collectRunningApps()
        }
        
        let source = source
        let (output, rawGpu) = await Self.runOnSamplingQueue {
            (source.readProcessTable(), source.readGpuEntries())
        }
        
        let (topGpu, gpuStatus) = await gpuTracker.sample(
            rawEntries: rawGpu,
            runningApps: runningApps,
            limit: 5,
            now: Date()
        )
        
        guard !output.isEmpty else {
            return ProcessSnapshot(
                timestamp: Date(),
                topCpuApps: [],
                topRamApps: [],
                topGpuApps: topGpu,
                status: .unavailable,
                gpuStatus: gpuStatus
            )
        }
        
        let (topCpu, topRam) = ProcessResourceSampler.parsePsOutput(output, runningApps: runningApps, limit: 5)
        return ProcessSnapshot(
            timestamp: Date(),
            topCpuApps: topCpu,
            topRamApps: topRam,
            topGpuApps: topGpu,
            status: .active,
            gpuStatus: gpuStatus
        )
    }
    
    @MainActor
    private static func collectRunningApps() -> [pid_t: (name: String, bundleURL: URL?)] {
        RunningApplicationsIndex.shared.snapshot()
    }
    
    public nonisolated static func executePs() -> String {
        runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid,%cpu,rss,comm"],
            timeout: psTimeoutSeconds
        )
    }
    
    /// Runs a short-lived tool and returns its stdout. A watchdog terminates the
    /// child after `timeout`; output of a killed run is discarded ("").
    nonisolated static func runCapturingOutput(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> String {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
        } catch {
            return ""
        }
        
        let box = UncheckedProcessBox(process: proc)
        let watchdog = DispatchWorkItem {
            if box.process.isRunning { box.process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        
        guard proc.terminationReason == .exit else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    public func updateSnapshot(_ snapshot: ProcessSnapshot) {
        self.currentSnapshot = snapshot
        ingestDiagnostics(snapshot)
    }
    
    /// Retrieves cached icon for application bundle path or generates fallback
    public func icon(for item: ProcessResourceUsage) -> NSImage {
        let key = (item.bundlePath ?? item.name) as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        
        let image: NSImage
        if let bundlePath = item.bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            image = NSWorkspace.shared.icon(forFile: bundlePath)
        } else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == item.mainPid }) {
            image = app.icon ?? NSWorkspace.shared.icon(for: .application)
        } else {
            // Check if generic symbol or default app icon
            if let sysImg = NSImage(systemSymbolName: "gearshape.2.fill", accessibilityDescription: nil) {
                image = sysImg
            } else {
                image = NSWorkspace.shared.icon(for: .application)
            }
        }
        
        iconCache.setObject(image, forKey: key)
        return image
    }
}

/// Lets the ps watchdog reference the child `Process` from a `@Sendable` block.
/// `Process.isRunning`/`terminate()` are safe to call from any thread.
private final class UncheckedProcessBox: @unchecked Sendable {
    let process: Process
    init(process: Process) { self.process = process }
}
