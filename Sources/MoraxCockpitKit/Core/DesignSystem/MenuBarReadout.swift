import Foundation

/// Text shown by the always-on menu bar label, derived from one telemetry sample.
///
/// Snapshots change on every sample (timestamp, uptime, sub-percent CPU), but the
/// label only shows rounded values. Comparing readouts lets the label skip
/// re-rendering the status item when what the user sees did not change.
public struct MenuBarReadout: Equatable, Sendable {
    /// Which readouts the user chose to display.
    public struct Options: Equatable, Sendable {
        public var showIcon: Bool
        public var showCpu: Bool
        public var showRam: Bool
        public var showNetwork: Bool
        public var showDisk: Bool
        public var showTemperature: Bool
        public var showSwapAlert: Bool
        public var temperatureUnit: TemperatureUnit

        public init(
            showIcon: Bool,
            showCpu: Bool,
            showRam: Bool,
            showNetwork: Bool,
            showDisk: Bool,
            showTemperature: Bool,
            showSwapAlert: Bool,
            temperatureUnit: TemperatureUnit
        ) {
            self.showIcon = showIcon
            self.showCpu = showCpu
            self.showRam = showRam
            self.showNetwork = showNetwork
            self.showDisk = showDisk
            self.showTemperature = showTemperature
            self.showSwapAlert = showSwapAlert
            self.temperatureUnit = temperatureUnit
        }

        @MainActor
        public init(settings: AppSettings) {
            self.init(
                showIcon: settings.menuBarShowIcon,
                showCpu: settings.menuBarShowCpu,
                showRam: settings.menuBarShowRam,
                showNetwork: settings.menuBarShowNetwork,
                showDisk: settings.menuBarShowDisk,
                showTemperature: settings.menuBarShowTemperature,
                showSwapAlert: settings.menuBarShowSwapAlert,
                temperatureUnit: settings.temperatureUnit
            )
        }

        /// Whether any displayed readout comes from the system snapshot.
        public var needsSystemSnapshot: Bool {
            showCpu || showRam || showDisk || showTemperature || showSwapAlert
        }

        /// Whether every readout, including the icon, is turned off.
        public var isEverythingHidden: Bool {
            !showIcon && !showCpu && !showRam && !showNetwork && !showDisk && !showTemperature && !showSwapAlert
        }
    }

    /// Swap usage above which the label shows the "SWAP" alert.
    public static let swapAlertThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024

    public var showsIcon: Bool
    public var showsSwapAlert: Bool
    public var cpu: String?
    public var ram: String?
    public var network: String?
    public var temperature: String?
    public var disk: String?
    /// Keeps at least the wrench icon when the user turned every readout off.
    public var showsFallbackIcon: Bool

    /// Pass `nil` for a snapshot whose readouts are hidden, so the caller does not observe it.
    public init(options: Options, system: SystemSnapshot?, network: NetworkSnapshot?) {
        showsIcon = options.showIcon
        showsFallbackIcon = options.isEverythingHidden
        showsSwapAlert = options.showSwapAlert && (system?.swapUsed ?? 0) > Self.swapAlertThresholdBytes
        cpu = options.showCpu ? system.map { String(format: "CPU %.0f%%", $0.cpuUsage * 100) } : nil
        ram = options.showRam ? system?.memory.formattedUsed : nil
        self.network = options.showNetwork ? network.map {
            "↓\(Self.formatSpeed($0.downloadBytesPerSecond)) ↑\(Self.formatSpeed($0.uploadBytesPerSecond))"
        } : nil
        temperature = options.showTemperature
            ? system.flatMap { options.temperatureUnit.formatTemperature(celsius: $0.cpuTemp ?? $0.gpuTemp) }
            : nil
        disk = options.showDisk ? system?.diskVolumes.first.map {
            "SSD \(ByteCountFormatter.string(fromByteCount: $0.freeBytes, countStyle: .file))"
        } : nil
    }

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1fM", bytesPerSec / (1024 * 1024))
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0fK", bytesPerSec / 1024)
        } else {
            return "0K"
        }
    }
}
