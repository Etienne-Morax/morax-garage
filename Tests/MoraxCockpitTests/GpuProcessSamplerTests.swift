import XCTest
import AppKit
@testable import MoraxCockpitKit

final class GpuProcessSamplerTests: XCTestCase {
    
    func testDescendingSortAndTop5Selection() async {
        let tracker = GpuProcessStateTracker(pathForPID: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 1000)
        
        // Initial sample
        let initialEntries = [
            RawGpuProcessEntry(pid: 101, name: "AppA", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 102, name: "AppB", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 103, name: "AppC", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 104, name: "AppD", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 105, name: "AppE", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 106, name: "AppF", accumulatedGpuTimeNs: 1_000_000_000)
        ]
        _ = await tracker.sample(rawEntries: initialEntries, limit: 5, now: t0)
        
        // 2 seconds later (dt = 2.0s = 2_000_000_000 ns)
        // Deltas:
        // AppA: +240ms (12.0%)
        // AppB: +1340ms (67.0%)
        // AppC: +620ms (31.0%)
        // AppD: +100ms (5.0%)
        // AppE: +1700ms (85.0%)
        // AppF: +40ms (2.0%)
        let t1 = t0.addingTimeInterval(2.0)
        let secondEntries = [
            RawGpuProcessEntry(pid: 101, name: "AppA", accumulatedGpuTimeNs: 1_240_000_000),
            RawGpuProcessEntry(pid: 102, name: "AppB", accumulatedGpuTimeNs: 2_340_000_000),
            RawGpuProcessEntry(pid: 103, name: "AppC", accumulatedGpuTimeNs: 1_620_000_000),
            RawGpuProcessEntry(pid: 104, name: "AppD", accumulatedGpuTimeNs: 1_100_000_000),
            RawGpuProcessEntry(pid: 105, name: "AppE", accumulatedGpuTimeNs: 2_700_000_000),
            RawGpuProcessEntry(pid: 106, name: "AppF", accumulatedGpuTimeNs: 1_040_000_000)
        ]
        
        let (topGpu, status) = await tracker.sample(rawEntries: secondEntries, limit: 5, now: t1)
        
        XCTAssertEqual(status, .active)
        XCTAssertEqual(topGpu.count, 5, "Should cap at top 5")
        
        // Expected order: AppE (85%), AppB (67%), AppC (31%), AppA (12%), AppD (5%)
        XCTAssertEqual(topGpu[0].name, "AppE")
        XCTAssertEqual(topGpu[0].gpuPercent, 85.0, accuracy: 0.5)
        XCTAssertEqual(topGpu[0].formattedGpu, "85.0%")
        
        XCTAssertEqual(topGpu[1].name, "AppB")
        XCTAssertEqual(topGpu[1].gpuPercent, 67.0, accuracy: 0.5)
        
        XCTAssertEqual(topGpu[2].name, "AppC")
        XCTAssertEqual(topGpu[2].gpuPercent, 31.0, accuracy: 0.5)
        
        XCTAssertEqual(topGpu[3].name, "AppA")
        XCTAssertEqual(topGpu[3].gpuPercent, 12.0, accuracy: 0.5)
        
        XCTAssertEqual(topGpu[4].name, "AppD")
        XCTAssertEqual(topGpu[4].gpuPercent, 5.0, accuracy: 0.5)
    }
    
    func testDeltaCalculationOverInterval() async {
        let tracker = GpuProcessStateTracker(pathForPID: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 2000)
        
        let initial = [
            RawGpuProcessEntry(pid: 201, name: "DaVinci Resolve", accumulatedGpuTimeNs: 5_000_000_000),
            RawGpuProcessEntry(pid: 202, name: "WindowServer", accumulatedGpuTimeNs: 10_000_000_000)
        ]
        _ = await tracker.sample(rawEntries: initial, limit: 5, now: t0)
        
        // 1.5 seconds later (dt = 1.5s = 1_500_000_000 ns)
        // DaVinci: delta = 750_000_000 ns -> 50.0% GPU
        // WindowServer: delta = 300_000_000 ns -> 20.0% GPU
        let t1 = t0.addingTimeInterval(1.5)
        let second = [
            RawGpuProcessEntry(pid: 201, name: "DaVinci Resolve", accumulatedGpuTimeNs: 5_750_000_000),
            RawGpuProcessEntry(pid: 202, name: "WindowServer", accumulatedGpuTimeNs: 10_300_000_000)
        ]
        
        let (topGpu, status) = await tracker.sample(rawEntries: second, limit: 5, now: t1)
        
        XCTAssertEqual(status, .active)
        XCTAssertEqual(topGpu.count, 2)
        XCTAssertEqual(topGpu[0].name, "DaVinci Resolve")
        XCTAssertEqual(topGpu[0].gpuPercent, 50.0, accuracy: 0.5)
        XCTAssertEqual(topGpu[1].name, "WindowServer")
        XCTAssertEqual(topGpu[1].gpuPercent, 20.0, accuracy: 0.5)
    }
    
    func testMultiProcessAggregation() async {
        let tracker = GpuProcessStateTracker(pathForPID: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 3000)
        
        let chromeBundle = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let runningApps: [pid_t: (name: String, bundleURL: URL?)] = [
            301: (name: "Google Chrome", bundleURL: chromeBundle),
            302: (name: "Google Chrome Helper (GPU)", bundleURL: chromeBundle),
            303: (name: "Google Chrome Helper (Renderer)", bundleURL: chromeBundle),
            401: (name: "Terminal", bundleURL: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        ]
        
        let initial = [
            RawGpuProcessEntry(pid: 301, name: "Google Chrome", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 302, name: "Google Chrome Helper", accumulatedGpuTimeNs: 2_000_000_000),
            RawGpuProcessEntry(pid: 303, name: "Google Chrome Helper", accumulatedGpuTimeNs: 500_000_000),
            RawGpuProcessEntry(pid: 401, name: "Terminal", accumulatedGpuTimeNs: 800_000_000)
        ]
        _ = await tracker.sample(rawEntries: initial, runningApps: runningApps, limit: 5, now: t0)
        
        // 2 seconds later (dt = 2.0s)
        // Chrome 301: +100ms (5.0%)
        // Chrome 302: +500ms (25.0%)
        // Chrome 303: +200ms (10.0%)
        // Total Chrome: 40.0% across 3 processes
        // Terminal 401: +300ms (15.0%) across 1 process
        let t1 = t0.addingTimeInterval(2.0)
        let second = [
            RawGpuProcessEntry(pid: 301, name: "Google Chrome", accumulatedGpuTimeNs: 1_100_000_000),
            RawGpuProcessEntry(pid: 302, name: "Google Chrome Helper", accumulatedGpuTimeNs: 2_500_000_000),
            RawGpuProcessEntry(pid: 303, name: "Google Chrome Helper", accumulatedGpuTimeNs: 700_000_000),
            RawGpuProcessEntry(pid: 401, name: "Terminal", accumulatedGpuTimeNs: 1_100_000_000)
        ]
        
        let (topGpu, _) = await tracker.sample(rawEntries: second, runningApps: runningApps, limit: 5, now: t1)
        
        XCTAssertEqual(topGpu.count, 2)
        XCTAssertEqual(topGpu[0].name, "Google Chrome")
        XCTAssertEqual(topGpu[0].bundlePath, "/Applications/Google Chrome.app")
        XCTAssertEqual(topGpu[0].gpuPercent, 40.0, accuracy: 0.5)
        XCTAssertEqual(topGpu[0].processCount, 3)
        
        XCTAssertEqual(topGpu[1].name, "Terminal")
        XCTAssertEqual(topGpu[1].gpuPercent, 15.0, accuracy: 0.5)
        XCTAssertEqual(topGpu[1].processCount, 1)
    }
    
    func testTerminatedPidPruning() async {
        let tracker = GpuProcessStateTracker(pathForPID: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 4000)
        let runningApps: [pid_t: (name: String, bundleURL: URL?)] = [
            99501: (name: "EphemeralWorker", bundleURL: nil),
            99502: (name: "PersistentService", bundleURL: nil)
        ]
        
        let initial = [
            RawGpuProcessEntry(pid: 99501, name: "EphemeralWorker", accumulatedGpuTimeNs: 1_000_000_000),
            RawGpuProcessEntry(pid: 99502, name: "PersistentService", accumulatedGpuTimeNs: 1_000_000_000)
        ]
        _ = await tracker.sample(rawEntries: initial, runningApps: runningApps, limit: 5, now: t0)
        
        // Sample 2: EphemeralWorker active
        let t1 = t0.addingTimeInterval(1.0)
        let sample2 = [
            RawGpuProcessEntry(pid: 99501, name: "EphemeralWorker", accumulatedGpuTimeNs: 1_500_000_000),
            RawGpuProcessEntry(pid: 99502, name: "PersistentService", accumulatedGpuTimeNs: 1_100_000_000)
        ]
        let (top2, _) = await tracker.sample(rawEntries: sample2, runningApps: runningApps, limit: 5, now: t1)
        XCTAssertEqual(top2.count, 2)
        XCTAssertEqual(top2[0].name, "EphemeralWorker")
        
        // Sample 3: EphemeralWorker terminated (disappeared from rawEntries)
        let t2 = t1.addingTimeInterval(1.0)
        let sample3 = [
            RawGpuProcessEntry(pid: 99502, name: "PersistentService", accumulatedGpuTimeNs: 1_200_000_000)
        ]
        let (top3, _) = await tracker.sample(rawEntries: sample3, runningApps: runningApps, limit: 5, now: t2)
        XCTAssertEqual(top3.count, 1)
        XCTAssertEqual(top3[0].name, "PersistentService")
        XCTAssertFalse(top3.contains { $0.name == "EphemeralWorker" })
    }
    
    func testUnavailableStateWhenNoEntries() async {
        let tracker = GpuProcessStateTracker(pathForPID: { _ in nil })
        let (topGpu, status) = await tracker.sample(rawEntries: [], limit: 5, now: Date())
        XCTAssertEqual(status, .unavailable)
        XCTAssertTrue(topGpu.isEmpty)
    }
    
    func testProcessResourceUsageFormatting() {
        let usage = ProcessResourceUsage(
            name: "Final Cut Pro",
            bundlePath: "/Applications/Final Cut Pro.app",
            cpuPercent: 35.4,
            ramBytes: 4 * 1024 * 1024 * 1024,
            gpuPercent: 72.8,
            gpuTimeNs: 15_000_000_000,
            processCount: 2,
            mainPid: 8888
        )
        
        XCTAssertEqual(usage.formattedGpu, "72.8%")
        XCTAssertEqual(usage.formattedCpu, "35.4%")
        XCTAssertEqual(usage.id, "/Applications/Final Cut Pro.app")
        XCTAssertEqual(usage.processCount, 2)
        XCTAssertEqual(usage.mainPid, 8888)
    }
    
    func testLiveRawEntryCollectionDoesNotCrash() {
        let entries = GpuProcessSampler.collectRawEntries()
        // On macOS Apple Silicon or Intel with IOAccelerator, this executes safely
        XCTAssertGreaterThanOrEqual(entries.count, 0)
        for entry in entries {
            XCTAssertGreaterThan(entry.pid, 0)
        }
    }
}
