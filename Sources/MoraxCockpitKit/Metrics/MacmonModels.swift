import Foundation

public struct MacmonCoreMetric: Codable, Sendable {
    public let active_ratio: Double?
    public let core_id: Int?
    public let die_id: Int?
    public let freq_mhz: Double?
    public let scaled_ratio: Double?
    
    public init(active_ratio: Double? = nil, core_id: Int? = nil, die_id: Int? = nil, freq_mhz: Double? = nil, scaled_ratio: Double? = nil) {
        self.active_ratio = active_ratio
        self.core_id = core_id
        self.die_id = die_id
        self.freq_mhz = freq_mhz
        self.scaled_ratio = scaled_ratio
    }
}

public struct MacmonMemory: Codable, Sendable {
    public let ram_total: Int64
    public let ram_usage: Int64
    public let swap_total: Int64
    public let swap_usage: Int64
    
    public init(ram_total: Int64 = 0, ram_usage: Int64 = 0, swap_total: Int64 = 0, swap_usage: Int64 = 0) {
        self.ram_total = ram_total
        self.ram_usage = ram_usage
        self.swap_total = swap_total
        self.swap_usage = swap_usage
    }
    
    public var ramUsedFraction: Double {
        guard ram_total > 0 else { return 0 }
        return Double(ram_usage) / Double(ram_total)
    }
    
    public var swapUsedFraction: Double {
        guard swap_total > 0 else { return 0 }
        return Double(swap_usage) / Double(swap_total)
    }
}

public struct MacmonTemp: Codable, Sendable {
    public let cpu_temp_avg: Double?
    public let gpu_temp_avg: Double?
    
    public init(cpu_temp_avg: Double? = nil, gpu_temp_avg: Double? = nil) {
        self.cpu_temp_avg = cpu_temp_avg
        self.gpu_temp_avg = gpu_temp_avg
    }
}

public struct MacmonFan: Codable, Sendable {
    public let max_rpm: Int?
    public let name: String?
    public let rpm: Int?
    
    public init(max_rpm: Int? = nil, name: String? = nil, rpm: Int? = nil) {
        self.max_rpm = max_rpm
        self.name = name
        self.rpm = rpm
    }
}

public struct MacmonSample: Codable, Sendable {
    public let all_power: Double?
    public let ane_power: Double?
    public let cpu_power: Double?
    public let gpu_power: Double?
    public let ram_power: Double?
    public let sys_power: Double?
    public let cpu_usage_pct: Double?
    public let ecpu_cores: [MacmonCoreMetric]?
    public let pcpu_cores: [MacmonCoreMetric]?
    public let ecpu_freq_mhz: Double?
    public let pcpu_freq_mhz: Double?
    public let gpu_freq_mhz: Double?
    public let gpu_active_ratio: Double?
    public let gpu_scaled_ratio: Double?
    public let gpu_usage_ratio: Double?
    public let gpu_usage_pct: Double?
    public let gpu_usage: [Double]?
    public let memory: MacmonMemory?
    public let temp: MacmonTemp?
    public let fans: [MacmonFan]?
    public let timestamp: String?
    
    public init(
        all_power: Double? = nil,
        ane_power: Double? = nil,
        cpu_power: Double? = nil,
        gpu_power: Double? = nil,
        ram_power: Double? = nil,
        sys_power: Double? = nil,
        cpu_usage_pct: Double? = nil,
        ecpu_cores: [MacmonCoreMetric]? = nil,
        pcpu_cores: [MacmonCoreMetric]? = nil,
        ecpu_freq_mhz: Double? = nil,
        pcpu_freq_mhz: Double? = nil,
        gpu_freq_mhz: Double? = nil,
        gpu_active_ratio: Double? = nil,
        gpu_scaled_ratio: Double? = nil,
        gpu_usage_ratio: Double? = nil,
        gpu_usage_pct: Double? = nil,
        gpu_usage: [Double]? = nil,
        memory: MacmonMemory? = nil,
        temp: MacmonTemp? = nil,
        fans: [MacmonFan]? = nil,
        timestamp: String? = nil
    ) {
        self.all_power = all_power
        self.ane_power = ane_power
        self.cpu_power = cpu_power
        self.gpu_power = gpu_power
        self.ram_power = ram_power
        self.sys_power = sys_power
        self.cpu_usage_pct = cpu_usage_pct
        self.ecpu_cores = ecpu_cores
        self.pcpu_cores = pcpu_cores
        self.ecpu_freq_mhz = ecpu_freq_mhz
        self.pcpu_freq_mhz = pcpu_freq_mhz
        self.gpu_freq_mhz = gpu_freq_mhz
        self.gpu_active_ratio = gpu_active_ratio
        self.gpu_scaled_ratio = gpu_scaled_ratio
        self.gpu_usage_ratio = gpu_usage_ratio
        self.gpu_usage_pct = gpu_usage_pct
        self.gpu_usage = gpu_usage
        self.memory = memory
        self.temp = temp
        self.fans = fans
        self.timestamp = timestamp
    }
    
    /// GPU usage ratio normalized within `0.0 ... 1.0`.
    ///
    /// Resolves across diverse `macmon` schema representations:
    /// 1. `gpu_usage_ratio` (explicit ratio)
    /// 2. `gpu_active_ratio` (standard active ratio)
    /// 3. `gpu_scaled_ratio` (frequency scaled ratio)
    /// 4. `gpu_usage_pct` (percentage or ratio)
    /// 5. `gpu_usage` (array `[freq_mhz, ratio]`)
    public var resolvedGpuUsageRatio: Double? {
        if let usage = gpu_usage_ratio {
            return Self.normalizeUsageRatio(usage)
        }
        if let active = gpu_active_ratio {
            return Self.normalizeUsageRatio(active)
        }
        if let scaled = gpu_scaled_ratio {
            return Self.normalizeUsageRatio(scaled)
        }
        if let pct = gpu_usage_pct {
            return Self.normalizeUsageRatio(pct)
        }
        if let arr = gpu_usage, arr.count >= 2 {
            return Self.normalizeUsageRatio(arr[1])
        }
        return nil
    }
    
    /// Normalizes raw usage inputs to a strictly clamped `0.0 ... 1.0` ratio.
    public static func normalizeUsageRatio(_ rawValue: Double) -> Double {
        guard !rawValue.isNaN && !rawValue.isInfinite else { return 0.0 }
        let ratio: Double
        if rawValue > 1.05 {
            ratio = rawValue / 100.0
        } else {
            ratio = rawValue
        }
        return min(1.0, max(0.0, ratio))
    }
}
