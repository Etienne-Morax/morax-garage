import SwiftUI
import AppKit

/// Vue principale du HUD miniature Always-On "Mini Cockpit" au design Liquid Glass macOS.
/// Propose des tuiles modulaires pour GPU, RAM, CPU, applications actives et quotas IA,
/// avec un rendu adaptatif en Dark Mode et Light Mode.
public struct MiniCockpitHUDView: View {
    @State private var store = MiniCockpitStore.shared
    @State private var quotaService = UsageQuotaService.shared
    @State private var openAICostsService = OpenAICostsService.shared
    @State private var higgsfieldService = HiggsfieldCreditService.shared
    private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    @State private var isHovered = false
    
    public let onOpenMainWindow: () -> Void
    public let onClose: () -> Void
    
    public init(
        onOpenMainWindow: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.onOpenMainWindow = onOpenMainWindow
        self.onClose = onClose
    }
    
    // MARK: - Effective Appearance
    private var isDarkMode: Bool {
        switch settings.miniCockpitAppearance {
        case .system:
            return systemColorScheme == .dark
        case .dark:
            return true
        case .light:
            return false
        }
    }
    
    // MARK: - Adaptive Theme Tokens
    private var textPrimary: Color {
        isDarkMode ? Color(hex: "#F8FAFC") : Color(hex: "#0F172A")
    }
    
    private var textSecondary: Color {
        isDarkMode ? Color(hex: "#94A3B8") : Color(hex: "#475569")
    }
    
    private var textMuted: Color {
        isDarkMode ? Color(hex: "#64748B") : Color(hex: "#64748B")
    }
    
    private var dividerColor: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
    
    public var body: some View {
        VStack(spacing: 5) {
            // 1. Header Bar (Brand, Status & Controls)
            headerRow
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 1)
            
            // 2. Glance Level (Ligne des 3 jauges CPU, GPU, RAM + Top Apps + Quotas IA)
            glanceSection
                .padding(.horizontal, 8)
                .padding(.bottom, store.isCompact ? 6 : (store.isExpanded ? 0 : 7))
            
            // 3. Detail Level (Déplié sur demande)
            if store.isExpanded {
                Divider()
                    .overlay(dividerColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                
                expandedDetailsSection
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: MiniCockpitWindowController.panelWidth)
        .miniCockpitLiquidGlass(
            cornerRadius: 16,
            isDarkMode: isDarkMode,
            isHovered: isHovered,
            reduceTransparency: reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isHovered ? 1.0 : 0.94)
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onOpenMainWindow()
        }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            contextMenuItems
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Morax Mini Cockpit HUD Liquid Glass")
    }
    
    // MARK: - Header Row
    private var headerRow: some View {
        HStack(spacing: 6) {
            // Mini Brand Icon / Mascot
            MoraxMenuBarWrenchIcon()
                .frame(width: 13, height: 13)
            
            Text("MORAX")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(textPrimary)
            
            Spacer()
            
            // SWAP Critical Warning Badge
            if store.currentSnapshot.isSwapHigh {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text("SWAP")
                        .font(.system(size: 8.5, weight: .black))
                }
                .foregroundStyle(isDarkMode ? MoraxTheme.oxbloodRed : Color(hex: "#DC2626"))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(isDarkMode ? MoraxTheme.oxbloodRed.opacity(0.18) : Color(hex: "#FEE2E2"))
                .clipShape(.rect(cornerRadius: 3.5))
                .accessibilityLabel("Alerte swap mémoire élevé")
            }
            
            // Health Status Pill
            let healthColor = store.healthState.color(isDark: isDarkMode)
            HStack(spacing: 4) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 5.5, height: 5.5)
                
                Text(store.healthState.label)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(healthColor)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(healthColor.opacity(isDarkMode ? 0.15 : 0.12))
            .clipShape(.capsule)
            .accessibilityLabel(store.healthState.accessibilityDescription)
            
            // Expand / Collapse Chevron Button (Redimensionne véritablement la fenêtre)
            Button(action: {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
                    if store.isCompact {
                        store.displayMode = .standard
                    } else if store.isExpanded {
                        store.displayMode = .standard
                    } else {
                        store.displayMode = .compact
                    }
                }
            }) {
                Image(systemName: store.isCompact ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isHovered ? textPrimary : textSecondary)
            }
            .buttonStyle(.plain)
            .help(store.isCompact ? "Déplier en mode standard" : "Réduire véritablement la fenêtre en mode compact")
            .accessibilityLabel(store.isCompact ? "Déplier en mode standard" : "Réduire la fenêtre en mode compact")
            
            // Close / Hide Button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isHovered ? textSecondary : textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Masquer le Mini Cockpit")
        }
    }
    
    // MARK: - Glance Section (Ligne des 3 Jauges CPU, GPU, RAM + Top Apps + Quotas IA)
    private var glanceSection: some View {
        VStack(spacing: 5) {
            // Ligne 1 : Trio de micro-jauges système (CPU, GPU et RAM côte à côte)
            HStack(spacing: 5) {
                cpuMetricTile
                gpuMetricTile
                ramMetricTile
            }
            
            if !store.isCompact {
                // Ligne 2 : Tuiles Top Applications (DaVinci, Lightroom, Photoshop, Terminal, etc.)
                topAppsRow
                
                // Ligne 3 : Compteurs IA (Claude, ChatGPT, Gemini, OpenAI API, Higgsfield)
                aiCountersRow
            }
        }
    }
    
    // MARK: - CPU Metric Tile
    private var cpuMetricTile: some View {
        let cpuFraction = store.currentSnapshot.cpuUsage
        let cpuPct = cpuFraction * 100
        let isUnavail = store.currentSnapshot.status.isUnavailable
        
        let cpuAccent: Color = isDarkMode
            ? (cpuPct >= 85 ? MoraxTheme.oxbloodRed : (cpuPct >= 70 ? MoraxTheme.warningAmber : MoraxTheme.electricCyan))
            : (cpuPct >= 85 ? Color(hex: "#DC2626") : (cpuPct >= 70 ? Color(hex: "#D97706") : Color(hex: "#0284C7")))
        
        let totalCores = store.currentSnapshot.pCoreCount + store.currentSnapshot.eCoreCount
        let secText = totalCores > 0 ? "\(totalCores) Coeurs" : (cpuPct >= 1 ? "Actif" : "Repos")
        
        return MiniMetricTile(
            iconName: "cpu",
            title: "CPU",
            valueText: isUnavail ? "--" : String(format: "%.0f%%", cpuPct),
            fraction: cpuFraction,
            secondaryText: secText,
            accentColor: cpuAccent,
            isDarkMode: isDarkMode,
            isUnavailable: isUnavail,
            gaugeType: .arc()
        )
    }
    
    // MARK: - GPU Metric Tile
    private var gpuMetricTile: some View {
        let gpuFraction = store.currentSnapshot.gpuUsage
        let gpuPct = gpuFraction * 100
        let isUnavail = store.currentSnapshot.status.isUnavailable
        
        let gpuAccent: Color = isDarkMode
            ? (gpuPct >= 85 ? MoraxTheme.oxbloodRed : (gpuPct >= 70 ? MoraxTheme.warningAmber : MoraxTheme.electricCyan))
            : (gpuPct >= 85 ? Color(hex: "#DC2626") : (gpuPct >= 70 ? Color(hex: "#D97706") : Color(hex: "#0284C7")))
        
        let secText = store.currentSnapshot.gpuFreqMHz.map { "\(Int($0)) MHz" }
            ?? (gpuPct >= 1 ? "Actif" : "Repos")
        
        return MiniMetricTile(
            iconName: "gauge.with.dots.needle.bottom.50percent",
            title: "GPU",
            valueText: isUnavail ? "--" : String(format: "%.0f%%", gpuPct),
            fraction: gpuFraction,
            secondaryText: secText,
            accentColor: gpuAccent,
            isDarkMode: isDarkMode,
            isUnavailable: isUnavail,
            gaugeType: .arc()
        )
    }
    
    // MARK: - RAM Metric Tile
    private var ramMetricTile: some View {
        let ramFraction = store.currentSnapshot.ramLoadFraction
        let ramPct = ramFraction * 100
        let pressure = store.currentSnapshot.memoryPressure
        let isUnavail = store.currentSnapshot.status.isUnavailable
        
        let ramAccent: Color = isDarkMode
            ? (pressure == .critical ? MoraxTheme.oxbloodRed : (pressure == .warning ? MoraxTheme.warningAmber : MoraxTheme.infoBlue))
            : (pressure == .critical ? Color(hex: "#DC2626") : (pressure == .warning ? Color(hex: "#D97706") : Color(hex: "#2563EB")))
        
        let secText = store.currentSnapshot.memory.formattedUsed
        
        let customGrad: LinearGradient = isDarkMode
            ? (pressure == .critical
               ? LinearGradient(colors: [MoraxTheme.warningAmber, MoraxTheme.oxbloodRed], startPoint: .topLeading, endPoint: .bottomTrailing)
               : (pressure == .warning
                  ? LinearGradient(colors: [MoraxTheme.electricCyan, MoraxTheme.warningAmber], startPoint: .topLeading, endPoint: .bottomTrailing)
                  : LinearGradient(colors: [MoraxTheme.infoBlue, Color(hex: "#38BDF8")], startPoint: .topLeading, endPoint: .bottomTrailing)))
            : (pressure == .critical
               ? LinearGradient(colors: [Color(hex: "#D97706"), Color(hex: "#DC2626")], startPoint: .topLeading, endPoint: .bottomTrailing)
               : (pressure == .warning
                  ? LinearGradient(colors: [Color(hex: "#0284C7"), Color(hex: "#D97706")], startPoint: .topLeading, endPoint: .bottomTrailing)
                  : LinearGradient(colors: [Color(hex: "#2563EB"), Color(hex: "#38BDF8")], startPoint: .topLeading, endPoint: .bottomTrailing)))
        
        return MiniMetricTile(
            iconName: "memorychip",
            title: "RAM",
            valueText: isUnavail ? "--" : String(format: "%.0f%%", ramPct),
            fraction: ramFraction,
            secondaryText: secText,
            accentColor: ramAccent,
            isDarkMode: isDarkMode,
            isUnavailable: isUnavail,
            gaugeType: .arc(gradient: customGrad)
        )
    }
    
    // MARK: - Top Monitored Apps Row (Tuiles avec Icônes réelles macOS)
    private var topAppsRow: some View {
        let apps = store.topMonitoredApps
        
        return HStack(spacing: 5) {
            if apps.isEmpty {
                // État au repos
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDarkMode ? MoraxTheme.successGreen : Color(hex: "#059669"))
                    Text("Aucun processus intensif")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .miniTileGlass(cornerRadius: 8, isDarkMode: isDarkMode)
            } else if apps.count == 1, let first = apps.first {
                MiniAppUsageTile(
                    appName: first.name,
                    bundlePath: first.bundlePath,
                    metricLabel: "CPU",
                    metricValue: first.formattedCpu,
                    fraction: min(1.0, first.cpuPercent / 100.0),
                    accentColor: isDarkMode ? MoraxTheme.cleanRose : Color(hex: "#E11D48"),
                    isDarkMode: isDarkMode
                )
                
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(textMuted)
                    Text("Système stable")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .miniTileGlass(cornerRadius: 8, isDarkMode: isDarkMode)
            } else {
                // Top 2 Applications avec logos réels
                ForEach(apps.prefix(2)) { app in
                    MiniAppUsageTile(
                        appName: app.name,
                        bundlePath: app.bundlePath,
                        metricLabel: "CPU",
                        metricValue: app.formattedCpu,
                        fraction: min(1.0, app.cpuPercent / 100.0),
                        accentColor: isDarkMode ? MoraxTheme.cleanRose : Color(hex: "#E11D48"),
                        isDarkMode: isDarkMode
                    )
                }
            }
        }
    }
    
    // MARK: - AI Counters Row (Claude, ChatGPT, Gemini, OpenAI API, Higgsfield)
    private var aiCountersRow: some View {
        let billedOpenAI = openAICostsService.spend
        let baseSnapshot = quotaService.cachedSnapshot
            ?? billedOpenAI.map { _ in UsageQuotaSnapshot(ok: true, capturedAt: quotaService.currentDate, gauges: [], paidApiMonthToDate: []) }
        let aiItems = MiniAICounterItem.resolveItems(
            from: baseSnapshot?.replacingOpenAISpend(billedOpenAI),
            higgsfieldService: higgsfieldService,
            at: quotaService.currentDate
        )
        
        return HStack(spacing: 4) {
            ForEach(aiItems) { item in
                MiniAICounterCard(item: item, isDarkMode: isDarkMode)
            }
        }
    }
    
    // MARK: - Expanded Details Section
    private var expandedDetailsSection: some View {
        VStack(spacing: 5) {
            // CPU & GPU Sparklines Row
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HISTORIQUE CPU")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(textSecondary)
                    
                    MiniSparklineView(
                        values: store.cpuSparkline.values,
                        strokeColor: isDarkMode ? MoraxTheme.electricCyan : Color(hex: "#0284C7"),
                        fillColor: (isDarkMode ? MoraxTheme.electricCyan : Color(hex: "#0284C7")).opacity(0.2)
                    )
                    .frame(height: 14)
                }
                .padding(5)
                .miniTileGlass(cornerRadius: 6, isDarkMode: isDarkMode)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("HISTORIQUE GPU")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(textSecondary)
                    
                    MiniSparklineView(
                        values: store.gpuSparkline.values,
                        strokeColor: isDarkMode ? MoraxTheme.vividPurple : Color(hex: "#7C3AED"),
                        fillColor: (isDarkMode ? MoraxTheme.vividPurple : Color(hex: "#7C3AED")).opacity(0.2)
                    )
                    .frame(height: 14)
                }
                .padding(5)
                .miniTileGlass(cornerRadius: 6, isDarkMode: isDarkMode)
            }
            
            // Swap & Temperature Row
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                        .foregroundStyle(textMuted)
                    Text("Swap: \(ByteCountFormatter.string(fromByteCount: store.currentSnapshot.swapUsed, countStyle: .memory))")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(store.currentSnapshot.isSwapHigh ? (isDarkMode ? MoraxTheme.oxbloodRed : Color(hex: "#DC2626")) : textSecondary)
                }
                
                Spacer()
                
                if let temp = store.currentSnapshot.cpuTemp ?? store.currentSnapshot.gpuTemp,
                   let formattedTemp = settings.temperatureUnit.formatTemperature(celsius: temp) {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 8))
                            .foregroundStyle(textMuted)
                        Text(formattedTemp)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(textSecondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            
            // Button to open full Cockpit
            let buttonBg = isDarkMode ? MoraxTheme.infoBlue.opacity(0.18) : Color(hex: "#EFF6FF")
            let buttonFg = isDarkMode ? MoraxTheme.infoBlue : Color(hex: "#1D4ED8")
            let buttonBorder = isDarkMode ? MoraxTheme.infoBlue.opacity(0.35) : Color(hex: "#BFDBFE")
            
            Button(action: onOpenMainWindow) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 9))
                    Text("Ouvrir Morax Garage")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(buttonBg)
                .foregroundStyle(buttonFg)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(buttonBorder, lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }
    
    // MARK: - Context Menu
    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Ouvrir Morax Garage") {
            onOpenMainWindow()
        }
        
        Divider()
        
        // Display Mode Selector
        Menu {
            Button(action: {
                withAnimation {
                    store.displayMode = .compact
                }
            }) {
                HStack {
                    Text("Mode Compact (3 jauges)")
                    if store.displayMode == .compact {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Button(action: {
                withAnimation {
                    store.displayMode = .standard
                }
            }) {
                HStack {
                    Text("Mode Standard (Jauges + Apps + IA)")
                    if store.displayMode == .standard {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Button(action: {
                withAnimation {
                    store.displayMode = .expanded
                }
            }) {
                HStack {
                    Text("Mode Détaillé (Graphiques & Historique)")
                    if store.displayMode == .expanded {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label("Mode d'affichage", systemImage: "macwindow")
        }
        
        // Appearance Switcher
        Menu {
            Button(action: { settings.miniCockpitAppearance = .system }) {
                HStack {
                    Text("Automatique (Système)")
                    if settings.miniCockpitAppearance == .system {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Button(action: { settings.miniCockpitAppearance = .light }) {
                HStack {
                    Text("Mode Clair")
                    if settings.miniCockpitAppearance == .light {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Button(action: { settings.miniCockpitAppearance = .dark }) {
                HStack {
                    Text("Mode Sombre")
                    if settings.miniCockpitAppearance == .dark {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label("Thème d'apparence", systemImage: settings.miniCockpitAppearance.iconName)
        }
        
        Divider()
        
        Button(action: {
            settings.miniCockpitAlwaysOnTop.toggle()
            MiniCockpitWindowController.shared.applyAlwaysOnTop(settings.miniCockpitAlwaysOnTop)
        }) {
            HStack {
                Text("Toujours au premier plan")
                if settings.miniCockpitAlwaysOnTop {
                    Image(systemName: "checkmark")
                }
            }
        }
        
        Button(action: {
            settings.miniCockpitAllSpaces.toggle()
            MiniCockpitWindowController.shared.applyAllSpaces(settings.miniCockpitAllSpaces)
        }) {
            HStack {
                Text("Afficher sur tous les Spaces")
                if settings.miniCockpitAllSpaces {
                    Image(systemName: "checkmark")
                }
            }
        }
        
        Divider()
        
        Button("Masquer le Mini Cockpit") {
            onClose()
        }
        
        Button("Quitter Morax Garage") {
            NSApplication.shared.terminate(nil)
        }
    }
}
