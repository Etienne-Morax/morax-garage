import Foundation
import SystemConfiguration
import Darwin
import Observation

public enum TopApplicationsStatus: Sendable, Equatable {
    case active
    case unavailable
    case noData
}

public struct NetworkApplicationUsage: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    
    public var totalBytesPerSecond: Double {
        downloadBytesPerSecond + uploadBytesPerSecond
    }
    
    public init(
        name: String,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.name = name
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public struct NetworkSnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let interfaceName: String?
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let topApplications: [NetworkApplicationUsage]
    public let topApplicationsStatus: TopApplicationsStatus
    
    public init(
        timestamp: Date = Date(),
        interfaceName: String? = nil,
        downloadBytesPerSecond: Double = 0,
        uploadBytesPerSecond: Double = 0,
        topApplications: [NetworkApplicationUsage] = [],
        topApplicationsStatus: TopApplicationsStatus = .noData
    ) {
        self.timestamp = timestamp
        self.interfaceName = interfaceName
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.topApplications = topApplications
        self.topApplicationsStatus = topApplicationsStatus
    }
    
    public static func unavailableTopApplications(
        timestamp: Date = Date(),
        interfaceName: String?,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) -> NetworkSnapshot {
        NetworkSnapshot(
            timestamp: timestamp,
            interfaceName: interfaceName,
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond,
            topApplications: [],
            topApplicationsStatus: .unavailable
        )
    }
}

public enum NetworkRateCalculator {
    public static func rate(previous: UInt64?, current: UInt64, elapsed: TimeInterval) -> Double {
        guard let previous, current >= previous, elapsed > 0 else { return 0 }
        return Double(current - previous) / elapsed
    }
}

public struct InterfaceByteCounters: Sendable, Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    
    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public protocol NetworkInterfaceReader: Sendable {
    func primaryInterfaceName() -> String?
    func interfaceCounters(for interfaceName: String) -> InterfaceByteCounters?
}

public struct SystemNetworkInterfaceReader: NetworkInterfaceReader {
    public init() {}
    
    public func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MoraxGarageNetworkReader" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primary = dict["PrimaryInterface"] as? String,
              !primary.isEmpty else {
            return nil
        }
        return primary
    }
    
    public func interfaceCounters(for interfaceName: String) -> InterfaceByteCounters? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let nameCString = ptr.pointee.ifa_name else { continue }
            let name = String(cString: nameCString)
            guard name == interfaceName else { continue }
            
            if let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    return InterfaceByteCounters(
                        bytesIn: UInt64(ifData.ifi_ibytes),
                        bytesOut: UInt64(ifData.ifi_obytes)
                    )
                }
            }
        }
        return nil
    }
}

@Observable
@MainActor
public final class NetworkMetricsService {
    public static let shared = NetworkMetricsService()
    
    public var currentSnapshot = NetworkSnapshot()
    public var updateIntervalSeconds: Double = 3.5
    public var isRunning = false
    
    private var monitoringTask: Task<Void, Never>?
    private let interfaceReader: NetworkInterfaceReader
    private let nettopPath: String
    
    public init(
        interfaceReader: NetworkInterfaceReader = SystemNetworkInterfaceReader(),
        nettopPath: String = "/usr/bin/nettop"
    ) {
        self.interfaceReader = interfaceReader
        self.nettopPath = nettopPath
    }
    
    public func startMonitoring() {
        guard monitoringTask == nil else { return }
        isRunning = true
        
        let reader = interfaceReader
        let nettopBinary = nettopPath
        
        monitoringTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                if FileManager.default.isExecutableFile(atPath: nettopBinary) {
                    await self?.pollNettop(binaryPath: nettopBinary, reader: reader)
                }
                
                if Task.isCancelled { break }
                
                // Fallback to native interface polling if nettop is unavailable or exited
                await self?.pollNativeInterface(reader: reader)
            }
        }
    }
    
    public func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isRunning = false
    }
    
    /// Samples nettop off the main actor, hopping back only to publish a snapshot.
    private nonisolated func pollNettop(
        binaryPath: String,
        reader: NetworkInterfaceReader
    ) async {
        var lastIterationTotals: [String: NettopProcessSample]?
        var lastIterationTime: Date?
        
        var lastInterfaceCounters: InterfaceByteCounters?
        var lastInterfaceName: String?
        var lastInterfaceTime: Date?
        
        while !Task.isCancelled {
            let now = Date()
            
            // 1. One-shot nettop sample (12ms execution, 0% CPU idle)
            var topApps: [NetworkApplicationUsage] = []
            var status: TopApplicationsStatus = .noData
            
            let output = Self.executeNettopOneShot(binaryPath: binaryPath)
            if !output.isEmpty {
                let lines = output.components(separatedBy: .newlines)
                let (_, samples) = NettopCSVParser().parseBatch(lines: lines)
                
                if !samples.isEmpty {
                    let currentTotals = NettopApplicationAggregator.aggregateByApplication(samples: samples)
                    
                    if let previousTotals = lastIterationTotals, let previousTime = lastIterationTime {
                        let elapsed = now.timeIntervalSince(previousTime)
                        topApps = NettopApplicationAggregator.calculateRates(
                            previousTotals: previousTotals,
                            currentTotals: currentTotals,
                            elapsed: elapsed,
                            limit: 3
                        )
                        status = .active
                    } else {
                        status = .noData
                    }
                    
                    lastIterationTotals = currentTotals
                    lastIterationTime = now
                }
            } else {
                status = .unavailable
            }
            
            // 2. Sample global interface counters
            let ifName = reader.primaryInterfaceName()
            var downloadRate: Double = 0
            var uploadRate: Double = 0
            
            if let ifName = ifName, let counters = reader.interfaceCounters(for: ifName) {
                if ifName == lastInterfaceName, let prev = lastInterfaceCounters, let prevTime = lastInterfaceTime {
                    let elapsed = now.timeIntervalSince(prevTime)
                    downloadRate = NetworkRateCalculator.rate(previous: prev.bytesIn, current: counters.bytesIn, elapsed: elapsed)
                    uploadRate = NetworkRateCalculator.rate(previous: prev.bytesOut, current: counters.bytesOut, elapsed: elapsed)
                }
                lastInterfaceCounters = counters
                lastInterfaceName = ifName
                lastInterfaceTime = now
            } else {
                lastInterfaceCounters = nil
                lastInterfaceName = nil
                lastInterfaceTime = nil
            }
            
            let snapshot = NetworkSnapshot(
                timestamp: now,
                interfaceName: ifName,
                downloadBytesPerSecond: downloadRate,
                uploadBytesPerSecond: uploadRate,
                topApplications: topApps,
                topApplicationsStatus: status
            )
            
            await self.updateSnapshot(snapshot)
            
            // Re-read the interval every tick so a change in settings applies
            // without restarting monitoring.
            let interval = await self.updateIntervalSeconds
            let nanoseconds = UInt64(max(1.0, interval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }
    
    public nonisolated static func executeNettopOneShot(binaryPath: String) -> String {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["-P", "-c", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    /// Samples the interface counters off the main actor, hopping back only to publish.
    private nonisolated func pollNativeInterface(
        reader: NetworkInterfaceReader
    ) async {
        var lastCounters: InterfaceByteCounters?
        var lastInterface: String?
        var lastTime: Date?
        
        while !Task.isCancelled {
            let now = Date()
            let ifName = reader.primaryInterfaceName()
            
            var downloadRate: Double = 0
            var uploadRate: Double = 0
            
            if let ifName = ifName, let counters = reader.interfaceCounters(for: ifName) {
                if ifName == lastInterface, let prev = lastCounters, let prevTime = lastTime {
                    let elapsed = now.timeIntervalSince(prevTime)
                    downloadRate = NetworkRateCalculator.rate(previous: prev.bytesIn, current: counters.bytesIn, elapsed: elapsed)
                    uploadRate = NetworkRateCalculator.rate(previous: prev.bytesOut, current: counters.bytesOut, elapsed: elapsed)
                }
                lastCounters = counters
                lastInterface = ifName
                lastTime = now
            } else {
                lastCounters = nil
                lastInterface = nil
                lastTime = nil
            }
            
            let snapshot = NetworkSnapshot.unavailableTopApplications(
                timestamp: now,
                interfaceName: ifName,
                downloadBytesPerSecond: downloadRate,
                uploadBytesPerSecond: uploadRate
            )
            
            await self.updateSnapshot(snapshot)
            
            // Re-read the interval every tick so a change in settings applies
            // without restarting monitoring.
            let interval = await self.updateIntervalSeconds
            let nanoseconds = UInt64(max(0.5, interval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }
    
    @MainActor
    public func updateSnapshot(_ snapshot: NetworkSnapshot) {
        self.currentSnapshot = snapshot
    }
}
