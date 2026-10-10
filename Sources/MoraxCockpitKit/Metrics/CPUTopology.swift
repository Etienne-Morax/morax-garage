import Foundation

/// Physical core layout of the host CPU.
///
/// Apple Silicon splits its cores into performance and efficiency clusters, exposed through the
/// `hw.perflevel0.physicalcpu` / `hw.perflevel1.physicalcpu` sysctl keys. Intel Macs have no such
/// split and those keys do not exist, so the topology must degrade to a single homogeneous count
/// instead of reporting every core as a performance core.
public struct CPUTopology: Sendable, Equatable {
    public let performanceCores: Int
    public let efficiencyCores: Int

    public init(performanceCores: Int, efficiencyCores: Int) {
        self.performanceCores = max(0, performanceCores)
        self.efficiencyCores = max(0, efficiencyCores)
    }

    /// True when the CPU exposes distinct performance and efficiency clusters.
    public var isHeterogeneous: Bool { efficiencyCores > 0 }

    /// Total physical cores across every cluster.
    public var totalCores: Int { performanceCores + efficiencyCores }

    /// Resolves the topology from raw sysctl readings.
    ///
    /// - Parameters:
    ///   - perfLevel0Cores: `hw.perflevel0.physicalcpu`, `nil` when the key is unavailable (Intel).
    ///   - perfLevel1Cores: `hw.perflevel1.physicalcpu`, `nil` when the key is unavailable (Intel).
    ///   - physicalCores: `hw.physicalcpu`, `nil` when unreadable.
    ///   - logicalCores: last-resort count, always available through `ProcessInfo`.
    public static func resolve(
        perfLevel0Cores: Int?,
        perfLevel1Cores: Int?,
        physicalCores: Int?,
        logicalCores: Int
    ) -> CPUTopology {
        if let performance = perfLevel0Cores, performance > 0 {
            return CPUTopology(
                performanceCores: performance,
                efficiencyCores: perfLevel1Cores ?? 0
            )
        }

        // Intel: no cluster split. Prefer physical cores over the logical count so that
        // hyper-threading does not double the reported core budget.
        let homogeneous = (physicalCores.map { $0 > 0 ? $0 : nil } ?? nil) ?? logicalCores
        return CPUTopology(performanceCores: homogeneous, efficiencyCores: 0)
    }

    /// Reads the topology from the running system.
    public static func current() -> CPUTopology {
        resolve(
            perfLevel0Cores: sysctlInt("hw.perflevel0.physicalcpu"),
            perfLevel1Cores: sysctlInt("hw.perflevel1.physicalcpu"),
            physicalCores: sysctlInt("hw.physicalcpu"),
            logicalCores: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
