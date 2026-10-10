import XCTest
@testable import MoraxCockpitKit

final class SystemMetricsServiceTests: XCTestCase {
    
    func testTelemetryStatusProperties() {
        let liveStatus = TelemetryStatus.live(source: "macmon")
        XCTAssertTrue(liveStatus.isLive)
        XCTAssertFalse(liveStatus.isFallback)
        XCTAssertFalse(liveStatus.isError)
        XCTAssertFalse(liveStatus.isUnavailable)
        XCTAssertEqual(liveStatus.statusLabel, "macmon live")
        
        let fallbackStatus = TelemetryStatus.fallback(reason: "macmon unavailable")
        XCTAssertFalse(fallbackStatus.isLive)
        XCTAssertTrue(fallbackStatus.isFallback)
        XCTAssertFalse(fallbackStatus.isError)
        XCTAssertFalse(fallbackStatus.isUnavailable)
        XCTAssertEqual(fallbackStatus.statusLabel, "native fallback")
        
        let unavailableStatus = TelemetryStatus.unavailable(reason: "Service stopped")
        XCTAssertFalse(unavailableStatus.isLive)
        XCTAssertFalse(unavailableStatus.isFallback)
        XCTAssertFalse(unavailableStatus.isError)
        XCTAssertTrue(unavailableStatus.isUnavailable)
        XCTAssertEqual(unavailableStatus.statusLabel, "unavailable")
        
        let errorStatus = TelemetryStatus.error("Process launch failed")
        XCTAssertFalse(errorStatus.isLive)
        XCTAssertFalse(errorStatus.isFallback)
        XCTAssertTrue(errorStatus.isError)
        XCTAssertFalse(errorStatus.isUnavailable)
        XCTAssertEqual(errorStatus.statusLabel, "error")
    }
    
    @MainActor
    func testMacmonSampleToSnapshotCpuUsagePreservation() {
        let service = SystemMetricsService()
        let sample = MacmonSample(
            cpu_power: 4.2,
            sys_power: 18.5,
            cpu_usage_pct: 0.201
        )
        
        let snapshot = service.createSnapshot(from: sample)
        
        // cpu_usage_pct = 0.201 must preserve exact fraction 0.201 (not divided by 100)
        XCTAssertEqual(snapshot.cpuUsage, 0.201, accuracy: 0.0001)
        XCTAssertTrue(snapshot.isMacmonActive)
        XCTAssertEqual(snapshot.status, .live(source: "macmon"))
        
        // In UI representation, 0.201 * 100 = 20.1%
        let formattedUiCpu = String(format: "%.1f%%", snapshot.cpuUsage * 100)
        XCTAssertEqual(formattedUiCpu, "20.1%")
    }
    
    @MainActor
    func testMacmonSampleFullTransformation() throws {
        let sampleJSON = """
        {
            "all_power": 4.315,
            "ane_power": 0.0,
            "cpu_power": 4.244,
            "gpu_power": 0.071,
            "ram_power": 1.780,
            "sys_power": 24.579,
            "cpu_usage_pct": 0.201,
            "ecpu_cores": [
                {"active_ratio": 0.525, "core_id": 0, "freq_mhz": 1451},
                {"active_ratio": 0.522, "core_id": 10, "freq_mhz": 1440}
            ],
            "pcpu_cores": [
                {"active_ratio": 0.342, "core_id": 0, "freq_mhz": 3220},
                {"active_ratio": 0.227, "core_id": 10, "freq_mhz": 3220}
            ],
            "memory": {
                "ram_total": 34359738368,
                "ram_usage": 27677458432,
                "swap_total": 6442450944,
                "swap_usage": 5465767936
            },
            "temp": {
                "cpu_temp_avg": 61.65,
                "gpu_temp_avg": 56.28
            },
            "fans": [
                {"max_rpm": 5348, "name": "fan0", "rpm": 0},
                {"max_rpm": 5776, "name": "fan1", "rpm": 0}
            ],
            "timestamp": "2026-08-16T15:04:05.133805+00:00"
        }
        """
        
        let data = sampleJSON.data(using: .utf8)!
        let sample = try JSONDecoder().decode(MacmonSample.self, from: data)
        let service = SystemMetricsService()
        let snapshot = service.createSnapshot(from: sample)
        
        XCTAssertTrue(snapshot.isMacmonActive)
        XCTAssertEqual(snapshot.status, .live(source: "macmon"))
        XCTAssertEqual(snapshot.cpuUsage, 0.201, accuracy: 0.0001)
        XCTAssertEqual(snapshot.systemPower, 24.579, accuracy: 0.001)
        XCTAssertEqual(snapshot.cpuPower, 4.244, accuracy: 0.001)
        XCTAssertEqual(snapshot.gpuPower, 0.071, accuracy: 0.001)
        XCTAssertEqual(snapshot.ramPower, 1.780, accuracy: 0.001)
        XCTAssertEqual(snapshot.anePower, 0.0, accuracy: 0.001)
        
        // E-Cores & P-Cores average active ratios
        XCTAssertEqual(snapshot.eCoreCount, 2)
        XCTAssertEqual(snapshot.pCoreCount, 2)
        XCTAssertEqual(snapshot.eCpuUsage, (0.525 + 0.522) / 2.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.pCpuUsage, (0.342 + 0.227) / 2.0, accuracy: 0.0001)
        
        // Memory & Swap
        XCTAssertEqual(snapshot.ramTotal, 34359738368)
        XCTAssertEqual(snapshot.ramUsed, 27677458432)
        XCTAssertEqual(snapshot.swapTotal, 6442450944)
        XCTAssertEqual(snapshot.swapUsed, 5465767936)
        
        // Thermals & Fans
        XCTAssertEqual(snapshot.cpuTemp, 61.65)
        XCTAssertEqual(snapshot.gpuTemp, 56.28)
        XCTAssertEqual(snapshot.fanSpeedRPM, 0)
    }
    
    func testDetermineStatusTransitionsByFailureType() {
        let binaryNotFoundStatus = SystemMetricsService.determineStatus(for: .binaryNotFound)
        XCTAssertTrue(binaryNotFoundStatus.isFallback)
        XCTAssertFalse(binaryNotFoundStatus.isError)
        XCTAssertEqual(binaryNotFoundStatus.statusLabel, "native fallback")
        XCTAssertTrue(binaryNotFoundStatus.description.contains("macmon binary not found in PATH"))
        
        let launchFailedStatus = SystemMetricsService.determineStatus(for: .launchFailed("permission denied"))
        XCTAssertTrue(launchFailedStatus.isError)
        XCTAssertFalse(launchFailedStatus.isFallback)
        XCTAssertEqual(launchFailedStatus.statusLabel, "error")
        XCTAssertTrue(launchFailedStatus.description.contains("macmon process could not start"))
        
        let firstStreamExitStatus = SystemMetricsService.determineStatus(for: .streamExited(consecutiveFailures: 1))
        XCTAssertTrue(firstStreamExitStatus.isFallback)
        XCTAssertFalse(firstStreamExitStatus.isError)
        XCTAssertEqual(firstStreamExitStatus.statusLabel, "native fallback")
        
        let repeatedStreamExitStatus = SystemMetricsService.determineStatus(for: .streamExited(consecutiveFailures: 2))
        XCTAssertTrue(repeatedStreamExitStatus.isError)
        XCTAssertFalse(repeatedStreamExitStatus.isFallback)
        XCTAssertEqual(repeatedStreamExitStatus.statusLabel, "error")
        XCTAssertTrue(repeatedStreamExitStatus.description.contains("failed repeatedly"))
        
        let severeStreamExitStatus = SystemMetricsService.determineStatus(for: .streamExited(consecutiveFailures: 5))
        XCTAssertTrue(severeStreamExitStatus.isError)
        XCTAssertEqual(severeStreamExitStatus.statusLabel, "error")
        
        let corruptedStreamStatus = SystemMetricsService.determineStatus(for: .streamCorrupted)
        XCTAssertTrue(corruptedStreamStatus.isError)
        XCTAssertEqual(corruptedStreamStatus.statusLabel, "error")
        XCTAssertTrue(corruptedStreamStatus.description.contains("could not be decoded"))
        
        let stoppedStatus = SystemMetricsService.determineStatus(for: .serviceStopped)
        XCTAssertTrue(stoppedStatus.isUnavailable)
        XCTAssertEqual(stoppedStatus.statusLabel, "unavailable")
    }
    
    func testNativeCpuCalculatorUsage() {
        let prev = NativeCpuTicks(user: 1000, system: 500, idle: 8000, nice: 0)
        // Active ticks increased by (100 user + 50 system) = 150. Idle increased by 350. Total = 500. Usage = 150 / 500 = 30% (0.30)
        let current = NativeCpuTicks(user: 1100, system: 550, idle: 8350, nice: 0)
        
        let usage = NativeCpuCalculator.calculateUsage(previous: prev, current: current)
        XCTAssertEqual(usage, 0.30, accuracy: 0.001)
    }
    
    func testNativeCpuCalculatorWithNoPreviousReturnsZero() {
        let current = NativeCpuTicks(user: 1100, system: 550, idle: 8350, nice: 0)
        let usage = NativeCpuCalculator.calculateUsage(previous: nil, current: current)
        XCTAssertEqual(usage, 0.0)
    }
    
    func testNativeCpuCalculatorWithZeroDeltaReturnsZero() {
        let ticks = NativeCpuTicks(user: 1000, system: 500, idle: 8000, nice: 0)
        let usage = NativeCpuCalculator.calculateUsage(previous: ticks, current: ticks)
        XCTAssertEqual(usage, 0.0)
    }
    
    func testBoundedBackoffProgressionAndReset() {
        var backoff = BoundedBackoff(initialDelay: 2.0, maxDelay: 30.0, multiplier: 2.0)
        
        XCTAssertEqual(backoff.nextDelay(), 2.0)
        XCTAssertEqual(backoff.nextDelay(), 4.0)
        XCTAssertEqual(backoff.nextDelay(), 8.0)
        XCTAssertEqual(backoff.nextDelay(), 16.0)
        XCTAssertEqual(backoff.nextDelay(), 30.0)
        XCTAssertEqual(backoff.nextDelay(), 30.0) // Capped at maxDelay
        
        backoff.reset()
        XCTAssertEqual(backoff.currentDelay, 2.0)
        XCTAssertEqual(backoff.nextDelay(), 2.0)
    }
    
    @MainActor
    func testSampleNativeMetricsProducesRealValues() {
        let service = SystemMetricsService()
        let snapshot = service.sampleNativeMetrics(reason: "test run")
        
        XCTAssertTrue(snapshot.status.isFallback)
        XCTAssertFalse(snapshot.isMacmonActive)
        XCTAssertGreaterThan(snapshot.ramTotal, 0)
        XCTAssertGreaterThanOrEqual(snapshot.ramUsed, 0)
        XCTAssertGreaterThanOrEqual(snapshot.uptimeSeconds, 0)
        XCTAssertFalse(snapshot.diskVolumes.isEmpty)
        // Power/thermals must not be treated as live
        XCTAssertNil(snapshot.cpuTemp)
        XCTAssertNil(snapshot.gpuTemp)
        XCTAssertNil(snapshot.fanSpeedRPM)
    }
    
    @MainActor
    func testLifecycleStartAndStop() {
        let service = SystemMetricsService()
        XCTAssertFalse(service.isRunning)
        
        service.startMonitoring()
        XCTAssertTrue(service.isRunning)
        
        service.stopMonitoring()
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(service.currentSnapshot.status, .unavailable(reason: "Monitoring stopped"))
    }
    
    @MainActor
    func testUpdateSnapshotStoresCurrentSnapshot() {
        let service = SystemMetricsService()
        let custom = SystemSnapshot(
            timestamp: Date(),
            status: .live(source: "macmon"),
            cpuUsage: 0.45,
            ramTotal: 36 * 1024 * 1024 * 1024,
            ramUsed: 18 * 1024 * 1024 * 1024,
            systemPower: 28.5
        )
        
        service.updateSnapshot(custom)
        XCTAssertEqual(service.currentSnapshot.cpuUsage, 0.45)
        XCTAssertEqual(service.currentSnapshot.systemPower, 28.5)
    }
    
    @MainActor
    func testMacmonSampleToSnapshotGpuUsagePreservation() {
        let service = SystemMetricsService()
        let sample = MacmonSample(
            gpu_power: 27.6,
            gpu_freq_mhz: 1742.0,
            gpu_active_ratio: 0.687
        )
        
        let snapshot = service.createSnapshot(from: sample)
        
        // gpu_active_ratio = 0.687 must preserve exact fraction 0.687
        XCTAssertEqual(snapshot.gpuUsage, 0.687, accuracy: 0.0001)
        XCTAssertEqual(snapshot.gpuFreqMHz, 1742.0)
        XCTAssertEqual(snapshot.gpuPower, 27.6, accuracy: 0.001)
        XCTAssertTrue(snapshot.isMacmonActive)
        
        // UI value calculation (0.687 * 100 = 68.7%)
        let uiGpuValue = snapshot.gpuUsage * 100
        let formattedUiGpu = String(format: "%.1f %%", uiGpuValue)
        XCTAssertEqual(formattedUiGpu, "68.7 %")
        XCTAssertNotEqual(formattedUiGpu, "6870.0 %")
    }
    
    @MainActor
    func testGpuMissingValuesHandling() {
        let service = SystemMetricsService()
        
        // Case 1: Usage absent, frequency present, power absent
        let sample1 = MacmonSample(gpu_freq_mhz: 1742.0)
        let snapshot1 = service.createSnapshot(from: sample1)
        XCTAssertEqual(snapshot1.gpuUsage, 0.0)
        XCTAssertEqual(snapshot1.gpuFreqMHz, 1742.0)
        XCTAssertEqual(snapshot1.gpuPower, 0.0)
        
        // Case 2: Usage present, frequency absent, power present
        let sample2 = MacmonSample(gpu_power: 12.4, gpu_usage_ratio: 0.45)
        let snapshot2 = service.createSnapshot(from: sample2)
        XCTAssertEqual(snapshot2.gpuUsage, 0.45, accuracy: 0.0001)
        XCTAssertNil(snapshot2.gpuFreqMHz)
        XCTAssertEqual(snapshot2.gpuPower, 12.4, accuracy: 0.001)
        
        // Case 3: All GPU values absent
        let sample3 = MacmonSample(cpu_usage_pct: 0.15)
        let snapshot3 = service.createSnapshot(from: sample3)
        XCTAssertEqual(snapshot3.gpuUsage, 0.0)
        XCTAssertNil(snapshot3.gpuFreqMHz)
        XCTAssertEqual(snapshot3.gpuPower, 0.0)
        XCTAssertNil(snapshot3.gpuTemp)
    }
    
    @MainActor
    func testDisconnectedSourceGpuState() {
        let service = SystemMetricsService()
        let nativeSnapshot = service.sampleNativeMetrics(reason: "macmon stopped")
        
        XCTAssertFalse(nativeSnapshot.isMacmonActive)
        XCTAssertGreaterThanOrEqual(nativeSnapshot.gpuUsage, 0.0)
        XCTAssertLessThanOrEqual(nativeSnapshot.gpuUsage, 1.0)
        XCTAssertNil(nativeSnapshot.gpuFreqMHz)
        XCTAssertEqual(nativeSnapshot.gpuPower, 0.0)
        XCTAssertNil(nativeSnapshot.gpuTemp)
    }
    
    @MainActor
    func testNonRegressionExistingInstruments() {
        let service = SystemMetricsService()
        let sample = MacmonSample(
            all_power: 15.0,
            cpu_power: 8.5,
            gpu_power: 4.2,
            ram_power: 2.1,
            sys_power: 22.0,
            cpu_usage_pct: 0.35,
            ecpu_cores: [MacmonCoreMetric(active_ratio: 0.4, freq_mhz: 1500)],
            pcpu_cores: [MacmonCoreMetric(active_ratio: 0.6, freq_mhz: 3000)],
            gpu_freq_mhz: 1200,
            gpu_active_ratio: 0.55,
            memory: MacmonMemory(ram_total: 16 * 1024 * 1024 * 1024, ram_usage: 10 * 1024 * 1024 * 1024, swap_total: 4 * 1024 * 1024 * 1024, swap_usage: 1 * 1024 * 1024 * 1024)
        )
        
        let snapshot = service.createSnapshot(from: sample)
        
        // Existing gauges continue to receive exact expected metrics
        XCTAssertEqual(snapshot.cpuUsage, 0.35, accuracy: 0.0001)
        XCTAssertEqual(snapshot.eCpuUsage, 0.4, accuracy: 0.0001)
        XCTAssertEqual(snapshot.pCpuUsage, 0.6, accuracy: 0.0001)
        XCTAssertEqual(snapshot.ramTotal, 16 * 1024 * 1024 * 1024)
        XCTAssertEqual(snapshot.ramUsed, 10 * 1024 * 1024 * 1024)
        XCTAssertEqual(snapshot.swapTotal, 4 * 1024 * 1024 * 1024)
        XCTAssertEqual(snapshot.swapUsed, 1 * 1024 * 1024 * 1024)
        XCTAssertEqual(snapshot.systemPower, 22.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.cpuPower, 8.5, accuracy: 0.001)
        
        // GPU gauge receives newly mapped metrics
        XCTAssertEqual(snapshot.gpuUsage, 0.55, accuracy: 0.0001)
        XCTAssertEqual(snapshot.gpuFreqMHz, 1200.0)
        XCTAssertEqual(snapshot.gpuPower, 4.2, accuracy: 0.001)
    }
}
