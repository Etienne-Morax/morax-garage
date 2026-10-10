import Foundation
import SwiftUI
import AppKit
import ServiceManagement
import Observation

public enum UpdateCheckFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case silent = "Silencieux"
    case onLaunch = "Au lancement"
    case daily = "Quotidien"
    case weekly = "Hebdomadaire"
    case disabled = "Désactivé"
    
    public var id: String { rawValue }
}

public enum TemperatureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "Système"
    case celsius = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"
    case kelvin = "Kelvin (K)"
    
    public var id: String { rawValue }
    
    public func formatTemperature(celsius: Double?) -> String? {
        guard let c = celsius else { return nil }
        switch self {
        case .celsius:
            return String(format: "%.0f°C", c)
        case .fahrenheit:
            let f = (c * 9.0 / 5.0) + 32.0
            return String(format: "%.0f°F", f)
        case .kelvin:
            let k = c + 273.15
            return String(format: "%.0f K", k)
        case .system:
            let usesMetric = Locale.current.measurementSystem == .metric
            if usesMetric {
                return String(format: "%.0f°C", c)
            } else {
                let f = (c * 9.0 / 5.0) + 32.0
                return String(format: "%.0f°F", f)
            }
        }
    }
}

public enum AppAppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "Système"
    case light = "Clair"
    case dark = "Sombre"
    
    public var id: String { rawValue }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()
    
    @ObservationIgnored
    private let defaults: UserDefaults
    
    // Keys
    /// Defaults key for the menu bar master switch, exposed so the app scene can bind
    /// to it with `@AppStorage` without observing this object at App scope.
    public static let menuBarEnabledKey = Keys.menuBarEnabled

    private enum Keys {
        static let showDockIcon = "morax_show_dock_icon"
        static let launchAtLogin = "morax_launch_at_login"
        static let updateCheckFrequency = "morax_update_check_frequency"
        static let temperatureUnit = "morax_temperature_unit"
        static let keepMenuBarPosition = "morax_keep_menubar_position"
        static let macosWidgetsEnabled = "morax_macos_widgets_enabled"
        
        // Mini Cockpit HUD items
        static let miniCockpitEnabled = "morax_mini_cockpit_enabled"
        static let miniCockpitAlwaysOnTop = "morax_mini_cockpit_always_on_top"
        static let miniCockpitAllSpaces = "morax_mini_cockpit_all_spaces"
        static let miniCockpitExpanded = "morax_mini_cockpit_expanded"
        static let miniCockpitAppearance = "morax_mini_cockpit_appearance"
        
        // Menu bar display items
        static let menuBarEnabled = "morax_menubar_enabled"
        static let menuBarShowIcon = "morax_menubar_show_icon"
        static let menuBarShowCpu = "morax_menubar_show_cpu"
        static let menuBarShowRam = "morax_menubar_show_ram"
        static let menuBarShowNetwork = "morax_menubar_show_network"
        static let menuBarShowDisk = "morax_menubar_show_disk"
        static let menuBarShowTemperature = "morax_menubar_show_temperature"
        static let menuBarShowSwapAlert = "morax_menubar_show_swap_alert"

        // AI usage quota bridge
        static let usageCockpitBaseURL = "morax_usage_cockpit_base_url"
        static let usageQuotasEnabled = "dashboard_show_usage_quotas"
        
        // Higgsfield AI Credits Monitoring
        static let higgsfieldMonitoringEnabled = "morax_higgsfield_monitoring_enabled"

        // Meta Muse Code local activity counter
        static let metamuseMonitoringEnabled = "morax_metamuse_monitoring_enabled"
        static let metamuseProjectID = "morax_metamuse_project_id"
        static let metamuseTeamID = "morax_metamuse_team_id"
    }
    
    public var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            applyDockVisibility()
        }
    }
    
    public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }
    
    public var updateCheckFrequency: UpdateCheckFrequency {
        didSet {
            defaults.set(updateCheckFrequency.rawValue, forKey: Keys.updateCheckFrequency)
        }
    }
    
    public var temperatureUnit: TemperatureUnit {
        didSet {
            defaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit)
        }
    }
    
    public var keepMenuBarPosition: Bool {
        didSet {
            defaults.set(keepMenuBarPosition, forKey: Keys.keepMenuBarPosition)
        }
    }
    
    public var macosWidgetsEnabled: Bool {
        didSet {
            defaults.set(macosWidgetsEnabled, forKey: Keys.macosWidgetsEnabled)
        }
    }
    
    // Mini Cockpit HUD Properties
    public var miniCockpitEnabled: Bool {
        didSet {
            defaults.set(miniCockpitEnabled, forKey: Keys.miniCockpitEnabled)
        }
    }
    
    public var miniCockpitAlwaysOnTop: Bool {
        didSet {
            defaults.set(miniCockpitAlwaysOnTop, forKey: Keys.miniCockpitAlwaysOnTop)
        }
    }
    
    public var miniCockpitAllSpaces: Bool {
        didSet {
            defaults.set(miniCockpitAllSpaces, forKey: Keys.miniCockpitAllSpaces)
        }
    }
    
    public var miniCockpitExpanded: Bool {
        didSet {
            defaults.set(miniCockpitExpanded, forKey: Keys.miniCockpitExpanded)
        }
    }
    
    public var miniCockpitAppearance: AppAppearanceMode {
        didSet {
            defaults.set(miniCockpitAppearance.rawValue, forKey: Keys.miniCockpitAppearance)
        }
    }
    
    // Menu Bar Items
    /// Master switch for the menu bar item itself. The `menuBarShow*` flags below
    /// only pick what the item displays, so without this the item cannot be removed.
    public var menuBarEnabled: Bool {
        didSet { defaults.set(menuBarEnabled, forKey: Keys.menuBarEnabled) }
    }

    public var menuBarShowIcon: Bool {
        didSet { defaults.set(menuBarShowIcon, forKey: Keys.menuBarShowIcon) }
    }
    
    public var menuBarShowCpu: Bool {
        didSet { defaults.set(menuBarShowCpu, forKey: Keys.menuBarShowCpu) }
    }
    
    public var menuBarShowRam: Bool {
        didSet { defaults.set(menuBarShowRam, forKey: Keys.menuBarShowRam) }
    }
    
    public var menuBarShowNetwork: Bool {
        didSet { defaults.set(menuBarShowNetwork, forKey: Keys.menuBarShowNetwork) }
    }
    
    public var menuBarShowDisk: Bool {
        didSet { defaults.set(menuBarShowDisk, forKey: Keys.menuBarShowDisk) }
    }
    
    public var menuBarShowTemperature: Bool {
        didSet { defaults.set(menuBarShowTemperature, forKey: Keys.menuBarShowTemperature) }
    }
    
    public var menuBarShowSwapAlert: Bool {
        didSet { defaults.set(menuBarShowSwapAlert, forKey: Keys.menuBarShowSwapAlert) }
    }

    public var usageCockpitBaseURL: String {
        didSet { defaults.set(usageCockpitBaseURL, forKey: Keys.usageCockpitBaseURL) }
    }

    public var usageQuotasEnabled: Bool {
        didSet { defaults.set(usageQuotasEnabled, forKey: Keys.usageQuotasEnabled) }
    }

    public var higgsfieldMonitoringEnabled: Bool {
        didSet { defaults.set(higgsfieldMonitoringEnabled, forKey: Keys.higgsfieldMonitoringEnabled) }
    }

    public var metamuseMonitoringEnabled: Bool {
        didSet { defaults.set(metamuseMonitoringEnabled, forKey: Keys.metamuseMonitoringEnabled) }
    }

    public var metamuseProjectID: String {
        didSet { defaults.set(metamuseProjectID, forKey: Keys.metamuseProjectID) }
    }

    public var metamuseTeamID: String {
        didSet { defaults.set(metamuseTeamID, forKey: Keys.metamuseTeamID) }
    }

    public var metamuseUsageURL: URL? {
        MetaMuseUsagePage.url(projectID: metamuseProjectID, teamID: metamuseTeamID)
    }

    public var usageCockpitURL: URL? {
        let trimmed = usageCockpitBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        // Defaults registration
        if defaults.object(forKey: Keys.showDockIcon) == nil {
            self.showDockIcon = true
        } else {
            self.showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
        }
        
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        
        if let freqRaw = defaults.string(forKey: Keys.updateCheckFrequency),
           let freq = UpdateCheckFrequency(rawValue: freqRaw) {
            self.updateCheckFrequency = freq
        } else {
            self.updateCheckFrequency = .silent
        }
        
        if let unitRaw = defaults.string(forKey: Keys.temperatureUnit),
           let unit = TemperatureUnit(rawValue: unitRaw) {
            self.temperatureUnit = unit
        } else {
            self.temperatureUnit = .system
        }
        
        if defaults.object(forKey: Keys.keepMenuBarPosition) == nil {
            self.keepMenuBarPosition = true
        } else {
            self.keepMenuBarPosition = defaults.bool(forKey: Keys.keepMenuBarPosition)
        }
        
        if defaults.object(forKey: Keys.macosWidgetsEnabled) == nil {
            self.macosWidgetsEnabled = true
        } else {
            self.macosWidgetsEnabled = defaults.bool(forKey: Keys.macosWidgetsEnabled)
        }
        
        // Mini Cockpit Defaults
        self.miniCockpitEnabled = defaults.bool(forKey: Keys.miniCockpitEnabled)
        
        if defaults.object(forKey: Keys.miniCockpitAlwaysOnTop) == nil {
            self.miniCockpitAlwaysOnTop = true
        } else {
            self.miniCockpitAlwaysOnTop = defaults.bool(forKey: Keys.miniCockpitAlwaysOnTop)
        }
        
        if defaults.object(forKey: Keys.miniCockpitAllSpaces) == nil {
            self.miniCockpitAllSpaces = true
        } else {
            self.miniCockpitAllSpaces = defaults.bool(forKey: Keys.miniCockpitAllSpaces)
        }
        
        self.miniCockpitExpanded = defaults.bool(forKey: Keys.miniCockpitExpanded)
        
        if let appRaw = defaults.string(forKey: Keys.miniCockpitAppearance),
           let mode = AppAppearanceMode(rawValue: appRaw) {
            self.miniCockpitAppearance = mode
        } else {
            self.miniCockpitAppearance = .system
        }
        
        // Menu Bar Items Defaults
        if defaults.object(forKey: Keys.menuBarEnabled) == nil {
            self.menuBarEnabled = true
        } else {
            self.menuBarEnabled = defaults.bool(forKey: Keys.menuBarEnabled)
        }

        if defaults.object(forKey: Keys.menuBarShowIcon) == nil {
            self.menuBarShowIcon = true
        } else {
            self.menuBarShowIcon = defaults.bool(forKey: Keys.menuBarShowIcon)
        }
        
        if defaults.object(forKey: Keys.menuBarShowCpu) == nil {
            self.menuBarShowCpu = true
        } else {
            self.menuBarShowCpu = defaults.bool(forKey: Keys.menuBarShowCpu)
        }
        
        self.menuBarShowRam = defaults.bool(forKey: Keys.menuBarShowRam)
        self.menuBarShowNetwork = defaults.bool(forKey: Keys.menuBarShowNetwork)
        self.menuBarShowDisk = defaults.bool(forKey: Keys.menuBarShowDisk)
        self.menuBarShowTemperature = defaults.bool(forKey: Keys.menuBarShowTemperature)
        
        if defaults.object(forKey: Keys.menuBarShowSwapAlert) == nil {
            self.menuBarShowSwapAlert = true
        } else {
            self.menuBarShowSwapAlert = defaults.bool(forKey: Keys.menuBarShowSwapAlert)
        }

        self.usageCockpitBaseURL = defaults.string(forKey: Keys.usageCockpitBaseURL)
            ?? ProcessInfo.processInfo.environment["MORAX_USAGE_COCKPIT_BASE_URL"]
            ?? ""
        if defaults.object(forKey: Keys.usageQuotasEnabled) == nil {
            self.usageQuotasEnabled = true
        } else {
            self.usageQuotasEnabled = defaults.bool(forKey: Keys.usageQuotasEnabled)
        }
        
        if defaults.object(forKey: Keys.higgsfieldMonitoringEnabled) == nil {
            self.higgsfieldMonitoringEnabled = true
        } else {
            self.higgsfieldMonitoringEnabled = defaults.bool(forKey: Keys.higgsfieldMonitoringEnabled)
        }

        if defaults.object(forKey: Keys.metamuseMonitoringEnabled) == nil {
            self.metamuseMonitoringEnabled = true
        } else {
            self.metamuseMonitoringEnabled = defaults.bool(forKey: Keys.metamuseMonitoringEnabled)
        }

        self.metamuseProjectID = defaults.string(forKey: Keys.metamuseProjectID)
            ?? ProcessInfo.processInfo.environment["MORAX_METAMUSE_PROJECT_ID"]
            ?? ""
        self.metamuseTeamID = defaults.string(forKey: Keys.metamuseTeamID)
            ?? ProcessInfo.processInfo.environment["MORAX_METAMUSE_TEAM_ID"]
            ?? ""
    }
    
    public func applyDockVisibility() {
        guard let app = NSApp ?? (NSApplication.shared as NSApplication?) else { return }
        if showDockIcon {
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
        } else {
            app.setActivationPolicy(.accessory)
            for window in app.windows where window.isVisible {
                window.orderFrontRegardless()
            }
        }
    }
    
    public func syncLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                self.launchAtLogin = true
            }
        }
    }
    
    public func applyLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                // Ignore service errors during development/unsigned test environments
            }
        }
    }
    
    public func formattedTemperature(celsius: Double?) -> String? {
        temperatureUnit.formatTemperature(celsius: celsius)
    }
}
