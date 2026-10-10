import SwiftUI
import MoraxCockpitKit

public struct DashboardView: View {
    @AppStorage("dashboard_show_cockpit_binnacle") private var showCockpitBinnacle: Bool = true
    @AppStorage("dashboard_show_usage_quotas") private var showUsageQuotas: Bool = true
    @AppStorage("morax_higgsfield_monitoring_enabled") private var showHiggsfieldGauge: Bool = true
    @AppStorage("morax_metamuse_monitoring_enabled") private var showMetaMuseGauge: Bool = true
    @State private var usageQuotaService = UsageQuotaService.shared
    @State private var openAICostsService = OpenAICostsService.shared
    @State private var selectedDomainForDetails: AppCacheDomainMetrics? = nil
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Cockpit Header Bar & Status
                CockpitHeaderBar()

                DiagnosticAttentionCard()
                
                // 2. Full Disk Access Banner (if not active)
                FullDiskAccessObserver { hasFullDiskAccess, service in
                    if !hasFullDiskAccess {
                        FullDiskAccessBanner(permissionsService: service)
                    }
                }
                
                // 3. Compteurs Forfaits IA
                if showUsageQuotas {
                    UsageQuotaCard()
                }
                
                // 4. Compteurs DeepSeek API, OpenAI API, Muse Code (Meta) & Higgsfield AI sur la même ligne
                let rawPaidSpends = showUsageQuotas ? (usageQuotaService.cachedSnapshot?.paidApiMonthToDate ?? []) : []
                let paidSpends: [PaidApiSpend] = showUsageQuotas ? {
                    var list = rawPaidSpends
                    if let billed = openAICostsService.spend {
                        list = list.filter { !PaidApiSpend.isOpenAIAPI($0) } + [billed]
                    }
                    let hasOpenAI = list.contains { s in
                        let p = s.provider.lowercased()
                        let l = s.label.lowercased()
                        return p.contains("openai") || l.contains("openai")
                    }
                    if !hasOpenAI {
                        list.append(
                            PaidApiSpend(
                                provider: "openai",
                                label: "OpenAI API",
                                costUsd: 0.0,
                                calls: 0,
                                totalTokens: 0,
                                since: Date(),
                                latestAt: nil,
                                balanceUsd: nil,
                                balanceCurrency: "USD",
                                balanceObservedAt: nil,
                                balanceAvailable: true,
                                balanceSpendUsd: 0.0,
                                balanceSpendSince: nil
                            )
                        )
                    }
                    return list
                }() : []
                let showPaidSpends = !paidSpends.isEmpty
                let showMetaMuse = showMetaMuseGauge
                let showHiggsfield = showHiggsfieldGauge

                if showPaidSpends || showMetaMuse || showHiggsfield {
                    BalancedGrid(minItemWidth: DashboardLayout.creditCardMinWidth, spacing: DashboardLayout.gridSpacing) {
                        if showPaidSpends {
                            ForEach(paidSpends) { spend in
                                PaidSpendCard(spend: spend)
                            }
                        }

                        if showMetaMuse {
                            MetaMuseCreditCard()
                        }

                        if showHiggsfield {
                            HiggsfieldCreditCard()
                        }
                    }
                }
                
                // 5. PANORAMIC INSTRUMENT BINNACLE (Hero Pod: CPU, RAM, Swap, GPU, Puissance, Buffer)
                if showCockpitBinnacle {
                    PanoramicInstrumentBinnacle()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        ))
                }
                
                // 5. Secondary Telemetry Deck: Live Network, Top CPU Apps & Top RAM Apps
                LiveSecondaryDeckSection()

                // 6. Application, Browser & System Cache Gauges Card
                AppAndSystemCacheCard(
                    onInspectDomain: { domain in
                        selectedDomainForDetails = domain
                    }
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(CleanMyMacBackground())
        .sheet(item: $selectedDomainForDetails, content: CacheBreakdownDetailSheet.init)
        // The lease is reference-counted: a rebuilt instance can appear before the old
        // one disappears, and the demand must survive that swap.
        .onAppear { DashboardTelemetryLease.shared.hold(feeds: telemetryFeeds) }
        .onDisappear { DashboardTelemetryLease.shared.drop() }
        .onChange(of: showUsageQuotas) { _, _ in DashboardTelemetryLease.shared.update(feeds: telemetryFeeds) }
        .onChange(of: showHiggsfieldGauge) { _, _ in DashboardTelemetryLease.shared.update(feeds: telemetryFeeds) }
    }

    private var telemetryFeeds: Set<TelemetryFeed> {
        DashboardTelemetryDemand.feeds(showUsageQuotas: showUsageQuotas, showHiggsfield: showHiggsfieldGauge)
    }
}

// MARK: - Layout Metrics
enum DashboardLayout {
    static let gridSpacing: CGFloat = 12
    /// Paid API / credit cards: dial pod (112) + metadata column.
    static let creditCardMinWidth: CGFloat = 270
    static let telemetryCardMinWidth: CGFloat = 230
    static let dialPodMinWidth: CGFloat = 132
    /// Largest diameter a hero dial may take, whatever the column width.
    static let dialMaxDiameter: CGFloat = 140
}

// MARK: - Secondary Telemetry Deck Section
private struct LiveSecondaryDeckSection: View {
    @State private var networkMetrics = NetworkMetricsService.shared
    @State private var processMetrics = ProcessMetricsService.shared
    
    var body: some View {
        BalancedGrid(minItemWidth: DashboardLayout.telemetryCardMinWidth, spacing: DashboardLayout.gridSpacing) {
            NetworkTelemetryCard(snapshot: networkMetrics.currentSnapshot)
            TopCpuAppsCard(snapshot: processMetrics.currentSnapshot)
            TopGpuAppsCard(snapshot: processMetrics.currentSnapshot)
            TopRamAppsCard(snapshot: processMetrics.currentSnapshot)
        }
    }
}

// MARK: - Cockpit Header Bar
private struct CockpitHeaderBar: View {
    private var settings = AppSettings.shared
    @State private var isRefreshing = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Title & Subtitle Section
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("TABLEAU DE BORD")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Text("TÉLÉMÉTRIE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: [MoraxTheme.electricCyan.opacity(0.22), MoraxTheme.neonViolet.opacity(0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(MoraxTheme.electricBlue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(MoraxTheme.electricBlue.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(.rect(cornerRadius: 4))
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                ViewThatFits(in: .horizontal) {
                    Text("Télémétrie système en temps réel & diagnostic de performance")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(1)
                    
                    Text("Télémétrie système en temps réel")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(1)
                    
                    Text("Télémétrie temps réel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(1)
                    
                    EmptyView()
                }
            }
            
            Spacer(minLength: 8)
            
            // Actions & Metrics Cluster (Auto-abbreviating when constrained)
            HStack(spacing: 7) {
                // 1. Live Telemetry Status Pill
                TelemetryStatusPill()
                
                // 2. Toggle Mini Cockpit HUD Floating Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        let newState = !settings.miniCockpitEnabled
                        settings.miniCockpitEnabled = newState
                        if newState {
                            MiniCockpitWindowController.shared.showMiniCockpit(onOpenMainWindow: {
                                MainWindowOpener.shared.open()
                            })
                        } else {
                            MiniCockpitWindowController.shared.hideMiniCockpit()
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: settings.miniCockpitEnabled ? "macwindow.on.rectangle" : "macwindow")
                            .font(.system(size: 10, weight: .bold))
                        
                        ViewThatFits(in: .horizontal) {
                            Text(settings.miniCockpitEnabled ? "Mini Cockpit (Actif)" : "Mini Cockpit")
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .fixedSize()
                            
                            Text(settings.miniCockpitEnabled ? "Mini HUD (Actif)" : "Mini HUD")
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .fixedSize()
                            
                            Text(settings.miniCockpitEnabled ? "HUD" : "HUD")
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .fixedSize()
                            
                            EmptyView()
                        }
                    }
                    .foregroundStyle(settings.miniCockpitEnabled ? MoraxTheme.electricCyan : MoraxTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(settings.miniCockpitEnabled ? MoraxTheme.electricCyan.opacity(0.16) : MoraxTheme.surfaceSubtle.opacity(0.6))
                    .overlay(
                        Capsule()
                            .stroke(settings.miniCockpitEnabled ? MoraxTheme.electricCyan.opacity(0.45) : MoraxTheme.border.opacity(0.6), lineWidth: 1)
                    )
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(settings.miniCockpitEnabled ? "Masquer le Mini Cockpit (HUD Always-On flottant)" : "Activer le Mini Cockpit (HUD Always-On flottant)")
                .fixedSize(horizontal: true, vertical: false)
                
                // 3. Uptime Pill
                UptimePill()
                
                // 4. Refresh Button
                Button(action: {
                    isRefreshing = true
                    Task {
                        await CacheTelemetryService.shared.refreshCacheTelemetry(force: true)
                        await ProcessMetricsService.shared.refreshNow()
                        await HiggsfieldCreditService.shared.refresh()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isRefreshing = false
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.6) : .default, value: isRefreshing)
                        .padding(6)
                        .background(MoraxTheme.surfaceSubtle.opacity(0.7))
                        .overlay(
                            Circle()
                                .stroke(MoraxTheme.border.opacity(0.7), lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Rafraîchir les métriques")
                .fixedSize()
            }
        }
    }
}

/// Header readouts that follow each telemetry sample live in their own views, so a
/// sample only re-renders these pills instead of the whole header bar.
private struct TelemetryStatusPill: View {
    @State private var metrics = SystemMetricsService.shared
    
    private var snapshot: SystemSnapshot {
        metrics.currentSnapshot
    }
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(telemetryBadgeColor(for: snapshot.status))
                .frame(width: 7, height: 7)
                .shadow(color: telemetryBadgeColor(for: snapshot.status).opacity(0.8), radius: 3)
            
            ViewThatFits(in: .horizontal) {
                Text(snapshot.status.statusLabel.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                
                Text(shortStatusLabel(for: snapshot.status))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                
                EmptyView()
            }
            .foregroundStyle(MoraxTheme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(MoraxTheme.surfaceSubtle.opacity(0.6))
        .overlay(
            Capsule()
                .stroke(telemetryBadgeColor(for: snapshot.status).opacity(0.35), lineWidth: 1)
        )
        .clipShape(.capsule)
        .help(snapshot.status.description)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func shortStatusLabel(for status: TelemetryStatus) -> String {
        switch status {
        case .live: return "LIVE"
        case .fallback: return "RELAIS"
        case .unavailable: return "OFF"
        case .error: return "ERR"
        }
    }
    
    private func telemetryBadgeColor(for status: TelemetryStatus) -> Color {
        switch status {
        case .live: return MoraxTheme.successGreen
        case .fallback: return MoraxTheme.warningAmber
        case .unavailable: return MoraxTheme.textMuted
        case .error: return MoraxTheme.neonRose
        }
    }
}

private struct UptimePill: View {
    @State private var metrics = SystemMetricsService.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9))
                .foregroundStyle(MoraxTheme.textSecondary)
            
            Text(metrics.currentSnapshot.uptimeFormatted)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(MoraxTheme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MoraxTheme.surfaceSubtle.opacity(0.6))
        .overlay(
            Capsule()
                .stroke(MoraxTheme.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(.capsule)
        .help("Temps d'activité système")
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Full Disk Access Banner
private struct FullDiskAccessBanner: View {
    var permissionsService: PermissionsService
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MoraxTheme.warningAmber.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "lock.shield")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MoraxTheme.warningAmber)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Accès complet au disque requis")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text("Activez l'accès complet au disque dans les Réglages Système pour permettre l'analyse complète des caches pros et agents de lancement.")
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
            
            Button(action: {
                permissionsService.openAllFilesSettings()
            }) {
                Text("Configurer...")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MoraxTheme.warningAmber)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(MoraxTheme.surfaceSubtle.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MoraxTheme.warningAmber.opacity(0.4), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - PANORAMIC INSTRUMENT BINNACLE
private struct PanoramicInstrumentBinnacle: View {
    @State private var metrics = SystemMetricsService.shared
    var style: CockpitGaugeStyle = .standard
    @State private var isHovered = false
    
    private var snapshot: SystemSnapshot {
        metrics.currentSnapshot
    }
    
    // RAM calculations
    private var ramLoadPercent: Double {
        snapshot.ramLoadFraction * 100
    }
    private var hasKernelPressure: Bool {
        snapshot.memory.pressureFraction != nil
    }
    
    // Swap calculations
    private var swapUsedGB: Double {
        snapshot.memory.swapUsedGB
    }
    private var swapTotalGB: Double {
        max(4.0, ceil(Double(snapshot.memory.swapTotalBytes) / (1024.0 * 1024.0 * 1024.0)))
    }
    
    // Primary Disk Volume calculations (200 GB Headroom Target)
    private var primaryVolume: DiskVolumeInfo? {
        snapshot.diskVolumes.first(where: { !$0.isRemovable }) ?? snapshot.diskVolumes.first
    }
    private var targetFreeBufferGB: Double {
        200.0
    }
    private var primaryVolumeFreeGB: Double {
        guard let vol = primaryVolume else { return 0 }
        return Double(vol.freeBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    private var bufferDeficitGB: Double {
        max(0.0, min(targetFreeBufferGB, targetFreeBufferGB - primaryVolumeFreeGB))
    }
    
    // Gauge Configurations
    private var cpuConfig: AutomotiveGaugeConfig {
        AutomotiveGaugeConfig(
            title: "Charge CPU",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 70,
            criticalThreshold: 90,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 1
        )
    }
    
    private var ramConfig: AutomotiveGaugeConfig {
        AutomotiveGaugeConfig(
            title: hasKernelPressure ? "Pression mémoire" : "Mémoire Vive",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 70,
            criticalThreshold: 85,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 0
        )
    }
    
    private var swapConfig: AutomotiveGaugeConfig {
        AutomotiveGaugeConfig(
            title: "Signal Swap",
            unit: "GB",
            minValue: 0,
            maxValue: swapTotalGB,
            warningThreshold: 1.0,
            criticalThreshold: 2.0,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 2
        )
    }
    
    private var gpuConfig: AutomotiveGaugeConfig {
        AutomotiveGaugeConfig(
            title: "Charge GPU",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 70,
            criticalThreshold: 90,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 1
        )
    }
    
    private var gpuStatusBadge: String {
        let pct = snapshot.gpuUsage * 100
        if pct >= 90 {
            return "Max Load"
        } else if pct >= 70 {
            return "High Load"
        } else {
            return "Normal"
        }
    }
    
    private func formatFrequency(_ mhz: Double) -> String {
        GaugeFormatting.frequency(mhz: mhz)
    }
    
    private var gpuSubtitle: String {
        if let freq = snapshot.gpuFreqMHz {
            if snapshot.gpuPower > 0 {
                return "\(formatFrequency(freq)) • \(String(format: "%.1f W", snapshot.gpuPower))"
            } else {
                return "Fréq. \(formatFrequency(freq))"
            }
        } else if snapshot.gpuPower > 0 {
            return String(format: "%.1f W GPU", snapshot.gpuPower)
        } else {
            return snapshot.isMacmonActive ? "Apple Silicon GPU" : "macmon requis"
        }
    }
    
    private var powerConfig: AutomotiveGaugeConfig {
        AutomotiveGaugeConfig(
            title: "Puissance",
            unit: "W",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 45,
            criticalThreshold: 75,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 1
        )
    }
    
    private var storageConfig: AutomotiveGaugeConfig {
        AutomotiveGaugeConfig(
            title: "Déficit Buffer",
            unit: "GB",
            minValue: 0,
            maxValue: targetFreeBufferGB,
            warningThreshold: 100,
            criticalThreshold: 150,
            majorTicksCount: 4,
            minorTicksPerInterval: 4,
            displayDecimals: 1,
            isInverted: false
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Canopy Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#38BDF8").opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#38BDF8"))
                    }
                    
                    Text("INSTRUMENTS PRINCIPAUX")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                // Live Hardware Badges (Temp & Fans)
                HStack(spacing: 10) {
                    if let temp = snapshot.cpuTemp {
                        HStack(spacing: 5) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 10))
                                .foregroundStyle(temp > 80 ? MoraxTheme.neonRose : Color(hex: "#38BDF8"))
                            Text(AppSettings.shared.formattedTemperature(celsius: temp) ?? String(format: "%.1f°C", temp))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MoraxTheme.surfaceSubtle.opacity(0.6))
                        .clipShape(.capsule)
                    }
                    
                    if let fan = snapshot.fanSpeedRPM {
                        HStack(spacing: 5) {
                            Image(systemName: "fan.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#FF2E93"))
                            Text("\(fan) RPM")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MoraxTheme.surfaceSubtle.opacity(0.6))
                        .clipShape(.capsule)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            Divider()
                .overlay(MoraxTheme.border.opacity(0.6))
                .padding(.horizontal, 14)
            
            // RESPONSIVE HERO GAUGES: 6 across when wide, then 3 + 3, 2 + 2 + 2…
            BalancedGrid(
                minItemWidth: DashboardLayout.dialPodMinWidth,
                maxColumns: 6,
                spacing: 8
            ) {
                dialCards
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .cleanGlassCard(cornerRadius: 16, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var dialCards: some View {
        // DIAL 1: CPU SPEEDO (Neon Rose / Magenta)
        DialPodCard(
            title: "CPU SPEEDO",
            gradientColors: [Color(hex: "#FF2E93"), Color(hex: "#FF758C")],
            footerLeft: "E: \(String(format: "%.0f%%", snapshot.eCpuUsage * 100))",
            footerRight: "P: \(String(format: "%.0f%%", snapshot.pCpuUsage * 100))"
        ) {
            AutomotiveGauge(
                value: snapshot.cpuUsage * 100,
                config: cpuConfig,
                style: style,
                subtitle: snapshot.coreLayoutLabel
            )
        }
        
        // DIAL 2: UNIFIED RAM (Purple / Indigo)
        DialPodCard(
            title: "RAM UNIFIÉE",
            gradientColors: [Color(hex: "#A855F7"), Color(hex: "#6366F1")],
            footerLeft: "Dispo \(snapshot.memory.formattedAvailable)",
            footerRight: "Comp \(snapshot.memory.formattedCompressed)"
        ) {
            AutomotiveGauge(
                value: ramLoadPercent,
                config: ramConfig,
                style: style,
                subtitle: "\(snapshot.memory.formattedUsed) / \(snapshot.memory.formattedTotal)"
            )
            .help("""
            Jauge = pression mémoire réelle (kern.memorystatus_level) : \(String(format: "%.0f%%", ramLoadPercent)).
            macOS remplit la RAM de cache qu'il libère à la demande ; la pression mesure le vrai manque de mémoire.
            Décomposition canonique (Moniteur d'activité) :
            • Mémoire utilisée (RAM physique) : \(snapshot.memory.formattedUsed)
            • Mémoire disponible (réutilisable) : \(snapshot.memory.formattedAvailable)
            • Mémoire compressée : \(snapshot.memory.formattedCompressed)
            • Fichiers en cache (inactive) : \(snapshot.memory.formattedCachedFiles)
            • Mémoire libre : \(snapshot.memory.formattedFree)
            • Swap utilisé : \(snapshot.memory.formattedSwapUsed)
            • Source : \(snapshot.memory.source)
            """)
        }
        
        // DIAL 3: SWAP VM & RESOLVE SIGNAL (Indigo / Fuchsia)
        DialPodCard(
            title: "SWAP SIGNAL",
            gradientColors: snapshot.isSwapHigh ? [Color(hex: "#EF4444"), Color(hex: "#DC2626")] : [Color(hex: "#6366F1"), Color(hex: "#EC4899")],
            footerLeft: snapshot.isSwapHigh ? "Élevé" : (snapshot.swapUsed == 0 ? "Inactif" : "Nominal"),
            footerRight: "\(snapshot.memory.formattedSwapUsed) actif"
        ) {
            AutomotiveGauge(
                value: swapUsedGB,
                config: swapConfig,
                style: style,
                subtitle: snapshot.swapUsed == 0 ? "0 B (OPTIMAL)" : "\(snapshot.memory.formattedSwapUsed) ACTIF"
            )
        }
        
        // DIAL 4: GPU LOAD & FREQUENCY (Cyan / Sky Blue)
        DialPodCard(
            title: "CHARGE GPU",
            gradientColors: [Color(hex: "#00E5FF"), Color(hex: "#38BDF8")],
            footerLeft: snapshot.isMacmonActive ? (snapshot.gpuFreqMHz.map { "Fréq. \(formatFrequency($0))" } ?? "Apple Silicon") : "Standby",
            footerRight: snapshot.isMacmonActive ? (snapshot.gpuPower > 0 ? String(format: "%.1f W", snapshot.gpuPower) : "Nominal") : "Natif"
        ) {
            if snapshot.isMacmonActive {
                AutomotiveGauge(
                    value: snapshot.gpuUsage * 100,
                    config: gpuConfig,
                    style: style,
                    subtitle: gpuSubtitle,
                    statusBadge: gpuStatusBadge
                )
            } else {
                UnavailableGaugePlaceholder(
                    title: "Charge GPU",
                    reason: "macmon requis",
                    iconName: "display",
                    style: style
                )
            }
        }
        
        // DIAL 5: SYSTEM POWER & THERMALS (Coral / Rose)
        DialPodCard(
            title: "PUISSANCE",
            gradientColors: [Color(hex: "#FB923C"), Color(hex: "#F43F5E")],
            footerLeft: snapshot.isMacmonActive ? "CPU: \(String(format: "%.1fW", snapshot.cpuPower))" : "Standby",
            footerRight: snapshot.isMacmonActive ? "GPU: \(String(format: "%.1fW", snapshot.gpuPower))" : "Natif"
        ) {
            if snapshot.isMacmonActive {
                AutomotiveGauge(
                    value: snapshot.systemPower,
                    config: powerConfig,
                    style: style,
                    subtitle: String(format: "%.1f W SYSTÈME", snapshot.systemPower)
                )
            } else {
                UnavailableGaugePlaceholder(
                    title: "Puissance",
                    reason: "macmon requis",
                    iconName: "bolt.slash",
                    style: style
                )
            }
        }
        
        // DIAL 6: 200 GB BUFFER HEADROOM (Cyan / Azure Blue)
        let isBufferTargetMet = bufferDeficitGB == 0
        let bufferColors: [Color] = {
            if bufferDeficitGB == 0 {
                return [Color(hex: "#00E5FF"), Color(hex: "#3B82F6")]
            } else if bufferDeficitGB < 100 {
                return [Color(hex: "#00E5FF"), Color(hex: "#6366F1")]
            } else if bufferDeficitGB < 150 {
                return [Color(hex: "#F59E0B"), Color(hex: "#F43F5E")]
            } else {
                return [Color(hex: "#EF4444"), Color(hex: "#991B1B")]
            }
        }()
        
        DialPodCard(
            title: "BUFFER 200 GB",
            gradientColors: bufferColors,
            footerLeft: primaryVolume?.name ?? "Macintosh HD",
            footerRight: isBufferTargetMet ? "200/200 GB OK" : "\(String(format: "%.1f", primaryVolumeFreeGB))/200 GB"
        ) {
            let subtitleText: String = {
                if isBufferTargetMet {
                    return "\(ByteCountFormatter.string(fromByteCount: primaryVolume?.freeBytes ?? 0, countStyle: .file)) LIBRE"
                } else {
                    return String(format: "%.1f / 200 GB DISPO", primaryVolumeFreeGB)
                }
            }()
            
            AutomotiveGauge(
                value: bufferDeficitGB,
                config: storageConfig,
                style: style,
                subtitle: subtitleText
            )
        }
    }
}

// MARK: - Dial Pod Container Card
private struct DialPodCard<Content: View>: View {
    let title: String
    let gradientColors: [Color]
    let footerLeft: String
    let footerRight: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        title: String,
        gradientColors: [Color],
        footerLeft: String,
        footerRight: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.gradientColors = gradientColors
        self.footerLeft = footerLeft
        self.footerRight = footerRight
        self.content = content()
    }
    
    private var highContrastGradientColors: [Color] {
        if title.contains("CPU") {
            return [Color(hex: "#BE123C"), Color(hex: "#E11D48")]
        } else if title.contains("RAM") {
            return [Color(hex: "#7E22CE"), Color(hex: "#6D28D9")]
        } else if title.contains("SWAP") {
            return footerLeft == "Élevé" ? [Color(hex: "#DC2626"), Color(hex: "#991B1B")] : [Color(hex: "#4338CA"), Color(hex: "#BE185D")]
        } else if title.contains("GPU") {
            return [Color(hex: "#0369A1"), Color(hex: "#0284C7")]
        } else if title.contains("PUISSANCE") {
            return [Color(hex: "#C2410C"), Color(hex: "#BE123C")]
        } else if title.contains("BUFFER") {
            return [Color(hex: "#0369A1"), Color(hex: "#1D4ED8")]
        } else {
            return gradientColors
        }
    }
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 6) {
            // Header Pill
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark ? gradientColors : highContrastGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Gauge Content — capped so dials stay instrument-sized on wide columns
            content
                .frame(maxWidth: DashboardLayout.dialMaxDiameter)
                .frame(maxWidth: .infinity)
            
            // Micro Telemetry Footer
            VStack(spacing: 3) {
                Divider()
                    .overlay(MoraxTheme.border.opacity(0.6))
                
                HStack {
                    Text(footerLeft)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 2)
                    
                    Text(footerRight)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
                .padding(.top, 1)
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isDark ? MoraxTheme.surfaceSubtle.opacity(0.4) : MoraxTheme.surface.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 10))
    }
}



// MARK: - Application, Browser & System Cache Gauges Card
private struct AppAndSystemCacheCard: View {
    @State private var cacheTelemetry = CacheTelemetryService.shared
    let onInspectDomain: (AppCacheDomainMetrics) -> Void
    @State private var isHovered = false
    
    private var snapshot: CacheSnapshot {
        cacheTelemetry.snapshot
    }
    
    private var isScanning: Bool {
        cacheTelemetry.isScanning
    }
    
    private var lastScannedDate: Date? {
        cacheTelemetry.lastScannedDate
    }
    
    private func triggerRefresh() {
        Task {
            await cacheTelemetry.refreshCacheTelemetry(force: true)
        }
    }
    
    private var isHeavyCache: Bool {
        snapshot.grandTotal > 50 * 1024 * 1024 * 1024 // > 50 GB
    }
    
    private var formattedLastScanString: String? {
        guard let date = lastScannedDate else { return nil }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        if calendar.isDateInToday(date) {
            return "Aujourd'hui à \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Hier à \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(MoraxTheme.electricBlue.opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: "cylinder.split.1x2.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.electricBlue)
                    }
                    
                    Text("EMPREINTE DES CACHES APPS & SYSTÈME")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    if isScanning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    
                    if let lastScan = formattedLastScanString {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(MoraxTheme.textMuted)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8.5))
                            Text(lastScan)
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(MoraxTheme.electricBlue)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Text(snapshot.formattedGrandTotal)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tabularFigures()
                            .foregroundStyle(isHeavyCache ? MoraxTheme.warningAmber : MoraxTheme.textPrimary)
                        Text("Caches disque")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                    
                    Button(action: triggerRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                            .rotationEffect(.degrees(isScanning ? 360 : 0))
                            .animation(isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                            .padding(5)
                            .background(MoraxTheme.surfaceSubtle.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanning)
                    .help("Relancer l'analyse du cache maintenant")
                    .accessibilityLabel("Refresh cache telemetry")
                }
            }
            
            // Multi-segment proportional gauge bar
            MultiSegmentCacheBar(snapshot: snapshot, isScanning: isScanning)
            
            // Top Aggregation Metrics Row (Adaptive Clean Glass Pills)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                CacheAggregatePill(
                    title: "Apps Pro",
                    subtitle: "Resolve, LR, PS, C1",
                    value: isScanning && snapshot.controlledAppsTotal == 0 ? "Scan..." : snapshot.formattedControlledAppsTotal,
                    gradientColors: [MoraxTheme.cleanCrimson, MoraxTheme.vividRose],
                    icon: "camera.badge.ellipsis"
                )
                
                CacheAggregatePill(
                    title: "Navigateurs",
                    subtitle: "Safari, Chrome, Arc",
                    value: isScanning && snapshot.browsersSizeBytes == 0 ? "Scan..." : snapshot.formattedBrowsersTotal,
                    gradientColors: [MoraxTheme.electricCyan, MoraxTheme.electricBlue],
                    icon: "globe"
                )
                
                CacheAggregatePill(
                    title: "Système macOS",
                    subtitle: "Caches & Logs",
                    value: isScanning && snapshot.systemSizeBytes == 0 ? "Scan..." : snapshot.formattedSystemTotal,
                    gradientColors: [MoraxTheme.vividPurple, MoraxTheme.deepIndigo],
                    icon: "internaldrive"
                )
            }
            
            Divider()
                .overlay(MoraxTheme.border.opacity(0.6))
            
            // Per-Domain Interactive Gauges Grid (Adaptive columns based on width)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 8)], spacing: 8) {
                ForEach(snapshot.domains) { domain in
                    AppDomainGaugeCard(
                        domain: domain,
                        grandTotal: max(1, snapshot.grandTotal),
                        onInspect: {
                            onInspectDomain(domain)
                        }
                    )
                }
            }
        }
        .padding(14)
        .cleanGlassCard(cornerRadius: 16, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Multi-Segment Cache Bar
private struct MultiSegmentCacheBar: View {
    let snapshot: CacheSnapshot
    var isScanning: Bool = false
    
    private var totalBytes: Int64 {
        max(1, snapshot.grandTotal)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                
                if snapshot.grandTotal == 0 {
                    HStack(spacing: 6) {
                        if isScanning {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Calcul des fichiers de cache sur disque...")
                                .font(.system(size: 9.5))
                                .foregroundStyle(MoraxTheme.textMuted)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(MoraxTheme.surfaceSubtle.opacity(0.5))
                        }
                    }
                    .frame(width: width, height: 9, alignment: .leading)
                } else {
                    HStack(spacing: 2) {
                        ForEach(snapshot.domains.filter { $0.sizeBytes > 0 }) { domain in
                            let fraction = CGFloat(domain.sizeBytes) / CGFloat(totalBytes)
                            let segmentWidth = max(4, fraction * (width - CGFloat(snapshot.domains.count * 2)))
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: domain.accentColorHex))
                                .frame(width: segmentWidth, height: 9)
                                .shadow(color: Color(hex: domain.accentColorHex).opacity(0.4), radius: 2)
                                .help("\(domain.name): \(domain.formattedSize) (\(String(format: "%.1f%%", fraction * 100)))")
                        }
                    }
                    .clipShape(.rect(cornerRadius: 4))
                }
            }
            .frame(height: 9)
            .accessibilityLabel("Proportional cache usage gauge")
            .accessibilityValue(snapshot.formattedGrandTotal)
            
            // Legend
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(snapshot.domains) { domain in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: domain.accentColorHex))
                                .frame(width: 6, height: 6)
                                .shadow(color: Color(hex: domain.accentColorHex).opacity(0.6), radius: 2)
                            
                            Text(domain.shortName)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(MoraxTheme.textSecondary)
                            
                            Text(domain.formattedSize)
                                .font(.system(size: 9.5, design: .monospaced))
                                .tabularFigures()
                                .foregroundStyle(MoraxTheme.textMuted)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Cache Aggregate Pill
private struct CacheAggregatePill: View {
    let title: String
    let subtitle: String
    let value: String
    let gradientColors: [Color]
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .shadow(color: gradientColors.first?.opacity(0.3) ?? .clear, radius: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tabularFigures()
                .foregroundStyle(MoraxTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MoraxTheme.surfaceSubtle.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MoraxTheme.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - App Domain Gauge Card
private struct AppDomainGaugeCard: View {
    let domain: AppCacheDomainMetrics
    let grandTotal: Int64
    let onInspect: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var fraction: Double {
        guard grandTotal > 0 else { return 0 }
        return min(1.0, Double(domain.sizeBytes) / Double(grandTotal))
    }
    
    private var domainAccentColor: Color {
        guard colorScheme == .light else { return Color(hex: domain.accentColorHex) }
        let h = domain.accentColorHex.uppercased()
        if h == "#31A8FF" || h == "#00E5FF" || h == "#38BDF8" {
            return Color(hex: "#0369A1")
        } else if h == "#F59E0B" || h == "#FB923C" {
            return Color(hex: "#B45309")
        } else if h == "#A855F7" || h == "#8B5CF6" {
            return Color(hex: "#7E22CE")
        } else if h == "#FF2E93" || h == "#EC4899" {
            return Color(hex: "#BE123C")
        } else {
            return Color(hex: domain.accentColorHex)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(domainAccentColor.opacity(0.18))
                        .frame(width: 18, height: 18)
                    Image(systemName: domain.iconName)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(domainAccentColor)
                }
                
                Text(domain.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                
                Spacer(minLength: 2)
                
                Text(domain.formattedSize)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tabularFigures()
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Button(action: onInspect) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Détails du cache \(domain.name)")
            }
            
            // Progress Bar + Stats
            HStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MoraxTheme.border.opacity(0.5))
                            .frame(height: 3.5)
                        
                        Capsule()
                            .fill(domainAccentColor)
                            .frame(width: max(3, geo.size.width * CGFloat(fraction)), height: 3.5)
                            .shadow(color: domainAccentColor.opacity(0.4), radius: 2)
                    }
                }
                .frame(height: 3.5)
                
                HStack(spacing: 3) {
                    Text(String(format: "%.1f%%", fraction * 100))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    Text("•")
                        .font(.system(size: 6))
                        .foregroundStyle(MoraxTheme.textMuted)
                    
                    Text("\(domain.items.count) réc")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(MoraxTheme.surfaceSubtle.opacity(isHovered ? 0.7 : 0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? domainAccentColor.opacity(0.4) : MoraxTheme.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Cache Breakdown Detail Sheet
private struct CacheBreakdownDetailSheet: View {
    let domain: AppCacheDomainMetrics
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: domain.accentColorHex).opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: domain.iconName)
                            .font(.title2)
                            .foregroundStyle(Color(hex: domain.accentColorHex))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(domain.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        Text("Détail des répertoires et caches identifiés")
                            .font(.caption)
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                Text(domain.formattedSize)
                    .font(.title2.weight(.bold))
                    .tabularFigures()
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Divider()
                .overlay(MoraxTheme.border.opacity(0.6))
            
            // List of items
            if domain.items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(MoraxTheme.successGreen)
                    Text("Aucun fichier de cache encombrant détecté pour \(domain.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(domain.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            
                            Spacer()
                            
                            Text(item.formattedSize)
                                .font(.caption.weight(.bold))
                                .tabularFigures()
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                        
                        Text(item.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(MoraxTheme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            
            // Footer
            HStack {
                Text("\(domain.items.count) élément(s) détecté(s). Nettoyable via l'onglet Espace & Nettoyage.")
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Text("Fermer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#00E5FF"), Color(hex: "#FF2E93")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(MoraxTheme.surfaceSubtle.opacity(0.6))
        }
        .frame(minWidth: 540, minHeight: 400)
        .background(CleanMyMacBackground())
    }
}

#Preview("Cockpit Dashboard") {
    DashboardView()
        .frame(width: 1080, height: 850)
}
