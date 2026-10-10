import Foundation
import SwiftUI
import Combine
import Darwin
import os

public enum TelemetryStatus: Sendable, Equatable {
    case live(source: String)
    case fallback(reason: String)
    case unavailable(reason: String)
    case error(String)
    
    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }
    
    public var isFallback: Bool {
        if case .fallback = self { return true }
        return false
    }
    
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
    
    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
    
    public var statusLabel: String {
        switch self {
        case .live(let src): return "\(src) live"
        case .fallback: return "native fallback"
        case .unavailable: return "unavailable"
        case .error: return "error"
        }
    }
    
    public var description: String {
        switch self {
        case .live(let src):
            return "Real-time hardware telemetry streaming via \(src)"
        case .fallback(let reason):
            return "Darwin native metrics: \(reason)"
        case .unavailable(let reason):
            return "Telemetry unavailable: \(reason)"
        case .error(let msg):
            return "Telemetry error: \(msg)"
        }
    }
}

public enum TelemetryFailureReason: Sendable, Equatable {
    case binaryNotFound
    case launchFailed(String)
    case streamExited(consecutiveFailures: Int)
    case streamCorrupted
    case serviceStopped
}

public struct DiskVolumeInfo: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let isRemovable: Bool
    
    public var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }
    
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    
    public init(name: String, path: String, totalBytes: Int64, freeBytes: Int64, isRemovable: Bool) {
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.isRemovable = isRemovable
    }
}

public struct MetricPoint: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let cpuUsage: Double
    public let gpuUsage: Double
    public let ramUsedBytes: Int64
    public let swapUsedBytes: Int64
    public let totalPowerWatts: Double
    public let cpuTemp: Double?
    
    public init(
        date: Date,
        cpuUsage: Double,
        gpuUsage: Double,
        ramUsedBytes: Int64,
        swapUsedBytes: Int64,
        totalPowerWatts: Double,
        cpuTemp: Double?
    ) {
        self.date = date
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.ramUsedBytes = ramUsedBytes
        self.swapUsedBytes = swapUsedBytes
        self.totalPowerWatts = totalPowerWatts
        self.cpuTemp = cpuTemp
    }
}

public struct SystemSnapshot: Sendable {
    public let timestamp: Date
    public let status: TelemetryStatus
    public let isMacmonActive: Bool
    public let cpuUsage: Double
    public let gpuUsage: Double
    public let eCpuUsage: Double
    public let pCpuUsage: Double
    public let eCoreCount: Int
    public let pCoreCount: Int
    
    /// Métriques mémoire canoniques détaillées conformes au Moniteur d'activité macOS
    public let memory: SystemMemoryMetrics
    
    public var ramTotal: Int64 { memory.totalPhysicalBytes }
    public var ramUsed: Int64 { memory.usedBytes }
    public var ramAvailable: Int64 { memory.availableBytes }
    public var ramCompressed: Int64 { memory.compressedBytes }
    public var ramCached: Int64 { memory.cachedFilesBytes }
    public var ramFree: Int64 { memory.freeBytes }
    public var swapTotal: Int64 { memory.swapTotalBytes }
    public var swapUsed: Int64 { memory.swapUsedBytes }
    public var compressedMemory: Int64? { memory.compressedBytes }
    public var memoryPressure: MemoryPressureState? { memory.memoryPressure }
    
    public let systemPower: Double
    public let cpuPower: Double
    public let gpuPower: Double
    public let anePower: Double
    public let ramPower: Double
    
    public let cpuTemp: Double?
    public let gpuTemp: Double?
    public let fanSpeedRPM: Int?
    public let gpuFreqMHz: Double?
    
    public let diskVolumes: [DiskVolumeInfo]
    public let uptimeSeconds: TimeInterval
    
    public init(
        timestamp: Date = Date(),
        status: TelemetryStatus = .unavailable(reason: "Telemetry service not running"),
        isMacmonActive: Bool? = nil,
        cpuUsage: Double = 0,
        gpuUsage: Double = 0,
        eCpuUsage: Double = 0,
        pCpuUsage: Double = 0,
        eCoreCount: Int = 0,
        pCoreCount: Int = 0,
        memory: SystemMemoryMetrics? = nil,
        ramTotal: Int64 = 0,
        ramUsed: Int64 = 0,
        swapTotal: Int64 = 0,
        swapUsed: Int64 = 0,
        compressedMemory: Int64? = nil,
        memoryPressure: MemoryPressureState? = nil,
        systemPower: Double = 0,
        cpuPower: Double = 0,
        gpuPower: Double = 0,
        anePower: Double = 0,
        ramPower: Double = 0,
        cpuTemp: Double? = nil,
        gpuTemp: Double? = nil,
        fanSpeedRPM: Int? = nil,
        gpuFreqMHz: Double? = nil,
        diskVolumes: [DiskVolumeInfo] = [],
        uptimeSeconds: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.timestamp = timestamp
        self.status = status
        self.isMacmonActive = isMacmonActive ?? status.isLive
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.eCpuUsage = eCpuUsage
        self.pCpuUsage = pCpuUsage
        self.eCoreCount = eCoreCount
        self.pCoreCount = pCoreCount
        
        let resolvedTotalRam = memory?.totalPhysicalBytes ?? (ramTotal > 0 ? ramTotal : Int64(ProcessInfo.processInfo.physicalMemory))
        let resolvedUsedRam = memory?.usedBytes ?? ramUsed
        let resolvedSwapTotal = memory?.swapTotalBytes ?? swapTotal
        let resolvedSwapUsed = memory?.swapUsedBytes ?? swapUsed
        let resolvedCompressed = memory?.compressedBytes ?? (compressedMemory ?? 0)
        let resolvedPressure = memory?.memoryPressure ?? memoryPressure
        
        self.memory = memory ?? SystemMemoryMetrics(
            timestamp: timestamp,
            source: status.isLive ? "macmon + Darwin vm_statistics64" : "Darwin vm_statistics64",
            totalPhysicalBytes: resolvedTotalRam,
            usedBytes: resolvedUsedRam,
            appMemoryBytes: max(0, resolvedUsedRam - resolvedCompressed),
            wiredBytes: 0,
            compressedBytes: resolvedCompressed,
            uncompressedInCompressorBytes: nil,
            availableBytes: max(0, resolvedTotalRam - resolvedUsedRam),
            freeBytes: max(0, resolvedTotalRam - resolvedUsedRam),
            cachedFilesBytes: 0,
            swapUsedBytes: resolvedSwapUsed,
            swapTotalBytes: resolvedSwapTotal,
            virtualAllocatedBytes: nil,
            memoryPressure: resolvedPressure
        )
        
        self.systemPower = systemPower
        self.cpuPower = cpuPower
        self.gpuPower = gpuPower
        self.anePower = anePower
        self.ramPower = ramPower
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.fanSpeedRPM = fanSpeedRPM
        self.gpuFreqMHz = gpuFreqMHz
        self.diskVolumes = diskVolumes
        self.uptimeSeconds = uptimeSeconds
    }
    
    /// Core layout as shown in the UI: clustered on Apple Silicon, a single count on Intel.
    public var coreLayoutLabel: String {
        eCoreCount > 0 ? "\(pCoreCount)P / \(eCoreCount)E COEURS" : "\(pCoreCount) COEURS"
    }

    public var swapUsedFraction: Double {
        memory.swapUsedFraction
    }
    
    public var isSwapHigh: Bool {
        swapUsed > 2 * 1024 * 1024 * 1024 // > 2 GB swap
    }
    
    public var ramUsedFraction: Double {
        memory.usedFraction
    }

    /// Charge RAM à afficher : pression réelle du kernel, sinon occupation physique en repli.
    public var ramLoadFraction: Double {
        memory.pressureFraction ?? memory.usedFraction
    }
    
    public var uptimeFormatted: String {
        let hours = Int(uptimeSeconds) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        let days = hours / 24
        if days > 0 {
            return "\(days)d \(hours % 24)h \(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }
}

public struct NativeCpuTicks: Sendable, Equatable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32
    
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum NativeCpuCalculator {
    public static func calculateUsage(previous: NativeCpuTicks?, current: NativeCpuTicks) -> Double {
        guard let prev = previous else { return 0.0 }
        let userDiff = Int64(current.user) - Int64(prev.user)
        let sysDiff = Int64(current.system) - Int64(prev.system)
        let idleDiff = Int64(current.idle) - Int64(prev.idle)
        let niceDiff = Int64(current.nice) - Int64(prev.nice)
        
        let total = userDiff + sysDiff + idleDiff + niceDiff
        guard total > 0 else { return 0.0 }
        let active = userDiff + sysDiff + niceDiff
        let fraction = Double(max(0, active)) / Double(total)
        return min(1.0, max(0.0, fraction))
    }
}

public struct BoundedBackoff: Sendable {
    public let initialDelay: Double
    public let maxDelay: Double
    public let multiplier: Double
    private(set) public var currentDelay: Double
    
    public init(initialDelay: Double = 2.0, maxDelay: Double = 30.0, multiplier: Double = 2.0) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.currentDelay = initialDelay
    }
    
    public mutating func nextDelay() -> Double {
        let delay = currentDelay
        currentDelay = min(maxDelay, currentDelay * multiplier)
        return delay
    }
    
    public mutating func reset() {
        currentDelay = initialDelay
    }
}

@Observable
@MainActor
public final class SystemMetricsService {
    public static let shared = SystemMetricsService()
    
    public var currentSnapshot = SystemSnapshot()
    public var isRunning = false
    public var updateIntervalSeconds: Double = 1.5
    
    private var monitoringTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    /// Reads the current macmon stream; cancelling it terminates that macmon process.
    private var macmonStreamTask: Task<MacmonStreamResult, Never>?
    /// When the current macmon stream last produced a line (or was launched).
    private var lastMacmonLineAt: Date?
    private let decoder = JSONDecoder()

    /// A macmon stream silent for this long is considered hung, whatever the interval.
    public nonisolated static let macmonStallMinimumTimeout: TimeInterval = 15.0
    /// A macmon stream silent for this many sample intervals is considered hung.
    public nonisolated static let macmonStallIntervalMultiplier: Double = 8.0

    /// Whether a macmon stream that last spoke at `lastLineAt` has stalled.
    ///
    /// macmon can stop emitting without exiting (typically an IOReport stall after
    /// wake). `for await` would then wait forever and the restart/backoff loop would
    /// never run, leaving the Darwin fallback in place for the whole session.
    public nonisolated static func isMacmonStreamStalled(
        lastLineAt: Date,
        now: Date,
        updateInterval: Double
    ) -> Bool {
        let timeout = max(macmonStallMinimumTimeout, updateInterval * macmonStallIntervalMultiplier)
        return now.timeIntervalSince(lastLineAt) > timeout
    }
    
    // Darwin sampling state
    private var previousCpuTicks: NativeCpuTicks?
    
    // Cached disk volumes (30s TTL)
    private var cachedDiskVolumes: [DiskVolumeInfo] = []
    private var lastDiskVolumesScanTime: Date = .distantPast
    private let diskVolumeCacheTTL: TimeInterval = 30.0
    
    public init() {
        // Immediate instant native Darwin sample so the initial snapshot is fully populated
        let initialSnapshot = self.sampleNativeMetrics(
            statusOverride: .fallback(reason: "Darwin initial sample"),
            reason: "Initial baseline"
        )
        self.currentSnapshot = initialSnapshot
        self.updateSnapshot(initialSnapshot)
    }
    
    public nonisolated static func determineStatus(for failure: TelemetryFailureReason) -> TelemetryStatus {
        switch failure {
        case .binaryNotFound:
            return .fallback(reason: "macmon binary not found in PATH")
        case .launchFailed(let detail):
            return .error("macmon process could not start: \(detail)")
        case .streamExited(let consecutiveFailures):
            if consecutiveFailures >= 2 {
                return .error("macmon streaming failed repeatedly (\(consecutiveFailures) attempts)")
            } else {
                return .fallback(reason: "macmon streaming interrupted, retrying")
            }
        case .streamCorrupted:
            return .error("macmon output could not be decoded")
        case .serviceStopped:
            return .unavailable(reason: "Monitoring stopped")
        }
    }
    
    public nonisolated func determineStatus(for failure: TelemetryFailureReason) -> TelemetryStatus {
        Self.determineStatus(for: failure)
    }
    
    public struct MacmonStreamResult: Sendable, Equatable {
        public let sampleCount: Int
        public let corruptedLines: Int
        public let launchFailed: Bool
        
        public var didStreamSuccessfully: Bool {
            sampleCount > 0
        }
        
        public init(sampleCount: Int, corruptedLines: Int, launchFailed: Bool) {
            self.sampleCount = sampleCount
            self.corruptedLines = corruptedLines
            self.launchFailed = launchFailed
        }
    }
    
    public func startMonitoring() {
        guard !isRunning || monitoringTask == nil else { return }
        isRunning = true
        TelemetryLogger.lifecycle.info("SystemMetricsService monitoring started")
        
        // Immediate synchronous native sample on start
        let immediateSample = self.sampleNativeMetrics(
            statusOverride: .fallback(reason: "Connecting to hardware telemetry..."),
            reason: "Monitoring started"
        )
        self.updateSnapshot(immediateSample)
        
        // Passive Watchdog Task (only fires if macmon stream stalls for > 4 seconds)
        heartbeatTask?.cancel()
        heartbeatTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                guard let self = self else { break }
                
                await MainActor.run {
                    self.restartMacmonIfStalled()
                    // If the current snapshot is older than 3.5 seconds, macmon is not actively feeding
                    if abs(self.currentSnapshot.timestamp.timeIntervalSinceNow) > 3.5 {
                        let fallback = self.sampleNativeMetrics(
                            statusOverride: .fallback(reason: "Darwin background monitor"),
                            reason: "macmon stream pending"
                        )
                        self.updateSnapshot(fallback)
                    }
                }
            }
        }
        
        // Start Streaming / Polling Task
        monitoringTask?.cancel()
        monitoringTask = Task.detached(priority: .userInitiated) { [weak self] in
            var backoff = BoundedBackoff(initialDelay: 2.0, maxDelay: 30.0, multiplier: 2.0)
            var consecutiveFailures = 0
            
            while !Task.isCancelled {
                guard let self = self else { break }
                let macmonPath = ToolRegistry.shared.resolveBinaryPath(name: "macmon")
                
                if let path = macmonPath {
                    guard FileManager.default.isExecutableFile(atPath: path) else {
                        consecutiveFailures += 1
                        let failureStatus = Self.determineStatus(for: .launchFailed("binary not executable"))
                        let snapshot = await self.sampleNativeMetrics(
                            statusOverride: failureStatus,
                            reason: "macmon binary not executable"
                        )
                        await self.updateSnapshot(snapshot)
                        
                        let delay = backoff.nextDelay()
                        let interval = await self.updateIntervalSeconds
                        var elapsed: Double = 0
                        while elapsed < delay && !Task.isCancelled {
                            let sleepNs = UInt64(interval * 1_000_000_000)
                            try? await Task.sleep(nanoseconds: sleepNs)
                            elapsed += interval
                        }
                        continue
                    }
                    
                    TelemetryLogger.telemetry.info("Attempting to connect to macmon stream at \(path, privacy: .public)")
                    let streamResult = await self.streamFromMacmon(path: path)
                    
                    if Task.isCancelled { break }
                    
                    if streamResult.didStreamSuccessfully {
                        backoff.reset()
                        consecutiveFailures = 0
                    } else {
                        consecutiveFailures += 1
                        let delay = backoff.nextDelay()
                        let failureReason: TelemetryFailureReason
                        if streamResult.launchFailed {
                            failureReason = .launchFailed("process failed to launch")
                        } else if streamResult.corruptedLines > 0 && streamResult.sampleCount == 0 {
                            failureReason = .streamCorrupted
                        } else {
                            failureReason = .streamExited(consecutiveFailures: consecutiveFailures)
                        }
                        
                        let failureStatus = Self.determineStatus(for: failureReason)
                        TelemetryLogger.telemetry.warning("macmon streaming failed (attempt \(consecutiveFailures)). Status: \(failureStatus.statusLabel). Backing off for \(delay)s.")
                        
                        // Sample native fallback metrics during backoff interval
                        let interval = await self.updateIntervalSeconds
                        var elapsed: Double = 0
                        while elapsed < delay && !Task.isCancelled {
                            let snapshot = await self.sampleNativeMetrics(
                                statusOverride: failureStatus,
                                reason: "macmon retry in \(Int(delay - elapsed))s"
                            )
                            await self.updateSnapshot(snapshot)
                            let sleepNs = UInt64(interval * 1_000_000_000)
                            try? await Task.sleep(nanoseconds: sleepNs)
                            elapsed += interval
                        }
                    }
                } else {
                    consecutiveFailures = 0
                    let status = Self.determineStatus(for: .binaryNotFound)
                    let snapshot = await self.sampleNativeMetrics(
                        statusOverride: status,
                        reason: "macmon binary not found in PATH"
                    )
                    await self.updateSnapshot(snapshot)
                    let interval = await self.updateIntervalSeconds
                    let nanoseconds = UInt64(interval * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
            }
        }
    }
    
    /// Cancels a hung macmon stream so the monitoring loop relaunches it.
    private func restartMacmonIfStalled() {
        guard let streamTask = macmonStreamTask,
              let lastLineAt = lastMacmonLineAt,
              Self.isMacmonStreamStalled(lastLineAt: lastLineAt, now: Date(), updateInterval: updateIntervalSeconds)
        else { return }
        TelemetryLogger.telemetry.warning("macmon stream silent for \(Int(Date().timeIntervalSince(lastLineAt)))s; restarting it")
        lastMacmonLineAt = nil
        streamTask.cancel()
    }

    public func stopMonitoring() {
        macmonStreamTask?.cancel()
        macmonStreamTask = nil
        lastMacmonLineAt = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        isRunning = false
        TelemetryLogger.lifecycle.info("SystemMetricsService monitoring stopped")
        
        // Preserve last known values while reflecting paused status
        currentSnapshot = SystemSnapshot(
            timestamp: Date(),
            status: .unavailable(reason: "Monitoring stopped"),
            isMacmonActive: false,
            cpuUsage: currentSnapshot.cpuUsage,
            gpuUsage: currentSnapshot.gpuUsage,
            eCpuUsage: currentSnapshot.eCpuUsage,
            pCpuUsage: currentSnapshot.pCpuUsage,
            eCoreCount: currentSnapshot.eCoreCount,
            pCoreCount: currentSnapshot.pCoreCount,
            memory: currentSnapshot.memory,
            systemPower: currentSnapshot.systemPower,
            cpuPower: currentSnapshot.cpuPower,
            gpuPower: currentSnapshot.gpuPower,
            anePower: currentSnapshot.anePower,
            ramPower: currentSnapshot.ramPower,
            cpuTemp: currentSnapshot.cpuTemp,
            gpuTemp: currentSnapshot.gpuTemp,
            fanSpeedRPM: currentSnapshot.fanSpeedRPM,
            gpuFreqMHz: currentSnapshot.gpuFreqMHz,
            diskVolumes: currentSnapshot.diskVolumes,
            uptimeSeconds: currentSnapshot.uptimeSeconds
        )
    }
    
    /// Streams lines from macmon and updates snapshots. Returns stream result metrics.
    private func streamFromMacmon(path: String) async -> MacmonStreamResult {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return MacmonStreamResult(sampleCount: 0, corruptedLines: 0, launchFailed: true)
        }
        
        let intervalMs = Int(updateIntervalSeconds * 1000)
        let stream = ProcessRunner.shared.streamLines(
            executableURL: URL(fileURLWithPath: path),
            arguments: ["pipe", "-i", "\(intervalMs)"]
        )

        // Read in a child task the heartbeat can cancel when macmon hangs; cancelling
        // the monitoring loop cancels it too.
        let streamTask = Task { @MainActor [weak self] () -> MacmonStreamResult in
            guard let self else {
                return MacmonStreamResult(sampleCount: 0, corruptedLines: 0, launchFailed: false)
            }
            return await self.consumeMacmonLines(stream)
        }
        macmonStreamTask = streamTask
        lastMacmonLineAt = Date()
        let result = await withTaskCancellationHandler {
            await streamTask.value
        } onCancel: {
            streamTask.cancel()
        }
        if macmonStreamTask == streamTask {
            macmonStreamTask = nil
            lastMacmonLineAt = nil
        }
        return result
    }

    private func consumeMacmonLines(_ stream: AsyncStream<String>) async -> MacmonStreamResult {
        var sampleCount = 0
        var corruptedCount = 0

        for await line in stream {
            if Task.isCancelled { break }
            lastMacmonLineAt = Date()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else {
                corruptedCount += 1
                continue
            }
            
            if let sample = try? self.decoder.decode(MacmonSample.self, from: data) {
                sampleCount += 1
                let snapshot = self.createSnapshot(from: sample)
                self.updateSnapshot(snapshot)
            } else {
                corruptedCount += 1
                TelemetryLogger.telemetry.debug("Skipped non-decodable macmon line: \(trimmed.prefix(60), privacy: .public)")
            }
        }
        
        return MacmonStreamResult(
            sampleCount: sampleCount,
            corruptedLines: corruptedCount,
            launchFailed: false
        )
    }
    
    public func sampleNativeMetrics(
        statusOverride: TelemetryStatus? = nil,
        reason: String = "macmon inactive"
    ) -> SystemSnapshot {
        let diskVolumes = getDiskVolumes()
        let uptime = ProcessInfo.processInfo.systemUptime
        let hostPort = mach_host_self()
        
        // 1. RAM & Swap via SystemMemoryCalculator (Darwin host_statistics64 + sysctl)
        let memoryMetrics = SystemMemoryCalculator.sampleCurrent(
            pressure: MemoryPressureMonitor.shared.currentState
        )
        
        // 2. CPU Load via host_cpu_load_info
        var cpuLoad = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuRes = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        
        var cpuUsage = 0.0
        if cpuRes == KERN_SUCCESS {
            let currentTicks = NativeCpuTicks(
                user: cpuLoad.cpu_ticks.0,
                system: cpuLoad.cpu_ticks.1,
                idle: cpuLoad.cpu_ticks.2,
                nice: cpuLoad.cpu_ticks.3
            )
            if let prev = previousCpuTicks {
                cpuUsage = NativeCpuCalculator.calculateUsage(previous: prev, current: currentTicks)
            } else {
                // First sample baseline fallback
                cpuUsage = 0.12 // 12% realistic nominal baseline for responsive initial rendering
            }
            previousCpuTicks = currentTicks
        }
        
        // 3. Core Counts — heterogeneous on Apple Silicon, single cluster on Intel.
        let topology = CPUTopology.current()
        let pCount = topology.performanceCores
        let eCount = topology.efficiencyCores
        
        // 4. Native GPU Sampling via IOKit IOAccelerator
        let nativeGpu = NativeGpuSampler.sampleGpuUsage() ?? 0.0
        
        let resolvedStatus = statusOverride ?? .fallback(reason: reason)
        
        return SystemSnapshot(
            timestamp: Date(),
            status: resolvedStatus,
            isMacmonActive: false,
            cpuUsage: cpuUsage,
            gpuUsage: nativeGpu,
            eCpuUsage: cpuUsage,
            pCpuUsage: cpuUsage,
            eCoreCount: eCount,
            pCoreCount: pCount,
            memory: memoryMetrics,
            systemPower: 0.0,
            cpuPower: 0.0,
            gpuPower: 0.0,
            anePower: 0.0,
            ramPower: 0.0,
            cpuTemp: nil,
            gpuTemp: nil,
            fanSpeedRPM: nil,
            gpuFreqMHz: nil,
            diskVolumes: diskVolumes,
            uptimeSeconds: uptime
        )
    }
    
    /// Construit un snapshot système à partir du flux temps réel macmon.
    ///
    /// Note sémantique sur macmon :
    /// macmon fournit des métriques matérielles étendues (puissance, fréquences GPU/CPU, thermiques, ventilateurs).
    /// Pour la mémoire, macmon fournit un champ synthétique `ram_usage`. Afin de respecter rigoureusement
    /// les règles produit et les catégories du Moniteur d'activité Apple (App, Résidente, Compressée,
    /// Cache/Inactive, Disponible), Morax Garage associe l'échantillonnage canonique `SystemMemoryCalculator`
    /// à la télémétrie matérielle de macmon.
    public func createSnapshot(from sample: MacmonSample) -> SystemSnapshot {
        let diskVolumes = getDiskVolumes()
        let uptime = ProcessInfo.processInfo.systemUptime
        
        let cpuUsage = sample.cpu_usage_pct ?? 0.0 // fraction 0.0...1.0
        let eCoreUsage = sample.ecpu_cores?.compactMap { $0.active_ratio }.reduce(0.0, +) ?? 0.0
        let eCount = sample.ecpu_cores?.count ?? 0
        let avgECpu = eCount > 0 ? (eCoreUsage / Double(eCount)) : 0.0
        
        let pCoreUsage = sample.pcpu_cores?.compactMap { $0.active_ratio }.reduce(0.0, +) ?? 0.0
        let pCount = sample.pcpu_cores?.count ?? 0
        let avgPCpu = pCount > 0 ? (pCoreUsage / Double(pCount)) : 0.0
        
        let fanRpm = sample.fans?.compactMap { $0.rpm }.max()
        let resolvedGpuUsage = sample.resolvedGpuUsageRatio ?? 0.0
        
        // Canonical memory breakdown via SystemMemoryCalculator & sample
        let canonicalMemory: SystemMemoryMetrics = {
            let live = SystemMemoryCalculator.sampleCurrent(
                pressure: MemoryPressureMonitor.shared.currentState
            )
            
            if let mem = sample.memory, mem.ram_total > 0 {
                return SystemMemoryMetrics(
                    timestamp: Date(),
                    source: "macmon live",
                    totalPhysicalBytes: mem.ram_total,
                    usedBytes: mem.ram_usage > 0 ? mem.ram_usage : live.usedBytes,
                    appMemoryBytes: live.appMemoryBytes > 0 ? live.appMemoryBytes : max(0, mem.ram_usage - (currentSnapshot.compressedMemory ?? 0)),
                    wiredBytes: live.wiredBytes,
                    compressedBytes: live.compressedBytes > 0 ? live.compressedBytes : (currentSnapshot.compressedMemory ?? 0),
                    uncompressedInCompressorBytes: live.uncompressedInCompressorBytes,
                    availableBytes: live.availableBytes > 0 ? live.availableBytes : max(0, mem.ram_total - mem.ram_usage),
                    freeBytes: live.freeBytes > 0 ? live.freeBytes : max(0, mem.ram_total - mem.ram_usage),
                    cachedFilesBytes: live.cachedFilesBytes,
                    swapUsedBytes: mem.swap_usage,
                    swapTotalBytes: mem.swap_total,
                    virtualAllocatedBytes: nil,
                    memoryPressure: MemoryPressureMonitor.shared.currentState,
                    pressureFraction: live.pressureFraction
                )
            }
            
            if !live.isUnknown {
                return live
            }
            
            return SystemMemoryMetrics.unknown(reason: "macmon memory and Darwin sampling unavailable")
        }()
        
        return SystemSnapshot(
            timestamp: Date(),
            status: .live(source: "macmon"),
            isMacmonActive: true,
            cpuUsage: min(1.0, max(0.0, cpuUsage)),
            gpuUsage: min(1.0, max(0.0, resolvedGpuUsage)),
            eCpuUsage: avgECpu,
            pCpuUsage: avgPCpu,
            eCoreCount: eCount,
            pCoreCount: pCount,
            memory: canonicalMemory,
            systemPower: sample.sys_power ?? sample.all_power ?? 0.0,
            cpuPower: sample.cpu_power ?? 0.0,
            gpuPower: sample.gpu_power ?? 0.0,
            anePower: sample.ane_power ?? 0.0,
            ramPower: sample.ram_power ?? 0.0,
            cpuTemp: sample.temp?.cpu_temp_avg,
            gpuTemp: sample.temp?.gpu_temp_avg,
            fanSpeedRPM: fanRpm,
            gpuFreqMHz: sample.gpu_freq_mhz,
            diskVolumes: diskVolumes,
            uptimeSeconds: uptime
        )
    }
    
    @MainActor
    public func updateSnapshot(_ snapshot: SystemSnapshot) {
        self.currentSnapshot = snapshot
        DiagnosticService.shared.ingest(snapshot)
    }
    
    public func getDiskVolumes(force: Bool = false) -> [DiskVolumeInfo] {
        let now = Date()
        if !force && !cachedDiskVolumes.isEmpty && now.timeIntervalSince(lastDiskVolumesScanTime) < diskVolumeCacheTTL {
            return cachedDiskVolumes
        }
        
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRemovableKey
        ]
        
        guard let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return cachedDiskVolumes
        }
        
        var volumes: [DiskVolumeInfo] = []
        for url in mounted {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            let isRemovable = values.volumeIsRemovable ?? false
            
            if total > 0 {
                volumes.append(DiskVolumeInfo(
                    name: name,
                    path: url.path,
                    totalBytes: total,
                    freeBytes: free,
                    isRemovable: isRemovable
                ))
            }
        }
        
        self.cachedDiskVolumes = volumes
        self.lastDiskVolumesScanTime = now
        return volumes
    }
}
