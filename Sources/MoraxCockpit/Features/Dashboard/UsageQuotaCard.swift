import SwiftUI
import MoraxCockpitKit

struct UsageQuotaCard: View {
    @State private var service = UsageQuotaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = service.cachedSnapshot
        let now = service.currentDate
        let offline = isOffline
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consommation")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MoraxTheme.textMuted)
                        .textCase(.uppercase)
                    Text("Forfaits")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                Spacer()
                statusChip
            }

            let displayedGauges = snapshot?.gauges.filter { gauge in
                let provider = gauge.provider.lowercased()
                let label = gauge.label.lowercased()
                return provider != "grok" && !label.contains("grok") && !provider.contains("xai")
            } ?? []

            if let snapshot, !displayedGauges.isEmpty {
                BalancedGrid(minItemWidth: 180, spacing: 10) {
                    ForEach(displayedGauges) { gauge in
                        QuotaGaugeCard(gauge: gauge, snapshot: snapshot, now: now, offline: offline, reduceMotion: reduceMotion)
                    }
                }
            } else if case .disabled = service.state {
                EmptyUsageCard(text: "Configurez l’URL et la clé du cockpit pour afficher les compteurs.")
            } else if case .unreachable(let message) = service.state {
                EmptyUsageCard(text: message)
            } else {
                EmptyUsageCard(text: "Aucun forfait n’expose de quota vérifié pour l’instant. Rien n’est estimé à partir des tokens : une jauge sans relevé serait une invention.")
            }
        }
        .padding(12)
        .background(MoraxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoraxTheme.border, lineWidth: 1))
    }

    private var statusChip: some View {
        let label: String
        let color: Color
        switch service.state {
        case .ready: label = "Source OK"; color = MoraxTheme.successGreen
        case .restored: label = "Relevé hors ligne"; color = MoraxTheme.warningAmber
        case .loading: label = "Chargement"; color = MoraxTheme.warningAmber
        case .unreachable: label = "Injoignable"; color = MoraxTheme.warningAmber
        case .disabled: label = "Désactivé"; color = MoraxTheme.textMuted
        }
        return Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var isOffline: Bool {
        if case .restored = service.state { return true }
        if case .unreachable = service.state { return true }
        return false
    }
}

private struct QuotaGaugeCard: View {
    let gauge: ProviderQuotaGauge
    let snapshot: UsageQuotaSnapshot
    let now: Date
    let offline: Bool
    let reduceMotion: Bool

    var body: some View {
        let localStale = gauge.isLocallyStale(snapshot: snapshot, at: now)
        VStack(spacing: 6) {
            // 1. Header: Name & Plan Type
            VStack(spacing: 1.5) {
                Text(gauge.label)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .help(gauge.label)
                Text(gauge.planType?.uppercased() ?? "")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)
                    .frame(minHeight: 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // 2. Dual Concentric Circular Gauge
            UsageQuotaGauge(gauge: gauge, reduceMotion: reduceMotion)

            // 3. Windows List (All horizons in duration order: short first, then long)
            VStack(spacing: 2.5) {
                ForEach(gauge.windows) { window in
                    QuotaWindowRow(
                        window: window,
                        isLead: window.windowMinutes == gauge.worst.windowMinutes,
                        snapshotStale: localStale,
                        now: now
                    )
                }
            }

            Spacer(minLength: 2)

            // 4. Footer: Observed Date / Stale Warning
            Text((offline || localStale ? snapshot.localObservedLabel(at: now) : gauge.observedLabel) + (localStale || gauge.stale ? " — relevé périmé" : ""))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(localStale || gauge.stale ? MoraxTheme.warningAmber : MoraxTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MoraxTheme.surfaceSubtle)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(toneColor(gauge.tone))
                .frame(height: 2.5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        let values = gauge.windows
            .map { "\(Int($0.usedPercent.rounded())) % consommés sur la fenêtre \($0.label)" }
        return "\(gauge.label) : " + values.joined(separator: ", ")
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let isLead: Bool
    let snapshotStale: Bool
    let now: Date

    var body: some View {
        let tone = toneColor(window.tone)
        let resetIn = window.localResetInLabel(snapshotIsStale: snapshotStale, at: now)
        let resetAt = window.displayResetAtLabel

        VStack(spacing: 1) {
            // Row 1: Label (e.g. 5H / WEEK) + Percentage (e.g. 25 %)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.displayShortLabel)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textSecondary)

                Spacer(minLength: 4)

                Text("\(Int(window.usedPercent.rounded())) %")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(tone)
            }

            // Row 2: In label (e.g. in 4 h) + Absolute Date (e.g. 30 août, 18:00)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(resetIn)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(resetAt)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textDisabled)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .frame(maxWidth: .infinity)
        .background(MoraxTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isLead ? tone : MoraxTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct UsageQuotaGauge: View {
    let gauge: ProviderQuotaGauge
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / UsageQuotaGeometry.canvas.width, proxy.size.height / UsageQuotaGeometry.canvas.height)
            ZStack {
                ForEach(UsageQuotaGeometry.ticks, id: \.self) { tick in
                    TickShape(tick: Double(tick)).stroke(MoraxTheme.textDisabled, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
                quotaArc(gauge.outer, radius: UsageQuotaGeometry.outerRadius, width: 9)
                if let inner = gauge.inner {
                    quotaArc(inner, radius: UsageQuotaGeometry.innerRadius, width: 4.5)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(gauge.worst.usedPercent.rounded()))")
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text("%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .offset(y: 4)
            }
            .frame(width: UsageQuotaGeometry.canvas.width, height: UsageQuotaGeometry.canvas.height)
            .scaleEffect(scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(width: 120, height: 98)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: gauge.outer.usedPercent)
    }

    private func quotaArc(_ window: QuotaWindow, radius: CGFloat, width: CGFloat) -> some View {
        ZStack {
            ArcShape(radius: radius).stroke(MoraxTheme.border, style: StrokeStyle(lineWidth: width, lineCap: .round))
            ArcShape(radius: radius).trim(from: 0, to: max(0, min(100, window.usedPercent)) / 100)
                .stroke(toneColor(window.tone), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }
}

private struct ArcShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: UsageQuotaGeometry.center, radius: radius,
                    startAngle: .degrees(UsageQuotaGeometry.startAngle),
                    endAngle: .degrees(UsageQuotaGeometry.startAngle + UsageQuotaGeometry.sweep), clockwise: false)
        return path
    }
}

private struct TickShape: Shape {
    let tick: Double
    func path(in rect: CGRect) -> Path {
        func point(_ radius: CGFloat) -> CGPoint {
            let angle = (UsageQuotaGeometry.startAngle + UsageQuotaGeometry.sweep * tick / 100) * .pi / 180
            return CGPoint(x: UsageQuotaGeometry.center.x + radius * cos(angle), y: UsageQuotaGeometry.center.y + radius * sin(angle))
        }
        var path = Path()
        path.move(to: point(UsageQuotaGeometry.tickInnerRadius))
        path.addLine(to: point(UsageQuotaGeometry.tickOuterRadius))
        return path
    }
}

private struct EmptyUsageCard: View {
    let text: String
    var body: some View { Text(text).font(.caption).foregroundStyle(MoraxTheme.textMuted).frame(maxWidth: 680, alignment: .leading) }
}

private func toneColor(_ tone: QuotaTone) -> Color {
    switch tone {
    case .ok: return MoraxTheme.successGreen
    case .warn: return MoraxTheme.warningAmber
    case .critical: return MoraxTheme.oxbloodRed
    }
}
