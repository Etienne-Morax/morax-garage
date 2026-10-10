import SwiftUI
import MoraxCockpitKit

public struct AutomotiveGauge: View {
    public let value: Double
    public let config: AutomotiveGaugeConfig
    public var style: CockpitGaugeStyle = .standard
    public var subtitle: String? = nil
    public var statusBadge: String? = nil
    public let accessibilityCustomValue: String?
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        value: Double,
        config: AutomotiveGaugeConfig,
        style: CockpitGaugeStyle = .standard,
        subtitle: String? = nil,
        statusBadge: String? = nil,
        accessibilityValue: String? = nil
    ) {
        self.value = value
        self.config = config
        self.style = style
        self.subtitle = subtitle
        self.statusBadge = statusBadge
        self.accessibilityCustomValue = accessibilityValue
    }
    
    public init(
        value: Double,
        title: String = "CPU Utilisation",
        unit: String = "%",
        minValue: Double = 0,
        maxValue: Double = 100,
        warningThreshold: Double? = 70,
        criticalThreshold: Double? = 90,
        majorTicksCount: Int = 4,
        minorTicksPerInterval: Int = 3,
        displayDecimals: Int = 1,
        isInverted: Bool = false,
        style: CockpitGaugeStyle = .standard,
        subtitle: String? = nil,
        statusBadge: String? = nil,
        accessibilityValue: String? = nil
    ) {
        self.value = value
        self.config = AutomotiveGaugeConfig(
            title: title,
            unit: unit,
            minValue: minValue,
            maxValue: maxValue,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            majorTicksCount: majorTicksCount,
            minorTicksPerInterval: minorTicksPerInterval,
            displayDecimals: displayDecimals,
            isInverted: isInverted,
            startAngle: 140.0,
            sweepAngle: 260.0
        )
        self.style = style
        self.subtitle = subtitle
        self.statusBadge = statusBadge
        self.accessibilityCustomValue = accessibilityValue
    }
    
    private var fraction: Double {
        config.fraction(for: value)
    }
    
    /// Short ease-out (none under Reduce Motion), keyed on visible arc steps only.
    private var arcAnimation: Animation? {
        GaugeMotion.animation(reduceMotion: reduceMotion)
    }
    
    private var arcAnimationKey: Int {
        GaugeMotion.animationKey(for: fraction)
    }
    
    private var zoneStatus: GaugeZoneStatus {
        config.zoneStatus(for: value)
    }
    
    private var currentAccentColor: Color {
        let isDark = colorScheme == .dark
        switch zoneStatus {
        case .safe:
            return isDark ? Color(hex: style.safeArcHex) : Color(hex: "#047857")
        case .warning:
            return isDark ? Color(hex: style.warningArcHex) : Color(hex: "#B45309")
        case .critical:
            return isDark ? Color(hex: style.criticalArcHex) : Color(hex: "#DC2626")
        }
    }
    
    private var gradientPalette: [Color] {
        let isDark = colorScheme == .dark
        switch zoneStatus {
        case .safe:
            if config.title.contains("CPU") {
                return isDark
                    ? [Color(hex: "#FF2A54"), Color(hex: "#FF758C")]
                    : [Color(hex: "#BE123C"), Color(hex: "#E11D48")]
            } else if config.title.contains("GPU") {
                return isDark
                    ? [Color(hex: "#00E5FF"), Color(hex: "#38BDF8")]
                    : [Color(hex: "#0369A1"), Color(hex: "#0284C7")]
            } else if config.title.contains("Memory") || config.title.contains("RAM") {
                return isDark
                    ? [Color(hex: "#A855F7"), Color(hex: "#EC4899")]
                    : [Color(hex: "#7E22CE"), Color(hex: "#BE185D")]
            } else if config.title.contains("Swap") {
                return isDark
                    ? [Color(hex: "#8B5CF6"), Color(hex: "#F43F5E")]
                    : [Color(hex: "#4338CA"), Color(hex: "#BE123C")]
            } else if config.title.contains("Power") || config.title.contains("Puissance") {
                return isDark
                    ? [Color(hex: "#FB923C"), Color(hex: "#E11D48")]
                    : [Color(hex: "#C2410C"), Color(hex: "#BE123C")]
            } else if config.title.contains("Buffer") || config.title.contains("Stockage") {
                return isDark
                    ? [Color(hex: "#00C6FF"), Color(hex: "#0072FF")]
                    : [Color(hex: "#0369A1"), Color(hex: "#1D4ED8")]
            } else {
                return isDark
                    ? [Color(hex: style.safeArcHex), Color(hex: style.secondaryAccentHex)]
                    : [Color(hex: "#047857"), Color(hex: "#0284C7")]
            }
        case .warning:
            if config.title.contains("GPU") {
                return isDark
                    ? [Color(hex: "#00E5FF"), Color(hex: "#F59E0B")]
                    : [Color(hex: "#0369A1"), Color(hex: "#B45309")]
            }
            return isDark
                ? [Color(hex: "#F59E0B"), Color(hex: "#EF4444")]
                : [Color(hex: "#B45309"), Color(hex: "#DC2626")]
        case .critical:
            if config.title.contains("GPU") {
                return isDark
                    ? [Color(hex: "#F59E0B"), Color(hex: "#FF2E93")]
                    : [Color(hex: "#B45309"), Color(hex: "#BE123C")]
            }
            return isDark
                ? [Color(hex: "#DC2626"), Color(hex: "#991B1B")]
                : [Color(hex: "#991B1B"), Color(hex: "#7F1D1D")]
        }
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = max(24, size / 2 - 8)
            let trackLineWidth: CGFloat = max(5, radius * 0.11)
            
            ZStack {
                // 1. CleanMyMac Glass Dial Face Background
                CleanDialFaceDisc(radius: radius)
                
                // 2. Translucent Base Track (260° sweep)
                GaugeArcShape(
                    startAngle: config.startAngle,
                    sweepAngle: config.sweepAngle,
                    center: center,
                    radius: radius
                )
                .stroke(
                    colorScheme == .dark
                        ? Color(hex: "#262350").opacity(0.65)
                        : Color(hex: "#E2E8F0").opacity(0.8),
                    style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round)
                )
                
                // 3. Subtle Peripheral Redline / Warning zones
                ForEach(config.zones) { zone in
                    let zoneStartAngle = config.angleDegrees(forFraction: zone.startFraction)
                    let zoneSweep = (zone.endFraction - zone.startFraction) * config.sweepAngle
                    GaugeArcShape(
                        startAngle: zoneStartAngle,
                        sweepAngle: zoneSweep,
                        center: center,
                        radius: radius + trackLineWidth / 2 + 2.5
                    )
                    .stroke(
                        Color(hex: zone.colorHex).opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                }
                
                // 4. Active Radiant Gradient Arc with CleanMyMac Ambient Glow
                if fraction > 0.005 {
                    // Ambient Glow behind active arc
                    GaugeArcShape(
                        startAngle: config.startAngle,
                        sweepAngle: fraction * config.sweepAngle,
                        center: center,
                        radius: radius
                    )
                    .stroke(
                        gradientPalette.first?.opacity(0.5) ?? currentAccentColor.opacity(0.5),
                        style: StrokeStyle(lineWidth: trackLineWidth + 4, lineCap: .round)
                    )
                    .blur(radius: 4)
                    .animation(arcAnimation, value: arcAnimationKey)
                    
                    // Main Gradient Arc
                    GaugeArcShape(
                        startAngle: config.startAngle,
                        sweepAngle: fraction * config.sweepAngle,
                        center: center,
                        radius: radius
                    )
                    .stroke(
                        LinearGradient(
                            colors: gradientPalette,
                            startPoint: .init(x: 0, y: 1),
                            endPoint: .init(x: 1, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round)
                    )
                    .animation(arcAnimation, value: arcAnimationKey)
                    
                    // Luminous Beacon Tip Dot
                    let currentAngleDeg = config.angleDegrees(forFraction: fraction)
                    let angleRad = currentAngleDeg * .pi / 180.0
                    let tipX = center.x + radius * CGFloat(cos(angleRad))
                    let tipY = center.y + radius * CGFloat(sin(angleRad))
                    
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : (gradientPalette.last ?? currentAccentColor))
                        .frame(width: max(4, trackLineWidth * 0.7), height: max(4, trackLineWidth * 0.7))
                        .shadow(color: gradientPalette.last ?? currentAccentColor, radius: 4)
                        .position(x: tipX, y: tipY)
                        .animation(arcAnimation, value: arcAnimationKey)
                }
                
                // 5. Clean Micro-Ticks & Numbers
                CleanTicksOverlay(
                    ticks: config.generateTicks(),
                    config: config,
                    center: center,
                    radius: radius,
                    trackLineWidth: trackLineWidth
                )
                
                // 6. Central Clean HUD Digital Readout
                CleanDigitalHUDReadout(
                    numberString: config.formatNumberOnly(value),
                    unit: config.unit,
                    title: config.title,
                    subtitle: subtitle,
                    statusText: statusBadge ?? zoneStatus.rawValue,
                    accentColor: gradientPalette.first ?? currentAccentColor,
                    radius: radius,
                    center: center
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(config.title)
        .accessibilityValue(accessibilityCustomValue ?? "\(config.formatValue(value)), \(zoneStatus.rawValue)")
    }
}

// MARK: - Subcomponents

private struct CleanDialFaceDisc: View {
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            // Soft Glass Outer Bezel
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: isDark
                        ? [Color(hex: "#38BDF8").opacity(0.35), Color(hex: "#FF2E93").opacity(0.35), Color.white.opacity(0.06)]
                        : [Color.white, Color(hex: "#CBD5E1").opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: radius * 2 + 10, height: radius * 2 + 10)
            
            // Translucent Frosted Glass Face
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark
                        ? [Color(hex: "#1A1738").opacity(0.75), Color(hex: "#0E0C22").opacity(0.92)]
                        : [Color.white.opacity(0.98), Color(hex: "#F1F5F9").opacity(0.95)],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2 + 8, height: radius * 2 + 8)
                .shadow(
                    color: isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.05),
                    radius: 5,
                    x: 0,
                    y: 2
                )
        }
    }
}

private struct CleanTicksOverlay: View {
    let ticks: [GaugeTick]
    let config: AutomotiveGaugeConfig
    let center: CGPoint
    let radius: CGFloat
    let trackLineWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            ForEach(ticks) { tick in
                let angleDeg = config.angleDegrees(forFraction: tick.fraction)
                let angleRad = angleDeg * .pi / 180.0
                let isMajor = tick.isMajor
                let tickLen: CGFloat = isMajor ? max(4, radius * 0.08) : max(2.5, radius * 0.04)
                let innerR = radius - trackLineWidth / 2 - 2 - tickLen
                let outerR = radius - trackLineWidth / 2 - 2
                
                CleanTickLineShape(
                    center: center,
                    innerRadius: innerR,
                    outerRadius: outerR,
                    angleRad: angleRad
                )
                .stroke(
                    isMajor
                        ? (colorScheme == .dark ? MoraxTheme.textPrimary.opacity(0.65) : MoraxTheme.textSecondary)
                        : (colorScheme == .dark ? MoraxTheme.textMuted.opacity(0.3) : MoraxTheme.border),
                    lineWidth: isMajor ? 1.2 : 0.8
                )
                
                // Tick Label for Major Ticks
                if isMajor && !tick.label.isEmpty && radius > 46 {
                    let labelR = innerR - max(5, radius * 0.10)
                    let lx = center.x + labelR * CGFloat(cos(angleRad))
                    let ly = center.y + labelR * CGFloat(sin(angleRad))
                    
                    Text(tick.label)
                        .font(.system(size: max(6.5, radius * 0.11), weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .position(x: lx, y: ly)
                }
            }
        }
    }
}

private struct CleanTickLineShape: Shape {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let angleRad: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cosA = CGFloat(cos(angleRad))
        let sinA = CGFloat(sin(angleRad))
        let p1 = CGPoint(x: center.x + innerRadius * cosA, y: center.y + innerRadius * sinA)
        let p2 = CGPoint(x: center.x + outerRadius * cosA, y: center.y + outerRadius * sinA)
        path.move(to: p1)
        path.addLine(to: p2)
        return path
    }
}

private struct CleanDigitalHUDReadout: View {
    let numberString: String
    let unit: String
    let title: String
    let subtitle: String?
    let statusText: String
    let accentColor: Color
    let radius: CGFloat
    let center: CGPoint
    @Environment(\.colorScheme) private var colorScheme
    
    private var iconForTitle: String {
        let t = title.lowercased()
        if t.contains("cpu") { return "cpu" }
        if t.contains("gpu") { return "display" }
        if t.contains("memory") || t.contains("ram") || t.contains("unifi") { return "memorychip" }
        if t.contains("swap") { return "arrow.triangle.2.circlepath" }
        if t.contains("power") || t.contains("puissance") { return "bolt.fill" }
        if t.contains("buffer") || t.contains("stockage") || t.contains("disk") { return "internaldrive" }
        return "gauge.with.needle"
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Category Icon Badge
            if radius > 42 {
                Image(systemName: iconForTitle)
                    .font(.system(size: max(8, radius * 0.16), weight: .bold))
                    .foregroundStyle(accentColor)
                    .padding(3)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Circle())
            }
            
            // Primary Numeric Value + Unit
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(numberString)
                    .font(.system(size: max(14, radius * 0.34), weight: .bold, design: .rounded))
                    .tabularFigures()
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                Text(unit)
                    .font(.system(size: max(8, radius * 0.16), weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
            }
            
            // Category Title
            Text(title.uppercased())
                .font(.system(size: max(7.5, radius * 0.11), weight: .bold))
                .foregroundStyle(MoraxTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            // Status Pill (CleanMyMac style)
            Text(statusText)
                .font(.system(size: max(7, radius * 0.10), weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    colorScheme == .dark
                        ? accentColor.opacity(0.15)
                        : accentColor.opacity(0.12)
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.clear : accentColor.opacity(0.35), lineWidth: 0.75)
                )
                .clipShape(.capsule)
            
            // Subtitle
            if let sub = subtitle, radius > 48 {
                Text(sub)
                    .font(.system(size: max(7, radius * 0.09), weight: .medium, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 1)
            }
        }
        // Keep the readout inside the dial face instead of spilling over the arc.
        .frame(maxWidth: radius * 1.5)
        .position(center)
    }
}

// MARK: - Unavailable Placeholder Clean Gauge

public struct UnavailableGaugePlaceholder: View {
    public let title: String
    public let reason: String
    public let iconName: String
    public var style: CockpitGaugeStyle = .standard
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        title: String = "System Power",
        reason: String = "macmon requis",
        iconName: String = "bolt.slash",
        style: CockpitGaugeStyle = .standard
    ) {
        self.title = title
        self.reason = reason
        self.iconName = iconName
        self.style = style
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = max(24, size / 2 - 8)
            let trackLineWidth: CGFloat = max(5, radius * 0.11)
            
            ZStack {
                // Glass Disc
                CleanDialFaceDisc(radius: radius)
                
                // Dashed Track Arc (260°)
                GaugeArcShape(
                    startAngle: 140.0,
                    sweepAngle: 260.0,
                    center: center,
                    radius: radius
                )
                .stroke(
                    MoraxTheme.border.opacity(0.6),
                    style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round, dash: [4, 6])
                )
                
                // Center Icon & Reason
                VStack(spacing: 3) {
                    Image(systemName: iconName)
                        .font(.system(size: max(14, radius * 0.28), weight: .semibold))
                        .foregroundStyle(MoraxTheme.textMuted)
                    
                    Text("—")
                        .font(.system(size: max(14, radius * 0.32), weight: .bold, design: .rounded))
                        .foregroundStyle(MoraxTheme.textMuted)
                    
                    Text(title.uppercased())
                        .font(.system(size: max(7, radius * 0.12), weight: .semibold))
                        .foregroundStyle(MoraxTheme.textMuted)
                    
                    Text(reason)
                        .font(.system(size: max(6.5, radius * 0.10), weight: .medium))
                        .foregroundStyle(Color(hex: style.primaryAccentHex).opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(hex: style.primaryAccentHex).opacity(0.12))
                        .clipShape(.capsule)
                        .lineLimit(1)
                }
                .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("Indisponible, \(reason)")
    }
}

// MARK: - Input equality

/// Lets SwiftUI skip re-rendering a dial whose inputs did not change between two
/// telemetry samples (e.g. swap or disk buffer), even though the parent re-renders.
/// Environment values (Reduce Motion, color scheme) still invalidate it on their own.
extension AutomotiveGauge: Equatable {
    nonisolated public static func == (lhs: AutomotiveGauge, rhs: AutomotiveGauge) -> Bool {
        lhs.value == rhs.value
            && lhs.config == rhs.config
            && lhs.style == rhs.style
            && lhs.subtitle == rhs.subtitle
            && lhs.statusBadge == rhs.statusBadge
            && lhs.accessibilityCustomValue == rhs.accessibilityCustomValue
    }
}

#Preview("CleanMyMac Gauges") {
    HStack(spacing: 20) {
        AutomotiveGauge(
            value: 42.5,
            title: "CPU Utilisation",
            unit: "%",
            subtitle: "8P / 2E CORES"
        )
        
        AutomotiveGauge(
            value: 23.4,
            config: AutomotiveGaugeConfig(
                title: "Unified Memory",
                unit: "GB",
                minValue: 0,
                maxValue: 32,
                warningThreshold: 25,
                criticalThreshold: 29
            ),
            subtitle: "32 GB TOTAL"
        )
        
        AutomotiveGauge(
            value: 18.5,
            config: AutomotiveGaugeConfig(
                title: "System Power",
                unit: "W",
                minValue: 0,
                maxValue: 100,
                warningThreshold: 45,
                criticalThreshold: 75
            ),
            subtitle: "56.4°C TEMP"
        )
    }
    .padding(32)
    .background(CleanMyMacBackground())
}
