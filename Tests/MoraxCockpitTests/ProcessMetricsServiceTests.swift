import XCTest
import AppKit
@testable import MoraxCockpitKit

final class ProcessMetricsServiceTests: XCTestCase {
    
    func testExtractAppBundleURL() {
        // App inside /Applications
        let path1 = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/151.0.7922.138/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let bundle1 = ProcessResourceSampler.extractAppBundleURL(from: path1)
        XCTAssertEqual(bundle1?.path, "/Applications/Google Chrome.app")
        
        // App root
        let path2 = "/Applications/Notion.app/Contents/MacOS/Notion"
        let bundle2 = ProcessResourceSampler.extractAppBundleURL(from: path2)
        XCTAssertEqual(bundle2?.path, "/Applications/Notion.app")
        
        // System Cryptex Safari
        let path3 = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari"
        let bundle3 = ProcessResourceSampler.extractAppBundleURL(from: path3)
        XCTAssertEqual(bundle3?.path, "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
        
        // Non-bundle system daemon
        let path4 = "/usr/sbin/coreaudiod"
        let bundle4 = ProcessResourceSampler.extractAppBundleURL(from: path4)
        XCTAssertNil(bundle4)
    }
    
    func testParsePsOutputAggregatesHelpersAndRanksCorrectly() {
        let samplePs = """
          PID  %CPU    RSS COMM
          402  50.0 100000 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
         1001  20.0 500000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
         1002  30.0 800000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1.0/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper
         2001  80.0 200000 /Applications/Xcode.app/Contents/MacOS/Xcode
         3001   5.5 1500000 /Applications/Notion.app/Contents/MacOS/Notion
        """
        
        let (topCpu, topRam) = ProcessResourceSampler.parsePsOutput(samplePs, limit: 5)
        
        // Xcode: 80.0% CPU
        // Google Chrome: 20.0 + 30.0 = 50.0% CPU (2 processes aggregated!)
        // WindowServer: 50.0% CPU
        // Notion: 5.5% CPU
        
        XCTAssertEqual(topCpu.count, 4)
        XCTAssertEqual(topCpu[0].name, "Xcode")
        XCTAssertEqual(topCpu[0].cpuPercent, 80.0, accuracy: 0.1)
        
        // Find Google Chrome in CPU list
        let chromeCpu = topCpu.first { $0.bundlePath == "/Applications/Google Chrome.app" }
        XCTAssertNotNil(chromeCpu)
        XCTAssertEqual(chromeCpu?.cpuPercent ?? 0, 50.0, accuracy: 0.1)
        XCTAssertEqual(chromeCpu?.processCount, 2)
        XCTAssertEqual(chromeCpu?.ramBytes, (500000 + 800000) * 1024)
        
        // Check Top RAM
        // Notion: 1500000 KB = ~1.5 GB
        // Google Chrome: 1300000 KB = ~1.3 GB
        // Xcode: 200000 KB = ~200 MB
        // WindowServer: 100000 KB = ~100 MB
        XCTAssertEqual(topRam.count, 4)
        XCTAssertEqual(topRam[0].name, "Notion")
        XCTAssertEqual(topRam[0].ramBytes, 1500000 * 1024)
        XCTAssertEqual(topRam[1].bundlePath, "/Applications/Google Chrome.app")
        XCTAssertEqual(topRam[1].ramBytes, 1300000 * 1024)
    }
    
    func testFormattingHelpers() {
        let usage = ProcessResourceUsage(
            name: "Safari",
            bundlePath: "/Applications/Safari.app",
            cpuPercent: 12.34,
            ramBytes: 1024 * 1024 * 1024,
            processCount: 3,
            mainPid: 1234
        )
        
        XCTAssertEqual(usage.formattedCpu, "12.3%")
        XCTAssertFalse(usage.formattedRam.isEmpty)
        XCTAssertEqual(usage.id, "/Applications/Safari.app")
    }
    
    @MainActor
    func testServiceLifecycle() {
        let service = ProcessMetricsService.shared
        XCTAssertNotNil(service.currentSnapshot)
        
        service.startMonitoring()
        XCTAssertTrue(service.isRunning)
        
        service.stopMonitoring()
        XCTAssertFalse(service.isRunning)
    }
    
    func testProcessSnapshotWithGpuApps() {
        let gpuApp = ProcessResourceUsage(
            name: "Blender",
            bundlePath: "/Applications/Blender.app",
            cpuPercent: 10.0,
            ramBytes: 2 * 1024 * 1024 * 1024,
            gpuPercent: 68.5,
            gpuTimeNs: 10_000_000_000,
            processCount: 1,
            mainPid: 9999
        )
        
        let snapshot = ProcessSnapshot(
            timestamp: Date(),
            topCpuApps: [],
            topRamApps: [],
            topGpuApps: [gpuApp],
            status: .active,
            gpuStatus: .active
        )
        
        XCTAssertEqual(snapshot.topGpuApps.count, 1)
        XCTAssertEqual(snapshot.topGpuApps[0].name, "Blender")
        XCTAssertEqual(snapshot.topGpuApps[0].formattedGpu, "68.5%")
        XCTAssertEqual(snapshot.gpuStatus, .active)
    }
}
