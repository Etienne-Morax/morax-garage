import Foundation
import IOKit

/// Échantillonneur matériel natif GPU pour macOS via IOKit (`IOAccelerator`).
///
/// Permet d'extraire le taux d'utilisation instantané du GPU sans dépendance externe,
/// fournissant une source de données matérielle fiable pour les processeurs Apple Silicon et Intel.
public enum NativeGpuSampler {
    
    /// Échantillonne le taux d'utilisation GPU matériel instantané normalisé entre `0.0` et `1.0`.
    /// Retourne `nil` si aucun service `IOAccelerator` n'est accessible.
    public static func sampleGpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        var maxUsage: Double = 0.0
        var foundValidReading = false
        
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            if let props = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                
                if let devUtil = props["Device Utilization %"] as? Int {
                    let ratio = Double(devUtil) / 100.0
                    maxUsage = max(maxUsage, ratio)
                    foundValidReading = true
                } else if let devUtil = props["Device Utilization %"] as? Double {
                    let ratio = devUtil > 1.0 ? devUtil / 100.0 : devUtil
                    maxUsage = max(maxUsage, ratio)
                    foundValidReading = true
                } else if let devUtil = props["Device Utilization %"] as? NSNumber {
                    let doubleVal = devUtil.doubleValue
                    let ratio = doubleVal > 1.0 ? doubleVal / 100.0 : doubleVal
                    maxUsage = max(maxUsage, ratio)
                    foundValidReading = true
                } else if let gpuActivity = props["GPU Activity"] as? Int {
                    let ratio = Double(gpuActivity) / 100.0
                    maxUsage = max(maxUsage, ratio)
                    foundValidReading = true
                } else if let gpuActivity = props["GPU Activity"] as? Double {
                    let ratio = gpuActivity > 1.0 ? gpuActivity / 100.0 : gpuActivity
                    maxUsage = max(maxUsage, ratio)
                    foundValidReading = true
                } else if let gpuUtil = props["GPU Core Utilization"] as? Double {
                    let ratio = gpuUtil > 1.0 ? gpuUtil / 100.0 : gpuUtil
                    maxUsage = max(maxUsage, ratio)
                    foundValidReading = true
                }
            }
        }
        
        return foundValidReading ? min(1.0, max(0.0, maxUsage)) : nil
    }
}
