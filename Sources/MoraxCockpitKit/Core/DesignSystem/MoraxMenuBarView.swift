import SwiftUI
import AppKit

public struct MoraxMenuBarWrenchIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}
    
    public var body: some View {
        if let image = loadWrenchImage(named: iconResourceName) {
            Image(nsImage: image)
                .renderingMode(.original)
        } else {
            Image(systemName: "wrench.adjustable.fill")
        }
    }
    
    private var iconResourceName: String {
        colorScheme == .dark ? "wrench-template-white" : "wrench-template-black"
    }

    private func loadWrenchImage(named resourceName: String) -> NSImage? {
        if let url = MoraxResourceBundle.url(forResource: resourceName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}

public struct MoraxMenuBarLabel: View {
    public var settings: AppSettings
    public var metrics: SystemMetricsService
    public var networkMetrics: NetworkMetricsService
    
    public init(
        settings: AppSettings = .shared,
        metrics: SystemMetricsService = .shared,
        networkMetrics: NetworkMetricsService = .shared
    ) {
        self.settings = settings
        self.metrics = metrics
        self.networkMetrics = networkMetrics
    }
    
    public var body: some View {
        let options = MenuBarReadout.Options(settings: settings)
        // Only the snapshots behind visible readouts are read, so hidden feeds never invalidate the label.
        let readout = MenuBarReadout(
            options: options,
            system: options.needsSystemSnapshot ? metrics.currentSnapshot : nil,
            network: options.showNetwork ? networkMetrics.currentSnapshot : nil
        )
        MenuBarReadoutView(readout: readout)
        .onAppear {
            syncMenuBarDemand()
        }
        .onChange(of: requiredFeeds) { _, _ in
            syncMenuBarDemand()
        }
        .onDisappear {
            if !settings.menuBarEnabled {
                TelemetryCoordinator.shared.release(TelemetryConsumer.menuBarLabel)
            }
        }
    }
    
    private func syncMenuBarDemand() {
        let feeds = requiredFeeds
        if feeds.isEmpty {
            TelemetryCoordinator.shared.release(TelemetryConsumer.menuBarLabel)
        } else {
            TelemetryCoordinator.shared.acquire(TelemetryConsumer.menuBarLabel, feeds: feeds)
        }
    }
    
    /// Feeds this readout needs, given what the user chose to display.
    ///
    /// The label is always on screen, so it keeps its feeds alive on its own; turning
    /// every readout off releases them.
    private var requiredFeeds: Set<TelemetryFeed> {
        guard settings.menuBarEnabled else { return [] }
        var feeds: Set<TelemetryFeed> = []
        if settings.menuBarShowCpu || settings.menuBarShowRam || settings.menuBarShowTemperature
            || settings.menuBarShowDisk || settings.menuBarShowSwapAlert {
            feeds.insert(.system)
        }
        if settings.menuBarShowNetwork {
            feeds.insert(.network)
        }
        return feeds
    }
}

/// Renders a menu bar readout. Equatable so a sample whose rounded values did not
/// change leaves the status item untouched.
private struct MenuBarReadoutView: View, Equatable {
    let readout: MenuBarReadout

    nonisolated static func == (lhs: MenuBarReadoutView, rhs: MenuBarReadoutView) -> Bool {
        lhs.readout == rhs.readout
    }

    var body: some View {
        HStack(spacing: 6) {
            // 1. Icon
            if readout.showsIcon {
                MoraxMenuBarWrenchIcon()
            }
            
            // 2. SWAP Critical Alert Badge
            if readout.showsSwapAlert {
                Text("SWAP")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(MoraxTheme.oxbloodRed)
            }
            
            // 3. CPU Usage
            if let cpu = readout.cpu {
                Text(cpu)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            
            // 4. Memory / RAM Usage
            if let ram = readout.ram {
                Text(ram)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            
            // 5. Network Throughput
            if let network = readout.network {
                Text(network)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            }
            
            // 6. Temperature
            if let temperature = readout.temperature {
                Text(temperature)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            
            // 7. Disk Space
            if let disk = readout.disk {
                Text(disk)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            }
            
            // Fallback if user unchecked literally everything: keep at least wrench icon
            if readout.showsFallbackIcon {
                MoraxMenuBarWrenchIcon()
            }
        }
    }
}

public struct MoraxMenuBarContent: View {
    public var metrics: SystemMetricsService
    public var networkMetrics: NetworkMetricsService
    public var processMetrics: ProcessMetricsService
    public let onOpenMainWindow: () -> Void
    
    public init(
        metrics: SystemMetricsService = .shared,
        networkMetrics: NetworkMetricsService = .shared,
        processMetrics: ProcessMetricsService = .shared,
        onOpenMainWindow: @escaping () -> Void = {}
    ) {
        self.metrics = metrics
        self.networkMetrics = networkMetrics
        self.processMetrics = processMetrics
        self.onOpenMainWindow = onOpenMainWindow
    }
    
    private func formatRate(_ bytesPerSecond: Double) -> String {
        let count = Int64(max(0, bytesPerSecond))
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file) + "/s"
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with Mascot
            HStack(spacing: 10) {
                MoraxMascotView(size: 32)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("MORAX GARAGE")
                        .font(.caption.weight(.black))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text("Uptime: \(metrics.currentSnapshot.uptimeFormatted)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                Spacer()
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Telemetry Quick Stats
            VStack(spacing: 6) {
                MenuBarMetricRow(
                    title: "CPU Active",
                    value: String(format: "%.1f%%", metrics.currentSnapshot.cpuUsage * 100),
                    fraction: metrics.currentSnapshot.cpuUsage,
                    color: MoraxTheme.infoBlue
                )
                
                let memoryColor: Color = {
                    if metrics.currentSnapshot.memoryPressure == .critical {
                        return MoraxTheme.oxbloodRed
                    } else if metrics.currentSnapshot.memoryPressure == .warning {
                        return MoraxTheme.warningAmber
                    } else {
                        return MoraxTheme.infoBlue
                    }
                }()
                
                if let pressure = metrics.currentSnapshot.memory.pressureFraction {
                    MenuBarMetricRow(
                        title: "Pression mémoire",
                        value: String(format: "%.0f%%", pressure * 100),
                        fraction: pressure,
                        color: memoryColor
                    )
                }

                MenuBarMetricRow(
                    title: "Mémoire utilisée",
                    value: "\(metrics.currentSnapshot.memory.formattedUsed) / \(metrics.currentSnapshot.memory.formattedTotal)",
                    fraction: metrics.currentSnapshot.memory.usedFraction,
                    color: memoryColor
                )
                
                MenuBarMetricRow(
                    title: "Swap utilisé",
                    value: ByteCountFormatter.string(fromByteCount: metrics.currentSnapshot.swapUsed, countStyle: .memory),
                    fraction: metrics.currentSnapshot.swapUsedFraction,
                    color: metrics.currentSnapshot.isSwapHigh ? MoraxTheme.oxbloodRed : MoraxTheme.infoBlue
                )
                
                if let primaryVolume = metrics.currentSnapshot.diskVolumes.first {
                    let freeGB = Double(primaryVolume.freeBytes) / (1024.0 * 1024.0 * 1024.0)
                    let deficitGB = max(0.0, min(200.0, 200.0 - freeGB))
                    let deficitFraction = deficitGB / 200.0
                    let isBufferSafe = freeGB >= 200.0
                    let bufferColor: Color = {
                        if deficitGB == 0 {
                            return MoraxTheme.successGreen
                        } else if deficitGB < 100.0 {
                            return MoraxTheme.infoBlue
                        } else if deficitGB < 150.0 {
                            return MoraxTheme.warningAmber
                        } else {
                            return MoraxTheme.oxbloodRed
                        }
                    }()
                    
                    MenuBarMetricRow(
                        title: "Buffer Deficit (200GB)",
                        value: isBufferSafe ? "0 GB (-0) • \(ByteCountFormatter.string(fromByteCount: primaryVolume.freeBytes, countStyle: .file)) Free" : "-\(String(format: "%.1f", deficitGB)) GB (\(String(format: "%.1f", freeGB))/200 GB)",
                        fraction: deficitFraction,
                        color: bufferColor
                    )
                }
            }
            
            Divider()
            
            // Live Network & Top Applications (Visible directly without the main cockpit window)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ACTIVITÉ EN DIRECT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    Spacer()
                    
                    if let ifName = networkMetrics.currentSnapshot.interfaceName {
                        Text(ifName.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                }
                
                // Network Throughput
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .foregroundStyle(Color(hex: "#00C6FF"))
                            .font(.system(size: 8.5, weight: .bold))
                        Text(formatRate(networkMetrics.currentSnapshot.downloadBytesPerSecond))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textPrimary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(Color(hex: "#EC4899"))
                            .font(.system(size: 8.5, weight: .bold))
                        Text(formatRate(networkMetrics.currentSnapshot.uploadBytesPerSecond))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textPrimary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MoraxTheme.surfaceSubtle.opacity(0.5))
                .clipShape(.rect(cornerRadius: 6))
                
                // Top CPU App
                if let topCpu = processMetrics.currentSnapshot.topCpuApps.first {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#FF2E93"))
                            .frame(width: 5, height: 5)
                        Text("CPU: \(topCpu.name)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(MoraxTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(topCpu.formattedCpu)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#FF2E93"))
                    }
                }
                
                // Top RAM App
                if let topRam = processMetrics.currentSnapshot.topRamApps.first {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#A855F7"))
                            .frame(width: 5, height: 5)
                        Text("RAM: \(topRam.name)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(MoraxTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(topRam.formattedRam)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#A855F7"))
                    }
                }
            }
            
            Divider()
            
            // Actions
            Button(action: {
                onOpenMainWindow()
            }) {
                HStack {
                    Image(systemName: "gauge.with.needle.fill")
                    Text("Open Morax Garage...")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            
            Button(action: {
                AppSettings.shared.miniCockpitEnabled.toggle()
                if AppSettings.shared.miniCockpitEnabled {
                    MiniCockpitWindowController.shared.showMiniCockpit(onOpenMainWindow: onOpenMainWindow)
                } else {
                    MiniCockpitWindowController.shared.hideMiniCockpit()
                }
            }) {
                HStack {
                    Image(systemName: "macwindow.on.rectangle")
                    Text(AppSettings.shared.miniCockpitEnabled ? "Masquer le Mini Cockpit" : "Afficher le Mini Cockpit HUD")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit Morax Garage")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            TelemetryCoordinator.shared.acquire(
                TelemetryConsumer.menuBarPopover,
                feeds: [.system, .network, .process]
            )
        }
        .onDisappear {
            TelemetryCoordinator.shared.release(TelemetryConsumer.menuBarPopover)
        }
    }
}

public struct MenuBarMetricRow: View {
    public let title: String
    public let value: String
    public let fraction: Double
    public let color: Color
    
    public init(title: String, value: String, fraction: Double, color: Color) {
        self.title = title
        self.value = value
        self.fraction = fraction
        self.color = color
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            ProgressView(value: min(1.0, max(0.0, fraction)))
                .tint(color)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
    }
}
