import SwiftUI
import MoraxCockpitKit

public struct NetworkTelemetryCard: View {
    public let snapshot: NetworkSnapshot
    @State private var isHovered = false
    
    public init(snapshot: NetworkSnapshot) {
        self.snapshot = snapshot
    }
    
    private func formatRate(_ bytesPerSecond: Double) -> String {
        let count = Int64(max(0, bytesPerSecond))
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file) + "/s"
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(MoraxTheme.infoBlue.opacity(0.18))
                            .frame(width: 22, height: 22)
                        Image(systemName: "network")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.infoBlue)
                    }
                    
                    Text("RÉSEAU LIVE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                if let ifName = snapshot.interfaceName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MoraxTheme.successGreen)
                            .frame(width: 5.5, height: 5.5)
                            .shadow(color: MoraxTheme.successGreen.opacity(0.6), radius: 2.5)
                        
                        Text(ifName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textPrimary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(MoraxTheme.surfaceSubtle.opacity(0.6))
                    .clipShape(.capsule)
                } else {
                    Text("Inactif")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                }
            }
            
            // Global Rates: 2 Clean Glass Tiles
            HStack(spacing: 6) {
                // Download Tile (Cyan -> Blue)
                NetworkRateTile(
                    title: "Download",
                    rateString: formatRate(snapshot.downloadBytesPerSecond),
                    icon: "arrow.down.circle.fill",
                    gradientColors: [MoraxTheme.electricCyan, MoraxTheme.electricBlue],
                    accessibilityLabel: "Débit descendant global: \(formatRate(snapshot.downloadBytesPerSecond))"
                )
                
                // Upload Tile (Purple -> Fuchsia)
                NetworkRateTile(
                    title: "Upload",
                    rateString: formatRate(snapshot.uploadBytesPerSecond),
                    icon: "arrow.up.circle.fill",
                    gradientColors: [MoraxTheme.vividPurple, MoraxTheme.hotPink],
                    accessibilityLabel: "Débit montant global: \(formatRate(snapshot.uploadBytesPerSecond))"
                )
            }
            
            Divider()
                .overlay(MoraxTheme.border.opacity(0.5))
            
            // Top 3 Applications Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Applications (trafic intervalle)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    Spacer()
                    
                    Text("Top 3 · 2s")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                
                switch snapshot.topApplicationsStatus {
                case .unavailable:
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(MoraxTheme.warningAmber)
                            .font(.caption2)
                        Text("Collecte indisponible")
                            .font(.caption2)
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 60)
                    
                case .noData:
                    if snapshot.topApplications.isEmpty {
                        VStack(spacing: 4) {
                            Spacer()
                            ProgressView()
                                .controlSize(.mini)
                            Text("Collecte du premier intervalle en cours...")
                                .font(.system(size: 9.5))
                                .foregroundStyle(MoraxTheme.textMuted)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 60)
                    } else {
                        topApplicationsList
                    }
                    
                case .active:
                    if snapshot.topApplications.isEmpty {
                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(MoraxTheme.successGreen)
                            Text("Aucun trafic applicatif détecté")
                                .font(.system(size: 9.5))
                                .foregroundStyle(MoraxTheme.textMuted)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 60)
                    } else {
                        topApplicationsList
                    }
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
    
    private var topApplicationsList: some View {
        let maxRate = max(1.0, snapshot.topApplications.first?.totalBytesPerSecond ?? 1.0)
        
        return VStack(spacing: 5) {
            ForEach(snapshot.topApplications) { app in
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack {
                        Text(app.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(Color(hex: "#00C6FF"))
                                Text(formatRate(app.downloadBytesPerSecond))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tabularFigures()
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                            
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(Color(hex: "#EC4899"))
                                Text(formatRate(app.uploadBytesPerSecond))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tabularFigures()
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                        }
                    }
                    
                    // Luminous Gradient Proportion Bar
                    GeometryReader { geo in
                        let fraction = min(1.0, max(0.03, app.totalBytesPerSecond / maxRate))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(MoraxTheme.surfaceSubtle.opacity(0.4))
                                .frame(height: 3)
                            
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(
                                    LinearGradient(
                                        colors: [MoraxTheme.electricCyan, MoraxTheme.hotPink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(fraction), height: 3)
                                .shadow(color: MoraxTheme.electricCyan.opacity(0.35), radius: 1.5)
                        }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(app.name), téléchargement \(formatRate(app.downloadBytesPerSecond)), téléversement \(formatRate(app.uploadBytesPerSecond))")
            }
        }
    }
}

private struct NetworkRateTile: View {
    let title: String
    let rateString: String
    let icon: String
    let gradientColors: [Color]
    let accessibilityLabel: String
    
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .shadow(color: gradientColors.first?.opacity(0.35) ?? .clear, radius: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            
            VStack(alignment: .leading, spacing: 0.5) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(MoraxTheme.textSecondary)
                Text(rateString)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .tabularFigures()
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(MoraxTheme.surfaceSubtle.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(MoraxTheme.border.opacity(0.6), lineWidth: 0.8)
        )
        .clipShape(.rect(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Live Network Card - Active") {
    NetworkTelemetryCard(
        snapshot: NetworkSnapshot(
            timestamp: .now,
            interfaceName: "en0",
            downloadBytesPerSecond: 12_500_000,
            uploadBytesPerSecond: 1_200_000,
            topApplications: [
                NetworkApplicationUsage(name: "Safari", downloadBytesPerSecond: 9_500_000, uploadBytesPerSecond: 400_000),
                NetworkApplicationUsage(name: "Google Drive", downloadBytesPerSecond: 2_000_000, uploadBytesPerSecond: 700_000),
                NetworkApplicationUsage(name: "Claude", downloadBytesPerSecond: 1_000_000, uploadBytesPerSecond: 100_000)
            ],
            topApplicationsStatus: .active
        )
    )
    .padding()
    .frame(width: 500)
    .background(CleanMyMacBackground())
}
