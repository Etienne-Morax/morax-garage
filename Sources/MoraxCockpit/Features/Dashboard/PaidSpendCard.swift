import SwiftUI
import MoraxCockpitKit

/// Carte affichant les dépenses et le solde d'une API à l'appel (ex. DeepSeek API),
/// avec une jauge visuelle et une télémétrie détaillée.
public struct PaidSpendCard: View {
    public let spend: PaidApiSpend
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(spend: PaidApiSpend) {
        self.spend = spend
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    /// Inner width of the 80 pt ring, so the amount never overlaps the arc.
    private let dialReadoutMaxWidth: CGFloat = 60

    public var body: some View {
        let fromBalance = spend.balanceSpendUsd != nil
        let amount = spend.balanceSpendUsd ?? spend.costUsd
        let currency = spend.balanceCurrency ?? "USD"
        let isDepleted = spend.balanceAvailable == false

        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDarkMode
                                ? [Color(hex: "#00E5FF").opacity(0.25), Color(hex: "#3B82F6").opacity(0.20)]
                                : [MoraxTheme.electricCyan.opacity(0.18), MoraxTheme.electricBlue.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: "cpu.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(MoraxTheme.electricBlue)
                }

                HStack(spacing: 6) {
                    Text(spend.label.uppercased())
                        .font(.system(size: 12.5, weight: .black, design: .rounded))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .layoutPriority(2)

                    ViewThatFits(in: .horizontal) {
                        callBadge
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                .layoutPriority(1)

                Spacer()

                // Status Badge
                if isDepleted {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MoraxTheme.oxbloodRed)
                            .frame(width: 5.5, height: 5.5)
                        Text("ÉPUISÉ")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(MoraxTheme.oxbloodRed.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(MoraxTheme.oxbloodRed.opacity(0.3), lineWidth: 0.75)
                    )
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MoraxTheme.successGreen)
                            .frame(width: 5.5, height: 5.5)
                        Text("SOLDE OK")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(MoraxTheme.successGreen)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(MoraxTheme.successGreen.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(MoraxTheme.successGreen.opacity(0.3), lineWidth: 0.75)
                    )
                }
            }

            // Content Body
            HStack(alignment: .center, spacing: 10) {
                // Left: Visual Spend Pod
                spendDialPod(amount: amount, currency: currency, fromBalance: fromBalance, isDepleted: isDepleted)
                    .frame(width: 112)

                // Right: Solde restant ou statut
                VStack(alignment: .leading, spacing: 6) {
                    if let balance = spend.balanceUsd {
                        metadataRow(
                            icon: "creditcard",
                            label: "Solde restant",
                            value: balance.formatted(.currency(code: currency).presentation(.narrow)),
                            accent: isDepleted ? MoraxTheme.oxbloodRed : MoraxTheme.textPrimary
                        )
                    } else {
                        metadataRow(
                            icon: "checkmark.circle.fill",
                            label: "Statut",
                            value: "Prêt",
                            accent: MoraxTheme.successGreen
                        )
                    }
                    if spend.calls > 0 {
                        metadataRow(
                            icon: "arrow.triangle.2.circlepath",
                            label: "Requêtes",
                            value: "\(spend.calls)",
                            accent: MoraxTheme.textSecondary
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .accessibilityLabel(accessibilityDescription(amount: amount, currency: currency, fromBalance: fromBalance, isDepleted: isDepleted))
    }

    // MARK: - Call Badge
    /// Dropped when the header is too narrow, so the provider name stays readable.
    private var callBadge: some View {
        Text("À L'APPEL")
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                isDarkMode
                ? Color(hex: "#00E5FF").opacity(0.18)
                : MoraxTheme.electricCyan.opacity(0.14)
            )
            .foregroundStyle(MoraxTheme.electricBlue)
            .clipShape(.rect(cornerRadius: 3.5))
    }

    // MARK: - Spend Dial Pod
    @ViewBuilder
    private func spendDialPod(amount: Double, currency: String, fromBalance: Bool, isDepleted: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background Track Arc
                CleanArcRingShape(startAngle: 140, sweepAngle: 260)
                    .stroke(
                        isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.10),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )

                // Active Glowing Arc
                CleanArcRingShape(startAngle: 140, sweepAngle: 260 * 0.75)
                    .stroke(
                        LinearGradient(
                            colors: isDepleted
                                ? [MoraxTheme.oxbloodRed, Color(hex: "#EF4444")]
                                : (isDarkMode
                                    ? [Color(hex: "#00E5FF"), Color(hex: "#3B82F6")]
                                    : [Color(hex: "#0284C7"), Color(hex: "#0369A1")]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )

                // Central Readout
                VStack(spacing: 1) {
                    Text(amount.formatted(.currency(code: currency).presentation(.narrow)))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: dialReadoutMaxWidth)

                    Text(fromBalance ? "DÉPENSÉ" : "COÛT MOIS")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(isDepleted ? MoraxTheme.oxbloodRed : (isDarkMode ? Color(hex: "#38BDF8") : Color(hex: "#0369A1")))
                }
            }
            .frame(width: 80, height: 70)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(MoraxTheme.surfaceSubtle.opacity(0.5))
        .clipShape(.rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(MoraxTheme.border.opacity(0.7), lineWidth: 0.75)
        )
    }

    // MARK: - Metadata Row
    private func metadataRow(icon: String, label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
                .foregroundStyle(MoraxTheme.textMuted)
                .frame(width: 14)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MoraxTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
    }

    private func accessibilityDescription(amount: Double, currency: String, fromBalance: Bool, isDepleted: Bool) -> String {
        var parts: [String] = ["\(spend.label) : \(amount.formatted(.currency(code: currency))) dépensé"]
        if let balance = spend.balanceUsd {
            parts.append("solde restant \(balance.formatted(.currency(code: currency)))")
        }
        if isDepleted {
            parts.append("crédit épuisé")
        }
        parts.append("\(spend.calls) appels")
        return parts.joined(separator: ", ")
    }
}
