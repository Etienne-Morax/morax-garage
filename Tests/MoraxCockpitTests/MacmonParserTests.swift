import XCTest
import Foundation
@testable import MoraxCockpitKit

final class MacmonParserTests: XCTestCase {
    
    func testDecodeMacmonSampleJSON() throws {
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
        
        XCTAssertEqual(sample.all_power, 4.315)
        XCTAssertEqual(sample.sys_power, 24.579)
        XCTAssertEqual(sample.memory?.ram_total, 34359738368)
        XCTAssertEqual(sample.memory?.swap_usage, 5465767936)
        XCTAssertEqual(sample.temp?.cpu_temp_avg, 61.65)
        XCTAssertEqual(sample.ecpu_cores?.count, 2)
        XCTAssertEqual(sample.pcpu_cores?.count, 2)
        XCTAssertEqual(sample.fans?.count, 2)
    }
    
    func testDecodeMacmonSampleWithRealAppleSiliconGpuPayload() throws {
        let realSampleJSON = """
        {
            "all_power": 4.0516,
            "ane_power": 0.0,
            "cpu_active_ratio": 0.2739,
            "cpu_power": 2.732,
            "cpu_scaled_ratio": 0.2167,
            "cpu_usage_pct": 0.2167,
            "gpu_active_ratio": 0.57602,
            "gpu_freq_mhz": 595,
            "gpu_power": 1.3192,
            "gpu_scaled_ratio": 0.2647,
            "gpu_usage": [595, 0.2647],
            "temp": {
                "cpu_temp_avg": 59.4,
                "gpu_temp_avg": 55.82
            },
            "timestamp": "2026-08-27T09:22:59.140459+00:00"
        }
        """
        
        let data = realSampleJSON.data(using: .utf8)!
        let sample = try JSONDecoder().decode(MacmonSample.self, from: data)
        
        XCTAssertEqual(sample.gpu_active_ratio ?? 0, 0.57602, accuracy: 0.0001)
        XCTAssertEqual(sample.gpu_scaled_ratio ?? 0, 0.2647, accuracy: 0.0001)
        XCTAssertEqual(sample.gpu_freq_mhz, 595.0)
        XCTAssertEqual(sample.gpu_power ?? 0, 1.3192, accuracy: 0.0001)
        XCTAssertEqual(sample.temp?.gpu_temp_avg ?? 0, 55.82, accuracy: 0.01)
        XCTAssertEqual(sample.resolvedGpuUsageRatio ?? 0, 0.57602, accuracy: 0.0001)
    }
    
    func testGpuUsageRatioResolutionAcrossSchemas() {
        // 1. Explicit gpu_usage_ratio has top priority
        let sample1 = MacmonSample(gpu_active_ratio: 0.5, gpu_usage_ratio: 0.687)
        XCTAssertEqual(sample1.resolvedGpuUsageRatio ?? 0, 0.687, accuracy: 0.0001)
        
        // 2. Fallback to gpu_active_ratio
        let sample2 = MacmonSample(gpu_active_ratio: 0.45, gpu_scaled_ratio: 0.3)
        XCTAssertEqual(sample2.resolvedGpuUsageRatio ?? 0, 0.45, accuracy: 0.0001)
        
        // 3. Fallback to gpu_scaled_ratio
        let sample3 = MacmonSample(gpu_scaled_ratio: 0.35)
        XCTAssertEqual(sample3.resolvedGpuUsageRatio ?? 0, 0.35, accuracy: 0.0001)
        
        // 4. Fallback to gpu_usage_pct
        let sample4 = MacmonSample(gpu_usage_pct: 0.82)
        XCTAssertEqual(sample4.resolvedGpuUsageRatio ?? 0, 0.82, accuracy: 0.0001)
        
        // 5. Fallback to gpu_usage array [freq, ratio]
        let sample5 = MacmonSample(gpu_usage: [1742.0, 0.725])
        XCTAssertEqual(sample5.resolvedGpuUsageRatio ?? 0, 0.725, accuracy: 0.0001)
        
        // 6. No GPU metrics
        let sample6 = MacmonSample()
        XCTAssertNil(sample6.resolvedGpuUsageRatio)
    }
    
    func testGpuUsageNormalizationAndClamping() {
        // Ratio format (0.687) -> preserved as 0.687 (which UI renders as 68.7 %)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(0.687), 0.687, accuracy: 0.0001)
        
        // Percentage format (68.7) -> converted to 0.687 (UI renders as 68.7 %, NEVER 6870 %)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(68.7), 0.687, accuracy: 0.0001)
        
        // Zero
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(0.0), 0.0, accuracy: 0.0001)
        
        // Max 1.0 (100 %)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(100.0), 1.0, accuracy: 0.0001)
        
        // Negative clamping
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(-0.25), 0.0, accuracy: 0.0001)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(-50.0), 0.0, accuracy: 0.0001)
        
        // Overflow clamping
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(150.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(2.5), 0.025, accuracy: 0.0001)
        
        // NaN & Infinity
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(Double.nan), 0.0)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(Double.infinity), 0.0)
    }
}
