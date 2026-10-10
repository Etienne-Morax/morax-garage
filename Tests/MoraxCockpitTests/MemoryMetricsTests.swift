import XCTest
@testable import MoraxCockpitKit

final class MemoryMetricsTests: XCTestCase {
    
    // MARK: - 1. Formule canonique avec fixture Apple Silicon 32 Go standard
    
    func testCanonicalMemoryCalculationsWithStandardAppleSiliconFixture() {
        let pageSize: Int64 = 16384 // 16 KB page size on Apple Silicon
        let totalRam: Int64 = 34_359_738_368 // 32 GB
        
        // Simule vm_statistics64 (en nombre de pages)
        let internalPages: UInt64 = 800_000   // Anonyme / App
        let purgeablePages: UInt64 = 20_000   // Purgeable
        let wiredPages: UInt64 = 200_000       // Résidente (wired)
        let compressorPages: UInt64 = 300_000  // Occupée par le compresseur
        let uncompressedPages: UInt64 = 650_000
        let externalPages: UInt64 = 500_000    // Fichiers en cache (file-backed)
        let freePages: UInt64 = 100_000        // Libre
        let speculativePages: UInt64 = 30_000
        let activePages: UInt64 = 700_000
        let inactivePages: UInt64 = 600_000
        
        let swapTotal: Int64 = 4_294_967_296  // 4 GB
        let swapUsed: Int64 = 524_288_000     // 500 MB
        let timestamp = Date(timeIntervalSince1970: 1724500000)
        
        let metrics = SystemMemoryCalculator.calculateFromRawCounts(
            freePages: freePages,
            activePages: activePages,
            inactivePages: inactivePages,
            speculativePages: speculativePages,
            wiredPages: wiredPages,
            purgeablePages: purgeablePages,
            externalPages: externalPages,
            internalPages: internalPages,
            compressorPages: compressorPages,
            uncompressedInCompressorPages: uncompressedPages,
            pageSize: pageSize,
            totalPhysicalMemory: totalRam,
            swapTotal: swapTotal,
            swapUsed: swapUsed,
            virtualAllocatedBytes: nil,
            memoryPressure: .normal,
            timestamp: timestamp,
            source: "Darwin vm_statistics64 fixture"
        )
        
        // 1. App Memory = (800_000 - 20_000) * 16384 = 12_779_520_000 octets (~11.9 GB)
        let expectedAppMemory: Int64 = 780_000 * pageSize
        XCTAssertEqual(metrics.appMemoryBytes, expectedAppMemory)
        
        // 2. Wired Memory = 200_000 * 16384 = 3_276_800_000 octets (~3.05 GB)
        let expectedWired: Int64 = 200_000 * pageSize
        XCTAssertEqual(metrics.wiredBytes, expectedWired)
        
        // 3. Compressed Memory = 300_000 * 16384 = 4_915_200_000 octets (~4.57 GB)
        let expectedCompressed: Int64 = 300_000 * pageSize
        XCTAssertEqual(metrics.compressedBytes, expectedCompressed)
        XCTAssertEqual(metrics.uncompressedInCompressorBytes, 650_000 * pageSize)
        
        // 4. Mémoire utilisée (Canonique Moniteur d'activité) = App + Wired + Compressed
        let expectedUsed: Int64 = expectedAppMemory + expectedWired + expectedCompressed // 20_971_520_000 octets (~19.53 GB)
        XCTAssertEqual(metrics.usedBytes, expectedUsed)
        XCTAssertEqual(metrics.usedBytes, 20_971_520_000)
        
        // 5. Fichiers en cache (external + purgeable) = (500_000 + 20_000) * 16384 = 8_519_680_000 octets (~7.93 GB)
        let expectedCached: Int64 = 520_000 * pageSize
        XCTAssertEqual(metrics.cachedFilesBytes, expectedCached)
        
        // 6. Mémoire disponible (immédiatement réutilisable : free + cached) = (100_000 + 520_000) * 16384 = 10_158_080_000 octets (~9.46 GB)
        let expectedAvailable = Int64(freePages + 520_000) * pageSize
        XCTAssertEqual(metrics.availableBytes, expectedAvailable)
        
        // 7. Swap
        XCTAssertEqual(metrics.swapTotalBytes, swapTotal)
        XCTAssertEqual(metrics.swapUsedBytes, swapUsed)
        
        // 8. Métadonnées
        XCTAssertEqual(metrics.source, "Darwin vm_statistics64 fixture")
        XCTAssertEqual(metrics.timestamp, timestamp)
        XCTAssertEqual(metrics.memoryPressure, .normal)
        XCTAssertFalse(metrics.isUnknown)
    }
    
    // MARK: - 2. Allocation virtuelle dépassant la RAM physique (ex. 51 Go / 400 To virtuels vs 32 Go physiques)
    
    func testVirtualAllocatedMemoryExceedingPhysicalRamNeverPollutesPhysicalUsedMemory() {
        let pageSize: Int64 = 16384
        let totalRam: Int64 = 34_359_738_368 // 32 GB
        let virtualAllocated: Int64 = 54_761_848_832 // 51 GB (allocation virtuelle agrégée VSZ / disk caches)
        
        let internalPages: UInt64 = 600_000
        let purgeablePages: UInt64 = 10_000
        let wiredPages: UInt64 = 150_000
        let compressorPages: UInt64 = 100_000
        
        let metrics = SystemMemoryCalculator.calculateFromRawCounts(
            freePages: 500_000,
            activePages: 600_000,
            inactivePages: 400_000,
            speculativePages: 20_000,
            wiredPages: wiredPages,
            purgeablePages: purgeablePages,
            externalPages: 400_000,
            internalPages: internalPages,
            compressorPages: compressorPages,
            pageSize: pageSize,
            totalPhysicalMemory: totalRam,
            swapTotal: 0,
            swapUsed: 0,
            virtualAllocatedBytes: virtualAllocated,
            memoryPressure: .normal,
            timestamp: Date(),
            source: "Darwin vm_statistics64"
        )
        
        // La mémoire physique utilisée DOIT rester basée sur la RAM physique réelle
        let appPages = internalPages - purgeablePages
        let physicalPages = appPages + wiredPages + compressorPages
        let expectedPhysicalUsed = Int64(physicalPages) * pageSize
        XCTAssertEqual(metrics.usedBytes, expectedPhysicalUsed)
        XCTAssertLessThanOrEqual(metrics.usedBytes, totalRam)
        
        // La mémoire virtuelle est stockée séparément et ne modifie pas usedBytes
        XCTAssertEqual(metrics.virtualAllocatedBytes, virtualAllocated)
        XCTAssertNotEqual(metrics.usedBytes, virtualAllocated)
        XCTAssertTrue(metrics.usedBytes < totalRam)
    }
    
    // MARK: - 3. Scénario avec forte compression mémoire et swap
    
    func testHeavyMemoryCompressionAndSwapScenario() {
        let pageSize: Int64 = 16384
        let totalRam: Int64 = 17_179_869_184 // 16 GB
        
        let internalPages: UInt64 = 500_000
        let purgeablePages: UInt64 = 5_000
        let wiredPages: UInt64 = 200_000
        let compressorPages: UInt64 = 300_000 // ~4.9 GB en RAM compressée
        let uncompressedPages: UInt64 = 900_000 // ~14.7 GB de données avant compression
        
        let swapTotal: Int64 = 8_589_934_592 // 8 GB
        let swapUsed: Int64 = 3_221_225_472  // 3 GB
        
        let metrics = SystemMemoryCalculator.calculateFromRawCounts(
            freePages: 50_000,
            activePages: 400_000,
            inactivePages: 200_000,
            speculativePages: 10_000,
            wiredPages: wiredPages,
            purgeablePages: purgeablePages,
            externalPages: 100_000,
            internalPages: internalPages,
            compressorPages: compressorPages,
            uncompressedInCompressorPages: uncompressedPages,
            pageSize: pageSize,
            totalPhysicalMemory: totalRam,
            swapTotal: swapTotal,
            swapUsed: swapUsed,
            memoryPressure: .warning,
            timestamp: Date(),
            source: "Darwin vm_statistics64"
        )
        
        XCTAssertEqual(metrics.compressedBytes, Int64(compressorPages) * pageSize)
        XCTAssertEqual(metrics.uncompressedInCompressorBytes, Int64(uncompressedPages) * pageSize)
        XCTAssertEqual(metrics.swapUsedBytes, swapUsed)
        XCTAssertEqual(metrics.swapTotalBytes, swapTotal)
        XCTAssertEqual(metrics.memoryPressure, .warning)
        
        // Ratio swap utilisé
        XCTAssertEqual(metrics.swapUsedFraction, Double(swapUsed) / Double(swapTotal), accuracy: 0.0001)
    }
    
    // MARK: - 4. Cas limites et statut UNKNOWN
    
    func testInvalidInputsAndUnknownFallback() {
        let invalidPageSize = SystemMemoryCalculator.calculateFromRawCounts(
            freePages: 100, activePages: 100, inactivePages: 100, speculativePages: 0,
            wiredPages: 100, purgeablePages: 0, externalPages: 100, internalPages: 100,
            compressorPages: 0, pageSize: 0, totalPhysicalMemory: 32_000_000_000
        )
        XCTAssertTrue(invalidPageSize.isUnknown)
        XCTAssertEqual(invalidPageSize.source, "UNKNOWN")
        
        let unknownMetrics = SystemMemoryMetrics.unknown(reason: "Mach host port failure")
        XCTAssertTrue(unknownMetrics.isUnknown)
        XCTAssertEqual(unknownMetrics.source, "UNKNOWN")
        XCTAssertEqual(unknownMetrics.usedBytes, 0)
        XCTAssertEqual(unknownMetrics.availableBytes, 0)
    }
    
    // MARK: - 5. Test d'intégration de cohérence globale dans SystemSnapshot
    
    @MainActor
    func testSystemSnapshotIntegratesCanonicalMemoryMetricsConsistently() {
        let memory = SystemMemoryMetrics(
            timestamp: Date(),
            source: "Darwin vm_statistics64",
            totalPhysicalBytes: 34_359_738_368, // 32 GB
            usedBytes: 21_474_836_480,          // 20 GB
            appMemoryBytes: 12_884_901_888,      // 12 GB
            wiredBytes: 4_294_967_296,           // 4 GB
            compressedBytes: 4_294_967_296,      // 4 GB
            uncompressedInCompressorBytes: 8_589_934_592,
            availableBytes: 12_884_901_888,      // 12 GB
            freeBytes: 2_147_483_648,            // 2 GB
            cachedFilesBytes: 10_737_418_240,    // 10 GB
            swapUsedBytes: 0,
            swapTotalBytes: 4_294_967_296,
            virtualAllocatedBytes: nil,
            memoryPressure: .normal
        )
        
        let snapshot = SystemSnapshot(
            timestamp: memory.timestamp,
            status: .live(source: "macmon"),
            isMacmonActive: true,
            cpuUsage: 0.25,
            memory: memory
        )
        
        // Vérification de la cohérence interne des accesseurs
        XCTAssertEqual(snapshot.ramTotal, memory.totalPhysicalBytes)
        XCTAssertEqual(snapshot.ramUsed, memory.usedBytes)
        XCTAssertEqual(snapshot.ramAvailable, memory.availableBytes)
        XCTAssertEqual(snapshot.ramCompressed, memory.compressedBytes)
        XCTAssertEqual(snapshot.ramCached, memory.cachedFilesBytes)
        XCTAssertEqual(snapshot.ramFree, memory.freeBytes)
        XCTAssertEqual(snapshot.swapTotal, memory.swapTotalBytes)
        XCTAssertEqual(snapshot.swapUsed, memory.swapUsedBytes)
        XCTAssertEqual(snapshot.compressedMemory, memory.compressedBytes)
        XCTAssertEqual(snapshot.memoryPressure, memory.memoryPressure)
        
        // Vérification de la décomposition canonique
        XCTAssertEqual(snapshot.ramUsed, memory.appMemoryBytes + memory.wiredBytes + memory.compressedBytes)
        XCTAssertEqual(snapshot.ramAvailable, memory.freeBytes + memory.cachedFilesBytes)
        
        // Fractions de jauge
        XCTAssertEqual(snapshot.ramUsedFraction, 21_474_836_480.0 / 34_359_738_368.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.swapUsedFraction, 0.0)
    }

    // MARK: - Pression mémoire (kern.memorystatus_level)

    func testPressureFractionIsComplementOfKernelFreeLevel() {
        XCTAssertEqual(SystemMemoryCalculator.pressureFraction(fromFreeLevel: 55) ?? -1, 0.45, accuracy: 0.0001)
        XCTAssertEqual(SystemMemoryCalculator.pressureFraction(fromFreeLevel: 100), 0)
        XCTAssertEqual(SystemMemoryCalculator.pressureFraction(fromFreeLevel: 0), 1)
    }

    func testPressureFractionRejectsOutOfRangeKernelLevel() {
        XCTAssertNil(SystemMemoryCalculator.pressureFraction(fromFreeLevel: -1))
        XCTAssertNil(SystemMemoryCalculator.pressureFraction(fromFreeLevel: 101))
    }

    func testPressureFractionIsIndependentOfUsedMemory() {
        // 25 Go « utilisés » sur 32 Go mais seulement 45 % de pression : le cache ne compte pas.
        let memory = SystemMemoryMetrics(
            totalPhysicalBytes: 32 * 1_073_741_824,
            usedBytes: 25 * 1_073_741_824,
            pressureFraction: 0.45
        )
        XCTAssertEqual(memory.usedFraction, 25.0 / 32.0, accuracy: 0.0001)
        XCTAssertEqual(memory.pressureFraction ?? -1, 0.45, accuracy: 0.0001)
    }

    func testLegacyEncodedMetricsDecodeWithoutPressureFraction() throws {
        let legacy = SystemMemoryMetrics(totalPhysicalBytes: 1_000, usedBytes: 500)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "pressureFraction")
        let decoded = try JSONDecoder().decode(SystemMemoryMetrics.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.pressureFraction)
    }
}
