import Foundation
import IOKit
import Darwin

/// Représente un échantillon brut extrait directement du sous-système matériel GPU IOKit.
public struct RawGpuProcessEntry: Sendable, Equatable {
    public let pid: pid_t
    public let name: String
    public let accumulatedGpuTimeNs: UInt64
    public let lastSubmittedTime: UInt64
    
    public init(
        pid: pid_t,
        name: String,
        accumulatedGpuTimeNs: UInt64,
        lastSubmittedTime: UInt64 = 0
    ) {
        self.pid = pid
        self.name = name
        self.accumulatedGpuTimeNs = accumulatedGpuTimeNs
        self.lastSubmittedTime = lastSubmittedTime
    }
}

/// Échantillonneur matériel pour la collecte d'activité GPU par processus via `IOAccelerator` et `IOUserClient`.
public enum GpuProcessSampler {
    
    /// Collecte les données brutes d'utilisation GPU pour tous les clients actifs dans l'IORegistry.
    public static func collectRawEntries() -> [RawGpuProcessEntry] {
        var rawEntries: [pid_t: (name: String, accumulatedGpuTimeNs: UInt64, lastSubmittedTime: UInt64)] = [:]
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            var childIterator: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == kIOReturnSuccess, childIterator != 0 else {
                continue
            }
            defer { IOObjectRelease(childIterator) }
            
            var child = IOIteratorNext(childIterator)
            while child != 0 {
                defer {
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }
                
                var propsCF: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(child, &propsCF, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                      let props = propsCF?.takeRetainedValue() as? [String: Any] else {
                    continue
                }
                
                guard let creator = props["IOUserClientCreator"] as? String else { continue }
                // Creator format is typically "pid <PID>, <Name>" or "pid <PID>"
                let creatorComponents = creator.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let pidPart = creatorComponents.first, pidPart.starts(with: "pid ") else { continue }
                let pidStr = pidPart.dropFirst(4).trimmingCharacters(in: .whitespaces)
                guard let pid = pid_t(pidStr) else { continue }
                let parsedName = creatorComponents.count > 1 ? creatorComponents[1] : ""
                
                var totalGpuTime: UInt64 = 0
                var maxLastSubmitted: UInt64 = 0
                
                if let appUsage = props["AppUsage"] as? [[String: Any]] {
                    for entry in appUsage {
                        if let gpuTime = entry["accumulatedGPUTime"] as? NSNumber {
                            totalGpuTime += gpuTime.uint64Value
                        }
                        if let lastSub = entry["lastSubmittedTime"] as? NSNumber {
                            maxLastSubmitted = max(maxLastSubmitted, lastSub.uint64Value)
                        }
                    }
                }
                
                if var existing = rawEntries[pid] {
                    existing.accumulatedGpuTimeNs += totalGpuTime
                    existing.lastSubmittedTime = max(existing.lastSubmittedTime, maxLastSubmitted)
                    if existing.name.isEmpty && !parsedName.isEmpty {
                        existing.name = parsedName
                    }
                    rawEntries[pid] = existing
                } else {
                    rawEntries[pid] = (name: parsedName, accumulatedGpuTimeNs: totalGpuTime, lastSubmittedTime: maxLastSubmitted)
                }
            }
        }
        
        return rawEntries.map {
            RawGpuProcessEntry(
                pid: $0.key,
                name: $0.value.name,
                accumulatedGpuTimeNs: $0.value.accumulatedGpuTimeNs,
                lastSubmittedTime: $0.value.lastSubmittedTime
            )
        }
    }
}

/// Traqueur d'état temporel pour le calcul différentiel de la charge GPU par processus et agrégation par application.
public actor GpuProcessStateTracker {
    private var previousSamples: [pid_t: (accumulatedGpuTimeNs: UInt64, timestamp: Date)] = [:]
    private var lastSampleDate: Date?
    /// Resolves a PID to its executable path. Injected so tests never read the host's real processes.
    private let pathForPID: @Sendable (pid_t) -> String?

    public init(pathForPID: @escaping @Sendable (pid_t) -> String? = GpuProcessStateTracker.executablePath) {
        self.pathForPID = pathForPID
    }

    public static func executablePath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else { return nil }
        return pathBuffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) }
        }
    }
    
    /// Discards the sampling history and records `rawEntries` as the reference for
    /// the next `sample`, so that sample already reports real GPU deltas. Reset and
    /// baseline happen in one actor call, so no other sample can land in between.
    public func rebaseline(rawEntries: [RawGpuProcessEntry], now: Date = Date()) {
        previousSamples = Dictionary(
            rawEntries.map { ($0.pid, (accumulatedGpuTimeNs: $0.accumulatedGpuTimeNs, timestamp: now)) },
            uniquingKeysWith: { _, latest in latest }
        )
        lastSampleDate = rawEntries.isEmpty ? nil : now
    }
    
    /// Calcule le snapshot différentiel des applications consommatrices de GPU à partir d'échantillons bruts.
    public func sample(
        rawEntries: [RawGpuProcessEntry],
        runningApps: [pid_t: (name: String, bundleURL: URL?)] = [:],
        limit: Int = 5,
        now: Date = Date()
    ) -> (topGpu: [ProcessResourceUsage], status: TopApplicationsStatus) {
        guard !rawEntries.isEmpty else {
            return ([], .unavailable)
        }
        
        let elapsedSec: Double
        if let lastDate = lastSampleDate {
            elapsedSec = max(0.01, now.timeIntervalSince(lastDate))
        } else {
            elapsedSec = 0.0
        }
        let elapsedNs = UInt64(elapsedSec * 1_000_000_000.0)
        
        struct AggregatedGpuApp {
            var name: String
            var bundlePath: String?
            var gpuPercent: Double
            var deltaGpuTimeNs: UInt64
            var accumulatedGpuTimeNs: UInt64
            var processCount: Int
            var mainPid: Int32
        }
        
        var currentPids = Set<pid_t>()
        var aggMap: [String: AggregatedGpuApp] = [:]
        
        for entry in rawEntries {
            currentPids.insert(entry.pid)
            let prev = previousSamples[entry.pid]
            let deltaNs: UInt64
            let gpuPct: Double
            
            if let prev = prev, elapsedNs > 0 {
                if entry.accumulatedGpuTimeNs >= prev.accumulatedGpuTimeNs {
                    deltaNs = entry.accumulatedGpuTimeNs - prev.accumulatedGpuTimeNs
                } else {
                    // Processus redémarré ou compteur réinitialisé
                    deltaNs = entry.accumulatedGpuTimeNs
                }
                gpuPct = min(100.0, max(0.0, (Double(deltaNs) / Double(elapsedNs)) * 100.0))
            } else {
                deltaNs = 0
                gpuPct = 0.0
            }
            
            let bundleURL: URL?
            let appName: String
            let bundlePathStr: String?
            let key: String
            
            if let runningApp = runningApps[entry.pid] {
                bundleURL = runningApp.bundleURL
                bundlePathStr = bundleURL?.path
                appName = runningApp.name
                key = bundlePathStr?.lowercased() ?? appName.lowercased()
            } else {
                let fullPath = pathForPID(entry.pid) ?? ""
                let extractedBundle = fullPath.isEmpty ? nil : ProcessResourceSampler.extractAppBundleURL(from: fullPath)
                
                if let extracted = extractedBundle {
                    bundleURL = extracted
                    bundlePathStr = extracted.path
                    appName = ProcessResourceSampler.resolveAppName(for: extracted)
                    key = extracted.path.lowercased()
                } else if !fullPath.isEmpty {
                    let lastComponent = URL(fileURLWithPath: fullPath).lastPathComponent
                    bundleURL = nil
                    bundlePathStr = nil
                    appName = lastComponent
                    key = lastComponent.lowercased()
                } else if !entry.name.isEmpty {
                    bundleURL = nil
                    bundlePathStr = nil
                    appName = entry.name
                    key = entry.name.lowercased()
                } else {
                    bundleURL = nil
                    bundlePathStr = nil
                    appName = "PID \(entry.pid)"
                    key = "pid_\(entry.pid)"
                }
            }
            
            if var existing = aggMap[key] {
                existing.gpuPercent += gpuPct
                existing.deltaGpuTimeNs += deltaNs
                existing.accumulatedGpuTimeNs += entry.accumulatedGpuTimeNs
                existing.processCount += 1
                if gpuPct > 0 && existing.mainPid == 0 {
                    existing.mainPid = entry.pid
                }
                aggMap[key] = existing
            } else {
                aggMap[key] = AggregatedGpuApp(
                    name: appName,
                    bundlePath: bundlePathStr,
                    gpuPercent: gpuPct,
                    deltaGpuTimeNs: deltaNs,
                    accumulatedGpuTimeNs: entry.accumulatedGpuTimeNs,
                    processCount: 1,
                    mainPid: entry.pid
                )
            }
            
            previousSamples[entry.pid] = (entry.accumulatedGpuTimeNs, now)
        }
        
        // Élagage des PIDs fermés ou disparus
        previousSamples = previousSamples.filter { currentPids.contains($0.key) }
        lastSampleDate = now
        
        let allUsages = aggMap.values.map {
            ProcessResourceUsage(
                name: $0.name,
                bundlePath: $0.bundlePath,
                cpuPercent: 0.0,
                ramBytes: 0,
                gpuPercent: $0.gpuPercent,
                gpuTimeNs: $0.accumulatedGpuTimeNs,
                processCount: $0.processCount,
                mainPid: $0.mainPid
            )
        }
        
        // Priorité aux processus avec charge active (> 0.05%), puis par temps GPU total
        let activeOrTotal = allUsages.filter { $0.gpuPercent > 0.05 || $0.gpuTimeNs > 0 }
        let sorted = activeOrTotal.sorted {
            if abs($0.gpuPercent - $1.gpuPercent) > 0.05 {
                return $0.gpuPercent > $1.gpuPercent
            }
            return $0.gpuTimeNs > $1.gpuTimeNs
        }
        
        let topGpu = Array(sorted.prefix(limit))
        return (topGpu, .active)
    }
}
