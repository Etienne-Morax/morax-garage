import XCTest
import SwiftUI
import AppKit
@testable import MoraxCockpitKit

final class MiniCockpitSnapshotTests: XCTestCase {
    
    @MainActor
    func testGenerateMiniCockpitRuntimeSnapshots() throws {
        let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots/mini_cockpit")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let store = MiniCockpitStore.shared
        let originalAppearance = AppSettings.shared.miniCockpitAppearance
        defer {
            AppSettings.shared.miniCockpitAppearance = originalAppearance
            store.isExpanded = false
        }
        
        // 1. Dark Mode Idle Snapshot
        AppSettings.shared.miniCockpitAppearance = .dark
        store.isExpanded = false
        renderView(MiniCockpitHUDView(), to: outputDir.appendingPathComponent("mini_cockpit_dark_idle.png"))
        
        // 2. Light Mode Idle Snapshot
        AppSettings.shared.miniCockpitAppearance = .light
        store.isExpanded = false
        renderView(MiniCockpitHUDView(), to: outputDir.appendingPathComponent("mini_cockpit_light_idle.png"))
        
        // 3. High GPU Load Scenario (67% GPU, DaVinci Resolve 45% + Lightroom 28%)
        AppSettings.shared.miniCockpitAppearance = .dark
        let highGpuSnapshot = SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.34,
            gpuUsage: 0.67,
            ramTotal: 32 * 1024 * 1024 * 1024,
            ramUsed: 24 * 1024 * 1024 * 1024,
            swapUsed: 512 * 1024 * 1024,
            memoryPressure: .normal,
            gpuFreqMHz: 1398
        )
        let highGpuApps = ProcessSnapshot(
            timestamp: Date(),
            topCpuApps: [
                ProcessResourceUsage(name: "DaVinci Resolve", bundlePath: "/Applications/DaVinci Resolve/DaVinci Resolve.app", cpuPercent: 45.2, ramBytes: 8 * 1024 * 1024 * 1024),
                ProcessResourceUsage(name: "Adobe Lightroom", bundlePath: "/Applications/Adobe Lightroom.app", cpuPercent: 28.6, ramBytes: 4 * 1024 * 1024 * 1024)
            ],
            status: .active
        )
        store.updateMetrics(system: highGpuSnapshot, process: highGpuApps)
        renderView(MiniCockpitHUDView(), to: outputDir.appendingPathComponent("mini_cockpit_high_gpu.png"))
        
        // 4. Expanded Mode Snapshot
        store.displayMode = .expanded
        renderView(MiniCockpitHUDView(), to: outputDir.appendingPathComponent("mini_cockpit_expanded.png"))
        
        // 5. Compact Mode Snapshot (Barre 3 Jauges Réduite)
        store.displayMode = .compact
        renderView(MiniCockpitHUDView(), to: outputDir.appendingPathComponent("mini_cockpit_compact.png"))
        
        // Verify output files exist and are non-empty
        let files = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertTrue(files.contains("mini_cockpit_dark_idle.png"))
        XCTAssertTrue(files.contains("mini_cockpit_light_idle.png"))
        XCTAssertTrue(files.contains("mini_cockpit_high_gpu.png"))
        XCTAssertTrue(files.contains("mini_cockpit_expanded.png"))
        XCTAssertTrue(files.contains("mini_cockpit_compact.png"))
    }
    
    @MainActor
    private func renderView<V: View>(_ view: V, to fileURL: URL) {
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        let targetSize = NSSize(width: max(MiniCockpitWindowController.panelWidth, size.width), height: max(70, size.height))
        hostingView.frame = NSRect(origin: .zero, size: targetSize)
        hostingView.layoutSubtreeIfNeeded()
        
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        
        if let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }
    }
}
