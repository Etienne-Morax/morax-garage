import SwiftUI
import AppKit
import MoraxCockpitKit

/// Carte Muse Code (Meta) réduite à l'essentiel : le seul % d'utilisation,
/// affiché comme les autres jauges (grand % au centre de l'arc).
///
/// Aucun endpoint ne servant les fenêtres d'abonnement Meta automatiquement,
/// le % est relevé à la main depuis `dev.meta.ai/usage` via le curseur en
/// Réglages > Compteurs IA ; le bouton dédié rouvre la page officielle.
public struct MetaMuseCreditCard: View {
    @AppStorage(MetaMuseManualQuota.percentKey) private var manualPercent: Double = MetaMuseManualQuota.unset
    @AppStorage(MetaMuseManualQuota.updatedAtKey) private var manualUpdatedAt: Double = 0

    private var settings = AppSettings.shared

    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var hasValue: Bool {
        manualPercent >= 0
    }

    private var clampedPercent: Double {
        MetaMuseManualQuota.clamped(manualPercent)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDarkMode
                                ? [Color(hex: "#0082FB").opacity(0.25), Color(hex: "#00E5FF").opacity(0.20)]
                                : [MoraxTheme.deepIndigo.opacity(0.18), MoraxTheme.electricCyan.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: "terminal.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(MoraxTheme.electricBlue)
                }

                Text("MUSE CODE")
                    .font(.system(size: 12.5, weight: .black, design: .rounded))
                    .foregroundStyle(MoraxTheme.textPrimary)

                Spacer()

                Button(action: openInBrowser) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .padding(5)
                        .background(MoraxTheme.surfaceSubtle)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(MoraxTheme.border.opacity(0.8), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help("Ouvrir la page Usage Meta (% d'abonnement)")
            }

            // Gauge
            VStack(spacing: 6) {
                ZStack {
                    CleanArcRingShape(startAngle: 140, sweepAngle: 260)
                        .stroke(
                            isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.10),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )

                    if hasValue {
                        CleanArcRingShape(startAngle: 140, sweepAngle: 260 * clampedPercent / 100)
                            .stroke(
                                LinearGradient(
                                    colors: isDarkMode
                                    ? [Color(hex: "#0082FB"), Color(hex: "#00E5FF")]
                                    : [Color(hex: "#1D4ED8"), Color(hex: "#0284C7")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round)
                            )
                    }

                    Text(hasValue ? MetaMuseManualQuota.formatted(manualPercent) : "—")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(hasValue ? MoraxTheme.textPrimary : MoraxTheme.textMuted)
                        .monospacedDigit()
                }
                .frame(height: 120)

                Text(MetaMuseManualQuota.updatedLabel(at: manualUpdatedAt > 0 ? Date(timeIntervalSince1970: manualUpdatedAt) : nil))
                    .font(.system(size: 10))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(hasValue
            ? "Muse Code : \(MetaMuseManualQuota.formatted(manualPercent)) utilisés"
            : "Muse Code : pourcentage non renseigné"))
    }

    private func openInBrowser() {
        guard let url = settings.metamuseUsageURL else { return }
        NSWorkspace.shared.open(url)
    }
}
