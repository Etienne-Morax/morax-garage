import SwiftUI
import MoraxCockpitKit

public enum GarageNavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case photoSync = "Sync Photos"
    case storageMap = "Storage Map"
    case cleanup = "Cleanup & Cache"
    case aiModels = "Modèles IA"
    case apps = "Applications"
    case audit = "Persistence Audit"
    case environment = "Environment"
    case settings = "Réglages"
    case permissions = "Permissions"
    case terminal = "Mole Terminal"
    case brew = "Homebrew"
    case demo = "Mode Démo & Guide"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "gauge.with.needle.fill"
        case .photoSync: return "photo.stack.fill"
        case .storageMap: return "square.grid.3x3.square"
        case .cleanup: return "trash.fill"
        case .aiModels: return "brain"
        case .apps: return "app.badge.fill"
        case .audit: return "shield.lefthalf.filled"
        case .environment: return "wrench.and.screwdriver.fill"
        case .settings: return "gearshape.fill"
        case .permissions: return "lock.shield.fill"
        case .terminal: return "terminal.fill"
        case .brew: return "mug.fill"
        case .demo: return "sparkles"
        }
    }
    
    public var gradientColors: [Color] {
        switch self {
        case .dashboard:
            return [MoraxTheme.electricCyan, MoraxTheme.neonViolet] // Vibrant Blue-Violet Signature
        case .photoSync:
            return [Color(hex: "#F59E0B"), Color(hex: "#EC4899")]
        case .storageMap:
            return [Color(hex: "#38BDF8"), Color(hex: "#6366F1")]
        case .cleanup:
            return [Color(hex: "#10B981"), Color(hex: "#059669")]
        case .aiModels:
            return [Color(hex: "#14B8A6"), Color(hex: "#0EA5E9")]
        case .apps:
            return [Color(hex: "#EC4899"), Color(hex: "#8B5CF6")]
        case .audit:
            return [Color(hex: "#F43F5E"), Color(hex: "#BE123C")]
        case .environment:
            return [Color(hex: "#8B5CF6"), Color(hex: "#3B82F6")]
        case .settings:
            return [Color(hex: "#6366F1"), Color(hex: "#A855F7")]
        case .permissions:
            return [Color(hex: "#F59E0B"), Color(hex: "#F43F5E")]
        case .terminal:
            return [Color(hex: "#00E5FF"), Color(hex: "#10B981")]
        case .brew:
            return [Color(hex: "#FB923C"), Color(hex: "#F59E0B")]
        case .demo:
            return [Color(hex: "#FF2E93"), Color(hex: "#8B5CF6")]
        }
    }
}

public struct GarageNavSection: Identifiable {
    public let id: String
    public let title: String
    public let items: [GarageNavigationItem]
}

public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedItem: GarageNavigationItem? = .dashboard
    @State private var selectedSettingsSubTab: SettingsSubTab = .general
    @AppStorage("morax_appearance_mode") private var appearanceMode: AppAppearanceMode = .system
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    private let navSections: [GarageNavSection] = [
        GarageNavSection(
            id: "overview",
            title: "VUE D'ENSEMBLE",
            items: [.dashboard]
        ),
        GarageNavSection(
            id: "client_projects",
            title: "PROJETS CLIENTS",
            items: [.photoSync]
        ),
        GarageNavSection(
            id: "storage",
            title: "ESPACE & NETTOYAGE",
            items: [.storageMap, .cleanup, .aiModels]
        ),
        GarageNavSection(
            id: "apps_system",
            title: "APPLICATIONS & SYSTÈME",
            items: [.apps, .audit, .environment]
        )
    ]
    
    public init() {}
    
    private var isSettingsSelected: Bool {
        guard let item = selectedItem else { return false }
        return item == .settings || item == .permissions || item == .terminal || item == .brew || item == .demo
    }
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                // Sidebar Brand Header (Clean Modern style with Blue-Rose badge)
                HStack(spacing: 12) {
                    MoraxMascotView(size: 38)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("MORAX")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(MoraxTheme.textPrimary)
                                .fixedSize()
                            
                            Text("GARAGE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    LinearGradient(
                                        colors: [MoraxTheme.electricCyan.opacity(0.20), MoraxTheme.neonViolet.opacity(0.18)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(MoraxTheme.electricBlue)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(MoraxTheme.electricBlue.opacity(0.4), lineWidth: 1)
                                )
                                .clipShape(.rect(cornerRadius: 3))
                        }
                        
                        Text("Mac Maintenance Suite")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
                
                Divider()
                    .overlay(MoraxTheme.border.opacity(0.6))
                    .padding(.horizontal, 12)
                
                // Grouped Clean Navigation Sections
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(navSections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                // Section Header
                                Text(section.title)
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MoraxTheme.textSecondary.opacity(0.75))
                                    .padding(.horizontal, 14)
                                    .padding(.top, 4)
                                    .padding(.bottom, 2)
                                
                                ForEach(section.items) { item in
                                    CleanMyMacNavRow(
                                        item: item,
                                        isSelected: selectedItem == item
                                    ) {
                                        navigateTo(item: item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                
                Divider()
                    .overlay(MoraxTheme.border.opacity(0.6))
                    .padding(.horizontal, 12)
                
                // Bottom Settings Dock & Appearance
                VStack(spacing: 8) {
                    // Settings Button with vibrant gear squircle tile
                    FullDiskAccessObserver { hasFullDiskAccess, _ in
                        CleanMyMacSettingsRow(
                            isSelected: isSettingsSelected,
                            badgeText: hasFullDiskAccess ? nil : "VÉRIF",
                            badgeColor: MoraxTheme.warningAmber
                        ) {
                            navigateTo(item: .settings)
                        }
                    }
                    
                    // Compact Appearance Switcher
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textSecondary)
                        
                        // Label drops out rather than wrapping letter by letter when narrow.
                        ViewThatFits(in: .horizontal) {
                            Text("Thème")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .fixedSize()
                            Color.clear.frame(width: 0, height: 0)
                        }
                        
                        Spacer(minLength: 0)
                        
                        Picker("", selection: $appearanceMode) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.mini)
                        .frame(maxWidth: 120)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
            .frame(minWidth: 220)
            .background(
                ZStack {
                    VisualEffectBackdrop(
                        material: .sidebar,
                        blendingMode: .behindWindow,
                        state: .active,
                        cornerRadius: 0
                    )
                    MoraxTheme.sidebarBackground.opacity(0.70)
                }
            )
        } detail: {
            NavigationStack {
                tabView(for: effectiveTab(for: selectedItem))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CleanMyMacBackground())
            }
        }
        .background(WindowLiquidGlassConfigurator())
        .preferredColorScheme(appearanceMode.colorScheme)
        .navigationTitle("Morax Garage")
        .modifier(HiddenWindowTitle())
        .onReceive(NotificationCenter.default.publisher(for: .moraxNavigateToTab)) { notification in
            if let targetItem = notification.object as? GarageNavigationItem {
                navigateTo(item: targetItem)
            }
        }
    }
    
    private func effectiveTab(for item: GarageNavigationItem?) -> GarageNavigationItem {
        guard let item = item else { return .dashboard }
        switch item {
        case .permissions, .terminal, .brew, .demo, .settings:
            return .settings
        default:
            return item
        }
    }
    
    private func navigateTo(item: GarageNavigationItem) {
        switch item {
        case .permissions:
            selectedSettingsSubTab = .permissions
            selectedItem = .settings
        case .terminal:
            selectedSettingsSubTab = .terminal
            selectedItem = .settings
        case .brew:
            selectedSettingsSubTab = .brew
            selectedItem = .settings
        case .demo:
            selectedSettingsSubTab = .demo
            selectedItem = .settings
        case .settings:
            selectedItem = .settings
        default:
            selectedItem = item
        }
    }
    
    @ViewBuilder
    private func tabView(for item: GarageNavigationItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView()
        case .photoSync:
            PhotoSyncView()
        case .storageMap:
            StorageMapView()
        case .cleanup:
            CleanupView()
        case .aiModels:
            AIModelsView()
        case .apps:
            AppsView()
        case .audit:
            AuditView()
        case .environment:
            EnvironmentView()
        case .settings, .permissions, .terminal, .brew, .demo:
            SettingsView(selectedSubTab: $selectedSettingsSubTab) { targetItem in
                navigateTo(item: targetItem)
            }
        }
    }
}

// MARK: - Blue-Rose Navigation Row
private struct CleanMyMacNavRow: View {
    let item: GarageNavigationItem
    let isSelected: Bool
    var badgeText: String? = nil
    var badgeColor: Color = MoraxTheme.warningAmber
    let onSelect: () -> Void
    @State private var isHovered = false
    
    private func settingsTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
            .foregroundStyle(MoraxTheme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private func settingsSubtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(MoraxTheme.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Active Left Indicator Pill with Blue-Rose Neon Glow
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#00E5FF"), Color(hex: "#FF2E93")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: 18)
                    .shadow(color: isSelected ? Color(hex: "#FF2E93").opacity(0.8) : .clear, radius: 4)
                    .opacity(isSelected ? 1 : 0)
                
                // Vibrant Squircle Icon Tile
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: item.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(
                            color: isSelected ? item.gradientColors.first?.opacity(0.5) ?? .clear : .clear,
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                    
                    Image(systemName: item.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                
                // Label
                Text(item.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isSelected ? MoraxTheme.textPrimary : (isHovered ? MoraxTheme.textPrimary : MoraxTheme.textSecondary))
                
                Spacer()
                
                if let badge = badgeText {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(badgeColor.opacity(0.2))
                        .foregroundStyle(badgeColor)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                        ? LinearGradient(
                            colors: [MoraxTheme.electricCyan.opacity(0.14), MoraxTheme.neonViolet.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : (isHovered ? LinearGradient(colors: [MoraxTheme.surfaceSubtle.opacity(0.6), MoraxTheme.surfaceSubtle.opacity(0.4)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .leading, endPoint: .trailing))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? MoraxTheme.electricBlue.opacity(0.35) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Blue-Violet Settings Row
private struct CleanMyMacSettingsRow: View {
    let isSelected: Bool
    var badgeText: String? = nil
    var badgeColor: Color = MoraxTheme.warningAmber
    let onSelect: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    private func settingsTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
            .foregroundStyle(MoraxTheme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private func settingsSubtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(MoraxTheme.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Active Left Indicator Pill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [MoraxTheme.electricCyan, MoraxTheme.neonViolet],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: 18)
                    .shadow(color: isSelected ? MoraxTheme.neonViolet.opacity(0.6) : .clear, radius: 4)
                    .opacity(isSelected ? 1 : 0)
                
                // Gear Squircle Tile
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                ? [MoraxTheme.electricCyan, MoraxTheme.neonViolet]
                                : (colorScheme == .dark ? [Color(hex: "#2B2857"), Color(hex: "#1E1A40")] : [Color(hex: "#E2E8F0"), Color(hex: "#CBD5E1")]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(
                            color: isSelected ? MoraxTheme.electricCyan.opacity(0.4) : .clear,
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colorScheme == .dark || isSelected ? Color.white : MoraxTheme.textSecondary)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    // Shorter labels win over "Réglages…" truncation in a narrow sidebar.
                    ViewThatFits(in: .horizontal) {
                        settingsTitle("Réglages & Outils")
                        settingsTitle("Réglages")
                    }

                    ViewThatFits(in: .horizontal) {
                        settingsSubtitle("Permissions • Terminal • Brew • Démo")
                        settingsSubtitle("Permissions • Outils")
                        settingsSubtitle("Permissions")
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

                if let badge = badgeText {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .black))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor)
                        .foregroundStyle(Color.black)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                        ? LinearGradient(
                            colors: [MoraxTheme.electricCyan.opacity(0.14), MoraxTheme.neonViolet.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : (isHovered ? LinearGradient(colors: [MoraxTheme.surfaceSubtle.opacity(0.6), MoraxTheme.surfaceSubtle.opacity(0.4)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [MoraxTheme.surface.opacity(0.3), MoraxTheme.surface.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? MoraxTheme.electricBlue.opacity(0.35) : MoraxTheme.border.opacity(0.6),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Native Liquid Glass Window Configurator
/// Configures the hosting window once per window attachment and hands it to the
/// dashboard's visibility gate.
///
/// The configuration used to be re-applied from `updateNSView`, which scheduled a
/// main-queue hop on every SwiftUI update of `RootView`. The window only needs it when
/// the view joins a window, so the work now hangs off `viewDidMoveToWindow`.
private struct WindowLiquidGlassConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowAttachmentView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowAttachmentView: NSView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window, window !== newWindow {
            WindowVisibilityTelemetryGate.dashboard.untrack(window)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Pause the dashboard feeds while this window is minimized, hidden or covered.
        WindowVisibilityTelemetryGate.dashboard.track(window)
        Self.applyLiquidGlass(to: window)
        // SwiftUI finishes configuring a new window after attaching its content, so
        // apply once more on the next turn to win over that initial setup.
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            Self.applyLiquidGlass(to: window)
        }
    }

    private static func applyLiquidGlass(to window: NSWindow) {
        if window.isOpaque {
            window.isOpaque = false
        }
        if window.backgroundColor != .clear {
            window.backgroundColor = .clear
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
    }
}

#Preview("Morax Garage Main App") {
    RootView()
        .frame(width: 1080, height: 750)
}

/// The transparent titlebar lets detail content scroll underneath it, so the
/// window title ended up drawn on top of dashboard cards. The sidebar already
/// carries the brand, so the title text is removed from the toolbar (it stays
/// the window's name for the Window menu and Mission Control).
private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
