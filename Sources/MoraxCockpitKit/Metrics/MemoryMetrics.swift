import Foundation
import Darwin

/// Représente l'état détaillé et canonique de la mémoire système macOS,
/// aligné sur les définitions et conventions du Moniteur d'activité Apple.
public struct SystemMemoryMetrics: Sendable, Equatable, Codable {
    /// Horodatage de l'échantillonnage
    public let timestamp: Date
    
    /// Identifiant de la source de mesure (ex: "Darwin vm_statistics64", "UNKNOWN")
    public let source: String
    
    /// Capacité totale de mémoire physique installée (en octets, ex: 32 Go)
    public let totalPhysicalBytes: Int64
    
    /// Mémoire utilisée canonique (RAM physique réellement occupée) : App + Résidente + Compressée
    public let usedBytes: Int64
    
    /// Mémoire des applications / anonyme (internal_page_count - purgeable_count)
    public let appMemoryBytes: Int64
    
    /// Mémoire résidente / wired (wire_count)
    public let wiredBytes: Int64
    
    /// Mémoire compressée (espace physique occupé par le compresseur dans la RAM)
    public let compressedBytes: Int64
    
    /// Taille décompressée totale avant compression (si disponible)
    public let uncompressedInCompressorBytes: Int64?
    
    /// Mémoire disponible (immédiatement réutilisable sans swap : Libre + Fichiers en cache)
    public let availableBytes: Int64
    
    /// Mémoire libre (pages libres non allouées)
    public let freeBytes: Int64
    
    /// Fichiers en cache / Inactive réutilisable (external file-backed + purgeable)
    public let cachedFilesBytes: Int64
    
    /// Swap utilisé (espace de pagination disque actif)
    public let swapUsedBytes: Int64
    
    /// Swap total configuré / alloué
    public let swapTotalBytes: Int64
    
    /// Mémoire virtuelle allouée (non physique), si disponible
    public let virtualAllocatedBytes: Int64?
    
    /// Niveau de pression sur la mémoire macOS
    public let memoryPressure: MemoryPressureState?

    /// Pression mémoire réelle (0…1) = 1 − kern.memorystatus_level / 100.
    /// Contrairement à `usedFraction`, ignore le cache que macOS libère à la demande :
    /// c'est le pourcentage affiché par `memory_pressure` et le graphe du Moniteur d'activité.
    public let pressureFraction: Double?
    
    public init(
        timestamp: Date = Date(),
        source: String = "Darwin vm_statistics64",
        totalPhysicalBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory),
        usedBytes: Int64 = 0,
        appMemoryBytes: Int64 = 0,
        wiredBytes: Int64 = 0,
        compressedBytes: Int64 = 0,
        uncompressedInCompressorBytes: Int64? = nil,
        availableBytes: Int64 = 0,
        freeBytes: Int64 = 0,
        cachedFilesBytes: Int64 = 0,
        swapUsedBytes: Int64 = 0,
        swapTotalBytes: Int64 = 0,
        virtualAllocatedBytes: Int64? = nil,
        memoryPressure: MemoryPressureState? = nil,
        pressureFraction: Double? = nil
    ) {
        self.timestamp = timestamp
        self.source = source
        self.totalPhysicalBytes = max(1, totalPhysicalBytes)
        self.usedBytes = max(0, usedBytes)
        self.appMemoryBytes = max(0, appMemoryBytes)
        self.wiredBytes = max(0, wiredBytes)
        self.compressedBytes = max(0, compressedBytes)
        self.uncompressedInCompressorBytes = uncompressedInCompressorBytes
        self.availableBytes = max(0, availableBytes)
        self.freeBytes = max(0, freeBytes)
        self.cachedFilesBytes = max(0, cachedFilesBytes)
        self.swapUsedBytes = max(0, swapUsedBytes)
        self.swapTotalBytes = max(0, swapTotalBytes)
        self.virtualAllocatedBytes = virtualAllocatedBytes
        self.memoryPressure = memoryPressure
        self.pressureFraction = pressureFraction.map { min(1, max(0, $0)) }
    }
    
    // MARK: - Computed Properties & Helpers
    
    public var usedFraction: Double {
        guard totalPhysicalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalPhysicalBytes)
    }
    
    public var availableFraction: Double {
        guard totalPhysicalBytes > 0 else { return 0 }
        return Double(availableBytes) / Double(totalPhysicalBytes)
    }
    
    public var swapUsedFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }
    
    public var usedGB: Double {
        Double(usedBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var totalGB: Double {
        Double(totalPhysicalBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var availableGB: Double {
        Double(availableBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var compressedGB: Double {
        Double(compressedBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var cachedFilesGB: Double {
        Double(cachedFilesBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var freeGB: Double {
        Double(freeBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var swapUsedGB: Double {
        Double(swapUsedBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .memory)
    }
    
    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalPhysicalBytes, countStyle: .memory)
    }
    
    public var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .memory)
    }
    
    public var formattedAppMemory: String {
        ByteCountFormatter.string(fromByteCount: appMemoryBytes, countStyle: .memory)
    }
    
    public var formattedWired: String {
        ByteCountFormatter.string(fromByteCount: wiredBytes, countStyle: .memory)
    }
    
    public var formattedCompressed: String {
        ByteCountFormatter.string(fromByteCount: compressedBytes, countStyle: .memory)
    }
    
    public var formattedCachedFiles: String {
        ByteCountFormatter.string(fromByteCount: cachedFilesBytes, countStyle: .memory)
    }
    
    public var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .memory)
    }
    
    public var formattedSwapUsed: String {
        ByteCountFormatter.string(fromByteCount: swapUsedBytes, countStyle: .memory)
    }
    
    public var formattedSwapTotal: String {
        ByteCountFormatter.string(fromByteCount: swapTotalBytes, countStyle: .memory)
    }
    
    public var isUnknown: Bool {
        source == "UNKNOWN" || totalPhysicalBytes == 0
    }
    
    /// État sentinelle en cas d'indisponibilité de la source
    public static func unknown(reason: String = "Source indisponible") -> SystemMemoryMetrics {
        SystemMemoryMetrics(
            timestamp: Date(),
            source: "UNKNOWN",
            totalPhysicalBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            usedBytes: 0,
            appMemoryBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            uncompressedInCompressorBytes: nil,
            availableBytes: 0,
            freeBytes: 0,
            cachedFilesBytes: 0,
            swapUsedBytes: 0,
            swapTotalBytes: 0,
            virtualAllocatedBytes: nil,
            memoryPressure: nil
        )
    }
}

/// Moteur de calcul canonique pour les métriques de mémoire macOS.
public enum SystemMemoryCalculator {

    /// Bornes du pourcentage de mémoire libre publié par le kernel (kern.memorystatus_level).
    private static let kernelFreeLevelRange = 0...100

    /// Convertit le niveau de mémoire libre du kernel (0…100) en fraction de pression (0…1).
    public static func pressureFraction(fromFreeLevel level: Int) -> Double? {
        guard kernelFreeLevelRange.contains(level) else { return nil }
        return 1 - Double(level) / Double(kernelFreeLevelRange.upperBound)
    }

    /// Lit kern.memorystatus_level ; nil si la sysctl est indisponible.
    public static func samplePressureFraction() -> Double? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return nil }
        return pressureFraction(fromFreeLevel: Int(level))
    }
    
    /// Échantillonne en temps réel les compteurs Darwin via mach host_statistics64 et sysctl vm.swapusage
    public static func sampleCurrent(pressure: MemoryPressureState? = nil) -> SystemMemoryMetrics {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return SystemMemoryMetrics.unknown(reason: "host_statistics64 failed with kern_return_t \(kerr)")
        }
        
        let pageSize = Int64(getpagesize())
        let totalRam = Int64(ProcessInfo.processInfo.physicalMemory)
        
        // Swap via sysctlbyname("vm.swapusage")
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapTotal: Int64 = 0
        var swapUsed: Int64 = 0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapTotal = Int64(swapUsage.xsu_total)
            swapUsed = Int64(swapUsage.xsu_used)
        }
        
        return calculate(
            from: stats,
            pageSize: pageSize,
            totalPhysicalMemory: totalRam,
            swapTotal: swapTotal,
            swapUsed: swapUsed,
            virtualAllocatedBytes: nil,
            memoryPressure: pressure,
            pressureFraction: samplePressureFraction(),
            timestamp: Date(),
            source: "Darwin vm_statistics64"
        )
    }
    
    /// Calcule les métriques canoniques à partir de la structure Darwin vm_statistics64
    public static func calculate(
        from stats: vm_statistics64,
        pageSize: Int64,
        totalPhysicalMemory: Int64,
        swapTotal: Int64 = 0,
        swapUsed: Int64 = 0,
        virtualAllocatedBytes: Int64? = nil,
        memoryPressure: MemoryPressureState? = nil,
        pressureFraction: Double? = nil,
        timestamp: Date = Date(),
        source: String = "Darwin vm_statistics64"
    ) -> SystemMemoryMetrics {
        let freePages = UInt64(stats.free_count)
        let activePages = UInt64(stats.active_count)
        let inactivePages = UInt64(stats.inactive_count)
        let speculativePages = UInt64(stats.speculative_count)
        let wiredPages = UInt64(stats.wire_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let externalPages = UInt64(stats.external_page_count)
        let internalPages = UInt64(stats.internal_page_count)
        let compressorPages = UInt64(stats.compressor_page_count)
        let uncompressedInCompPages = stats.total_uncompressed_pages_in_compressor
        
        return calculateFromRawCounts(
            freePages: freePages,
            activePages: activePages,
            inactivePages: inactivePages,
            speculativePages: speculativePages,
            wiredPages: wiredPages,
            purgeablePages: purgeablePages,
            externalPages: externalPages,
            internalPages: internalPages,
            compressorPages: compressorPages,
            uncompressedInCompressorPages: uncompressedInCompPages,
            pageSize: pageSize,
            totalPhysicalMemory: totalPhysicalMemory,
            swapTotal: swapTotal,
            swapUsed: swapUsed,
            virtualAllocatedBytes: virtualAllocatedBytes,
            memoryPressure: memoryPressure,
            pressureFraction: pressureFraction,
            timestamp: timestamp,
            source: source
        )
    }
    
    /// Fonction pure de calcul à partir des compteurs de pages bruts.
    ///
    /// Règles canoniques macOS Activity Monitor :
    /// - App Memory (Mémoire app / anonyme) = max(0, internal - purgeable) * pageSize
    /// - Wired Memory (Mémoire résidente) = wired * pageSize
    /// - Compressed Memory (Compressée) = compressor * pageSize
    /// - Mémoire utilisée = App Memory + Wired Memory + Compressed Memory
    /// - Cached Files (Fichiers en cache / inactive) = (external + purgeable) * pageSize
    /// - Mémoire disponible = Free + Cached Files
    public static func calculateFromRawCounts(
        freePages: UInt64,
        activePages: UInt64,
        inactivePages: UInt64,
        speculativePages: UInt64,
        wiredPages: UInt64,
        purgeablePages: UInt64,
        externalPages: UInt64,
        internalPages: UInt64,
        compressorPages: UInt64,
        uncompressedInCompressorPages: UInt64? = nil,
        pageSize: Int64,
        totalPhysicalMemory: Int64,
        swapTotal: Int64 = 0,
        swapUsed: Int64 = 0,
        virtualAllocatedBytes: Int64? = nil,
        memoryPressure: MemoryPressureState? = nil,
        pressureFraction: Double? = nil,
        timestamp: Date = Date(),
        source: String = "Darwin vm_statistics64"
    ) -> SystemMemoryMetrics {
        guard pageSize > 0, totalPhysicalMemory > 0 else {
            return SystemMemoryMetrics.unknown(reason: "Invalid pageSize or totalPhysicalMemory")
        }
        
        let freeBytes = Int64(freePages) * pageSize
        let wiredBytes = Int64(wiredPages) * pageSize
        let purgeableBytes = Int64(purgeablePages) * pageSize
        let externalBytes = Int64(externalPages) * pageSize
        let internalBytes = Int64(internalPages) * pageSize
        let compressorBytes = Int64(compressorPages) * pageSize
        
        let uncompressedBytes: Int64? = uncompressedInCompressorPages.map { Int64($0) * pageSize }
        
        // 1. App Memory (Mémoire de l'application) = Pages internes (anonymes) - Pages purgeables
        let appMemoryBytes = max(0, internalBytes - purgeableBytes)
        
        // 2. Mémoire utilisée (Apple Activity Monitor) = App Memory + Wired + Compressed
        let rawUsedBytes = appMemoryBytes + wiredBytes + compressorBytes
        let usedBytes = max(0, min(totalPhysicalMemory, rawUsedBytes))
        
        // 3. Fichiers en cache / Inactive = Pages externes (adossées aux fichiers) + Pages purgeables
        let cachedFilesBytes = externalBytes + purgeableBytes
        
        // 4. Mémoire disponible (immédiatement réutilisable sans swap) = Pages libres + Fichiers en cache
        let rawAvailableBytes = freeBytes + cachedFilesBytes
        let availableBytes = max(0, min(totalPhysicalMemory, rawAvailableBytes))
        
        return SystemMemoryMetrics(
            timestamp: timestamp,
            source: source,
            totalPhysicalBytes: totalPhysicalMemory,
            usedBytes: usedBytes,
            appMemoryBytes: appMemoryBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressorBytes,
            uncompressedInCompressorBytes: uncompressedBytes,
            availableBytes: availableBytes,
            freeBytes: freeBytes,
            cachedFilesBytes: cachedFilesBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            virtualAllocatedBytes: virtualAllocatedBytes,
            memoryPressure: memoryPressure,
            pressureFraction: pressureFraction
        )
    }
}
