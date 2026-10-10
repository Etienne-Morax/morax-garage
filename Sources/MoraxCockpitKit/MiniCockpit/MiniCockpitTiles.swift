import SwiftUI
import AppKit

// MARK: - Mini Arc Shape

/// Forme en arc circulaire pour les micro-jauges du Mini Cockpit.
public struct MiniArcShape: Shape {
    public let startAngle: Double
    public let sweep: Double
    
    public init(startAngle: Double = 135, sweep: Double = 270) {
        self.startAngle = startAngle
        self.sweep = sweep
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(2, min(rect.width, rect.height) / 2.0 - 2)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweep),
            clockwise: false
        )
        return path
    }
}

// MARK: - Mini Sparkline View

/// Canvas ultra-léger traçant l'historique temporel des métriques CPU / GPU sans allocation superflue.
public struct MiniSparklineView: View {
    public let values: [Double]
    public let strokeColor: Color
    public let fillColor: Color
    
    public init(values: [Double], strokeColor: Color, fillColor: Color) {
        self.values = values
        self.strokeColor = strokeColor
        self.fillColor = fillColor
    }
    
    public var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            
            let width = size.width
            let height = size.height
            let step = width / CGFloat(values.count - 1)
            
            var linePath = Path()
            var fillPath = Path()
            
            for (index, val) in values.enumerated() {
                let x = CGFloat(index) * step
                let y = height - (CGFloat(val) * (height - 3)) - 1.5
                
                if index == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: x, y: height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            fillPath.addLine(to: CGPoint(x: CGFloat(values.count - 1) * step, y: height))
            fillPath.closeSubpath()
            
            context.fill(fillPath, with: .color(fillColor))
            context.stroke(linePath, with: .color(strokeColor), lineWidth: 1.25)
        }
    }
}

// MARK: - Circular Arc Micro Gauge

/// Jauge en arc circulaire précise et légère pour GPU, CPU, RAM ou métrique unitaire.
public struct MiniGpuGaugeView: View {
    public let valueFraction: Double // 0.0 ... 1.0
    public let isDarkMode: Bool
    public let isUnavailable: Bool
    public let customGradient: LinearGradient?
    
    public init(
        valueFraction: Double,
        isDarkMode: Bool,
        isUnavailable: Bool = false,
        customGradient: LinearGradient? = nil
    ) {
        self.valueFraction = min(1.0, max(0.0, valueFraction))
        self.isDarkMode = isDarkMode
        self.isUnavailable = isUnavailable
        self.customGradient = customGradient
    }
    
    private var statusGradient: LinearGradient {
        if let custom = customGradient {
            return custom
        }
        if isUnavailable {
            let col = isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.2)
            return LinearGradient(colors: [col, col], startPoint: .leading, endPoint: .trailing)
        }
        
        let pct = valueFraction * 100
        if isDarkMode {
            if pct >= 85 {
                return LinearGradient(
                    colors: [MoraxTheme.warningAmber, MoraxTheme.oxbloodRed],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if pct >= 70 {
                return LinearGradient(
                    colors: [MoraxTheme.electricCyan, MoraxTheme.warningAmber],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [Color(hex: "#00E5FF"), Color(hex: "#3B82F6")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            if pct >= 85 {
                return LinearGradient(
                    colors: [Color(hex: "#D97706"), Color(hex: "#DC2626")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if pct >= 70 {
                return LinearGradient(
                    colors: [Color(hex: "#0284C7"), Color(hex: "#D97706")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [Color(hex: "#0284C7"), Color(hex: "#2563EB")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    private var trackColor: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
    
    public var body: some View {
        ZStack {
            // Track Arc (240°)
            MiniArcShape(startAngle: 150, sweep: 240)
                .stroke(trackColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            
            // Value Arc
            if !isUnavailable && valueFraction > 0.005 {
                MiniArcShape(startAngle: 150, sweep: 240)
                    .trim(from: 0, to: CGFloat(valueFraction))
                    .stroke(statusGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .frame(width: 24, height: 22)
    }
}

// MARK: - Reusable Metric Tile (GPU, RAM, CPU)

public struct MiniMetricTile: View {
    public let iconName: String
    public let title: String
    public let valueText: String
    public let fraction: Double
    public let secondaryText: String?
    public let accentColor: Color
    public let isDarkMode: Bool
    public let isUnavailable: Bool
    public let gaugeType: GaugeType
    
    public enum GaugeType {
        case arc(gradient: LinearGradient? = nil)
        case gpuArc
        case ramBar
        case cpuSparkline(values: [Double])
    }
    
    public init(
        iconName: String,
        title: String,
        valueText: String,
        fraction: Double,
        secondaryText: String? = nil,
        accentColor: Color,
        isDarkMode: Bool,
        isUnavailable: Bool = false,
        gaugeType: GaugeType
    ) {
        self.iconName = iconName
        self.title = title
        self.valueText = valueText
        self.fraction = fraction
        self.secondaryText = secondaryText
        self.accentColor = accentColor
        self.isDarkMode = isDarkMode
        self.isUnavailable = isUnavailable
        self.gaugeType = gaugeType
    }
    
    private var textPrimary: Color {
        isDarkMode ? Color(hex: "#F8FAFC") : Color(hex: "#0F172A")
    }
    
    private var textSecondary: Color {
        isDarkMode ? Color(hex: "#94A3B8") : Color(hex: "#475569")
    }
    
    private var textMuted: Color {
        isDarkMode ? Color(hex: "#64748B") : Color(hex: "#64748B")
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            // Header Row: Icon + Title
            HStack(alignment: .center, spacing: 3.5) {
                Image(systemName: iconName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accentColor)
                
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(textSecondary)
                
                Spacer(minLength: 2)
            }
            
            // Gauge & Value Display
            switch gaugeType {
            case .arc(let customGrad):
                HStack(alignment: .center, spacing: 4.5) {
                    MiniGpuGaugeView(
                        valueFraction: fraction,
                        isDarkMode: isDarkMode,
                        isUnavailable: isUnavailable,
                        customGradient: customGrad
                    )
                    
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text(valueText)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(isUnavailable ? textMuted : accentColor)
                            .monospacedDigit()
                            .lineLimit(1)
                        
                        if let sec = secondaryText {
                            Text(sec)
                                .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(textMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                
            case .gpuArc:
                HStack(alignment: .center, spacing: 4.5) {
                    MiniGpuGaugeView(
                        valueFraction: fraction,
                        isDarkMode: isDarkMode,
                        isUnavailable: isUnavailable
                    )
                    
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text(valueText)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(isUnavailable ? textMuted : accentColor)
                            .monospacedDigit()
                            .lineLimit(1)
                        
                        if let sec = secondaryText {
                            Text(sec)
                                .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(textMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                
            case .ramBar:
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(valueText)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                        
                        Spacer(minLength: 2)
                        
                        if let sec = secondaryText {
                            Text(sec)
                                .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(textMuted)
                                .lineLimit(1)
                        }
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                                .frame(height: 3)
                            
                            Capsule()
                                .fill(accentColor)
                                .frame(
                                    width: max(0, min(geo.size.width, geo.size.width * CGFloat(fraction))),
                                    height: 3
                                )
                        }
                    }
                    .frame(height: 3)
                }
                
            case .cpuSparkline(let values):
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack {
                        Text(valueText)
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                        
                        Spacer(minLength: 2)
                        
                        if let sec = secondaryText {
                            Text(sec)
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundStyle(textMuted)
                                .lineLimit(1)
                        }
                    }
                    
                    MiniSparklineView(
                        values: values,
                        strokeColor: accentColor,
                        fillColor: accentColor.opacity(isDarkMode ? 0.22 : 0.18)
                    )
                    .frame(height: 10)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .miniTileGlass(cornerRadius: 8, isDarkMode: isDarkMode)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) : \(valueText)\(secondaryText != nil ? ", \(secondaryText!)" : "")")
    }
}

// MARK: - Reusable App Usage Tile (Top GPU / CPU Applications)

public struct MiniAppUsageTile: View {
    public let appName: String
    public let bundlePath: String?
    public let metricLabel: String
    public let metricValue: String
    public let fraction: Double
    public let accentColor: Color
    public let isDarkMode: Bool
    public let fallbackIcon: String
    
    public init(
        appName: String,
        bundlePath: String? = nil,
        metricLabel: String = "GPU",
        metricValue: String,
        fraction: Double,
        accentColor: Color,
        isDarkMode: Bool,
        fallbackIcon: String = "app.fill"
    ) {
        self.appName = appName
        self.bundlePath = bundlePath
        self.metricLabel = metricLabel
        self.metricValue = metricValue
        self.fraction = min(1.0, max(0.0, fraction))
        self.accentColor = accentColor
        self.isDarkMode = isDarkMode
        self.fallbackIcon = fallbackIcon
    }
    
    private var textPrimary: Color {
        isDarkMode ? Color(hex: "#F8FAFC") : Color(hex: "#0F172A")
    }
    
    private var textSecondary: Color {
        isDarkMode ? Color(hex: "#94A3B8") : Color(hex: "#475569")
    }
    
    private var resolvedAppIcon: NSImage? {
        if let path = bundlePath, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(appName) == .orderedSame ||
            $0.bundleURL?.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }) {
            if let icon = running.icon {
                return icon
            }
            if let url = running.bundleURL {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        
        let candidates = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            "/Applications/Utilities/\(appName).app"
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return NSWorkspace.shared.icon(forFile: candidate)
            }
        }
        
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
            return NSWorkspace.shared.icon(forFile: appUrl.path)
        }
        
        return nil
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            // Real macOS App Icon or Styled SF Symbol Badge
            if let icon = resolvedAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 4.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5)
                            .stroke(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(accentColor.opacity(isDarkMode ? 0.20 : 0.14))
                        .frame(width: 20, height: 20)
                    
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5)
                        .stroke(accentColor.opacity(0.35), lineWidth: 0.5)
                )
            }
            
            // Name + Load
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 2) {
                    Text(appName)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer(minLength: 2)
                    
                    Text(metricValue)
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                }
                
                // Micro bar with background track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            .frame(height: 2)
                        
                        Capsule()
                            .fill(accentColor)
                            .frame(width: max(2, geo.size.width * CGFloat(fraction)), height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .miniTileGlass(cornerRadius: 8, isDarkMode: isDarkMode)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName) : \(metricLabel) \(metricValue)")
    }
}

// MARK: - Mini AI Counter Card

public struct MiniAICounterCard: View {
    public let item: MiniAICounterItem
    public let isDarkMode: Bool
    
    public init(item: MiniAICounterItem, isDarkMode: Bool) {
        self.item = item
        self.isDarkMode = isDarkMode
    }
    
    private var textPrimary: Color {
        isDarkMode ? Color(hex: "#F8FAFC") : Color(hex: "#0F172A")
    }
    
    private var textMuted: Color {
        isDarkMode ? Color(hex: "#64748B") : Color(hex: "#64748B")
    }
    
    private var trackColor: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    
    private var statusColor: Color {
        guard item.hasData else {
            return isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.2)
        }
        switch item.tone {
        case .ok:
            return isDarkMode ? MoraxTheme.successGreen : Color(hex: "#059669")
        case .warn:
            return isDarkMode ? MoraxTheme.warningAmber : Color(hex: "#D97706")
        case .critical:
            return isDarkMode ? MoraxTheme.oxbloodRed : Color(hex: "#DC2626")
        }
    }
    
    public var body: some View {
        VStack(spacing: 3) {
            // Provider name
            Text(item.shortName)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            // Mini Ring Gauge
            ZStack {
                // Background Track Arc (270°)
                MiniArcShape(startAngle: 135, sweep: 270)
                    .stroke(trackColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                
                // Active Progress Arc
                if let pct = item.usedPercent {
                    MiniArcShape(startAngle: 135, sweep: 270)
                        .trim(from: 0, to: max(0, min(100, pct)) / 100.0)
                        .stroke(statusColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                } else if item.hasData {
                    MiniArcShape(startAngle: 135, sweep: 270)
                        .trim(from: 0, to: 0.6)
                        .stroke(statusColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                
                // Center text: Pourcentage utilisé uniquement pour les forfaits
                if let pct = item.usedPercent {
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .monospacedDigit()
                } else if let spend = item.spendAmount {
                    let textValue: String = item.spendCurrency == "CR"
                        ? (spend.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", spend) : String(format: "%.1f", spend))
                        : String(format: "$%.1f", spend)
                    Text(textValue)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("--")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(textMuted)
                }
            }
            .frame(width: 30, height: 26)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .miniTileGlass(cornerRadius: 6, isDarkMode: isDarkMode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
    
    private var accessibilityDescription: String {
        if let pct = item.usedPercent {
            return "\(item.name) : \(Int(pct.rounded())) pourcent consommés"
        } else if let spend = item.spendAmount {
            if item.spendCurrency == "CR" {
                return "\(item.name) : \(spend) crédits restants"
            } else {
                return "\(item.name) : \(spend) dollars dépensés"
            }
        } else {
            return "\(item.name) : aucune donnée"
        }
    }
}

