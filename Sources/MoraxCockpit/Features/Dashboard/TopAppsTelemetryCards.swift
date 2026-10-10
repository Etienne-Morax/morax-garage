import SwiftUI
import AppKit
import MoraxCockpitKit

// MARK: - Top CPU Applications Card
public struct TopCpuAppsCard: View {
    public let snapshot: ProcessSnapshot
    @State private var isHovered = false
    
    public init(snapshot: ProcessSnapshot) {
        self.snapshot = snapshot
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(MoraxTheme.neonRose.opacity(0.18))
                            .frame(width: 22, height: 22)
                        Image(systemName: "cpu")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.neonRose)
                    }
                    
                    Text("TOP CHARGE CPU")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                Text("Top 5 · 2s")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
            }
            
            // Content
            switch snapshot.status {
            case .unavailable:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(MoraxTheme.warningAmber)
                        .font(.caption2)
                    Text("Collecte des processus indisponible")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 140)
                
            case .noData:
                if snapshot.topCpuApps.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                        Text("Analyse de la charge CPU...")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 140)
                } else {
                    cpuAppsList
                }
                
            case .active:
                if snapshot.topCpuApps.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(MoraxTheme.successGreen)
                        Text("Aucune activité CPU intense")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 140)
                } else {
                    cpuAppsList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cleanGlassCard(cornerRadius: 14, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var cpuAppsList: some View {
        let maxCpu = max(1.0, snapshot.topCpuApps.first?.cpuPercent ?? 1.0)
        
        return VStack(spacing: 7) {
            ForEach(snapshot.topCpuApps) { app in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        // App Icon
                        AppIconView(app: app)
                        
                        // App Name + Sub-process badge
                        HStack(spacing: 4) {
                            Text(app.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                                .lineLimit(1)
                            
                            if app.processCount > 1 {
                                Text("\(app.processCount)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MoraxTheme.textMuted)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(MoraxTheme.surfaceSubtle.opacity(0.8))
                                    .clipShape(.capsule)
                                    .help("\(app.processCount) sous-processus actifs")
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        Text(app.formattedCpu)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .tabularFigures()
                            .foregroundStyle(MoraxTheme.textPrimary)
                    }
                    
                    // Luminous Gradient Progress Bar
                    GeometryReader { geo in
                        let fraction = min(1.0, max(0.04, app.cpuPercent / maxCpu))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MoraxTheme.surfaceSubtle.opacity(0.4))
                                .frame(height: 3.5)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [MoraxTheme.neonRose, MoraxTheme.cleanOrange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(fraction), height: 3.5)
                                .shadow(color: MoraxTheme.neonRose.opacity(0.35), radius: 2)
                        }
                    }
                    .frame(height: 3.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(app.name), utilisation processeur \(app.formattedCpu)")
            }
        }
    }
}

// MARK: - Top GPU Applications Card
public struct TopGpuAppsCard: View {
    public let snapshot: ProcessSnapshot
    @State private var isHovered = false
    
    public init(snapshot: ProcessSnapshot) {
        self.snapshot = snapshot
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(MoraxTheme.electricCyan.opacity(0.18))
                            .frame(width: 22, height: 22)
                        Image(systemName: "display")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.electricCyan)
                    }
                    
                    Text("TOP CHARGE GPU")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                Text("Top 5 · 2s")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
            }
            
            // Content
            switch snapshot.gpuStatus {
            case .unavailable:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(MoraxTheme.warningAmber)
                        .font(.caption2)
                    Text("Données GPU par application indisponibles")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 140)
                
            case .noData:
                if snapshot.topGpuApps.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                        Text("Analyse de la charge GPU...")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 140)
                } else {
                    gpuAppsList
                }
                
            case .active:
                if snapshot.topGpuApps.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(MoraxTheme.successGreen)
                        Text("Aucune activité GPU intense")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 140)
                } else {
                    gpuAppsList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cleanGlassCard(cornerRadius: 14, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var gpuAppsList: some View {
        let maxGpu = max(1.0, snapshot.topGpuApps.first?.gpuPercent ?? 1.0)
        
        return VStack(spacing: 7) {
            ForEach(snapshot.topGpuApps) { app in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        // App Icon
                        AppIconView(app: app)
                        
                        // App Name + Sub-process badge
                        HStack(spacing: 4) {
                            Text(app.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                                .lineLimit(1)
                            
                            if app.processCount > 1 {
                                Text("\(app.processCount)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MoraxTheme.textMuted)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(MoraxTheme.surfaceSubtle.opacity(0.8))
                                    .clipShape(.capsule)
                                    .help("\(app.processCount) sous-processus actifs")
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        Text(app.formattedGpu)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .tabularFigures()
                            .foregroundStyle(MoraxTheme.textPrimary)
                    }
                    
                    // Luminous Gradient Progress Bar
                    GeometryReader { geo in
                        let fraction = min(1.0, max(0.04, app.gpuPercent / maxGpu))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MoraxTheme.surfaceSubtle.opacity(0.4))
                                .frame(height: 3.5)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [MoraxTheme.electricCyan, MoraxTheme.electricBlue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(fraction), height: 3.5)
                                .shadow(color: MoraxTheme.electricCyan.opacity(0.35), radius: 2)
                        }
                    }
                    .frame(height: 3.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(app.name), utilisation processeur graphique \(app.formattedGpu)")
            }
        }
    }
}
public struct TopRamAppsCard: View {
    public let snapshot: ProcessSnapshot
    @State private var isHovered = false
    
    public init(snapshot: ProcessSnapshot) {
        self.snapshot = snapshot
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#A855F7").opacity(0.18))
                            .frame(width: 22, height: 22)
                        Image(systemName: "memorychip")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#A855F7"))
                    }
                    
                    Text("TOP MÉMOIRE VIVE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                Text("Top 5 · 2s")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
            }
            
            // Content
            switch snapshot.status {
            case .unavailable:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(MoraxTheme.warningAmber)
                        .font(.caption2)
                    Text("Collecte de la mémoire indisponible")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 140)
                
            case .noData:
                if snapshot.topRamApps.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                        Text("Analyse de la mémoire vive...")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 140)
                } else {
                    ramAppsList
                }
                
            case .active:
                if snapshot.topRamApps.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(MoraxTheme.successGreen)
                        Text("Aucune application lourde en mémoire")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 140)
                } else {
                    ramAppsList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cleanGlassCard(cornerRadius: 14, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var ramAppsList: some View {
        let maxRam = max(1.0, Double(snapshot.topRamApps.first?.ramBytes ?? 1))
        
        return VStack(spacing: 7) {
            ForEach(snapshot.topRamApps) { app in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        // App Icon
                        AppIconView(app: app)
                        
                        // App Name + Sub-process badge
                        HStack(spacing: 4) {
                            Text(app.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                                .lineLimit(1)
                            
                            if app.processCount > 1 {
                                Text("\(app.processCount)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MoraxTheme.textMuted)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(MoraxTheme.surfaceSubtle.opacity(0.8))
                                    .clipShape(.capsule)
                                    .help("\(app.processCount) sous-processus actifs")
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        Text(app.formattedRam)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .tabularFigures()
                            .foregroundStyle(MoraxTheme.textPrimary)
                    }
                    
                    // Luminous Gradient Progress Bar
                    GeometryReader { geo in
                        let fraction = min(1.0, max(0.04, Double(app.ramBytes) / maxRam))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MoraxTheme.surfaceSubtle.opacity(0.4))
                                .frame(height: 3.5)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#A855F7"), Color(hex: "#6366F1")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(fraction), height: 3.5)
                                .shadow(color: Color(hex: "#A855F7").opacity(0.4), radius: 2)
                        }
                    }
                    .frame(height: 3.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(app.name), mémoire vive \(app.formattedRam)")
            }
        }
    }
}

// MARK: - App Icon Thumbnail Component
private struct AppIconView: View {
    let app: ProcessResourceUsage
    
    var body: some View {
        let image = ProcessMetricsService.shared.icon(for: app)
        
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(MoraxTheme.surfaceSubtle.opacity(0.6))
                .frame(width: 18, height: 18)
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(.rect(cornerRadius: 3.5))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(MoraxTheme.border.opacity(0.4), lineWidth: 0.5)
        )
    }
}
