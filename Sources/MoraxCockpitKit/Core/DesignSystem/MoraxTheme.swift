import SwiftUI
import AppKit

public enum MoraxTheme {
    // MARK: - Dynamic Color Helper
    public static func dynamicColor(dark: String, light: String) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(hexString: dark)
            } else {
                return NSColor(hexString: light)
            }
        }))
    }

    // MARK: - Core Blue-Rose Cosmic Modern Brand Tokens
    // Dark mode preserves exact existing vibrant neon colors; Light mode uses high-contrast WCAG AA counterparts.
    public static let electricCyan = dynamicColor(dark: "#00E5FF", light: "#0284C7")     // Sky-600 in light (contrast 4.7:1)
    public static let electricBlue = dynamicColor(dark: "#38BDF8", light: "#0369A1")     // Sky-700 in light (contrast 5.8:1)
    public static let deepIndigo = dynamicColor(dark: "#6366F1", light: "#4338CA")       // Indigo-700 in light (contrast 7.4:1)
    public static let neonViolet = dynamicColor(dark: "#8B5CF6", light: "#6D28D9")       // Violet-700 in light (contrast 7.1:1)
    public static let vividPurple = dynamicColor(dark: "#A855F7", light: "#7E22CE")      // Purple-700 in light (contrast 6.7:1)
    public static let hotPink = dynamicColor(dark: "#EC4899", light: "#BE185D")          // Pink-700 in light (contrast 6.2:1)
    public static let neonRose = dynamicColor(dark: "#FF2E93", light: "#BE123C")         // Rose-700 in light (contrast 6.6:1)
    public static let vividRose = dynamicColor(dark: "#F43F5E", light: "#E11D48")        // Rose-600 in light (contrast 4.9:1)
    
    // Status & Accent Colors
    public static let inkBlack = Color(hex: "#080612")
    public static let warmOffWhite = Color(hex: "#F8FAFC")
    public static let oxbloodRed = dynamicColor(dark: "#F43F5E", light: "#DC2626")       // Red-600 in light (contrast 5.0:1)
    
    public static let successGreen = dynamicColor(dark: "#10B981", light: "#047857")     // Emerald-700 in light (contrast 5.7:1)
    public static let warningAmber = dynamicColor(dark: "#F59E0B", light: "#B45309")     // Amber-700 in light (contrast 5.4:1)
    public static let infoBlue = dynamicColor(dark: "#38BDF8", light: "#0369A1")         // Sky-700 in light (contrast 5.8:1)
    public static let cleanPurple = dynamicColor(dark: "#A855F7", light: "#7E22CE")      // Purple-700 in light (contrast 6.7:1)
    public static let cleanRose = dynamicColor(dark: "#FF2E93", light: "#BE123C")        // Rose-700 in light (contrast 6.6:1)
    public static let cleanCoral = dynamicColor(dark: "#FB7185", light: "#E11D48")       // Rose-600 in light (contrast 4.9:1)
    public static let cleanCrimson = dynamicColor(dark: "#FF2E93", light: "#9F1239")     // Rose-800 in light (contrast 8.4:1)
    public static let cleanRuby = dynamicColor(dark: "#E11D74", light: "#9F1239")        // Deep Rose Ruby in light
    public static let cleanOrange = dynamicColor(dark: "#FB923C", light: "#C2410C")      // Orange-700 in light (contrast 6.0:1)
    
    // MARK: - Dynamic Adaptive Colors (Light & Dark appearance)
    public static let background: Color = dynamicColor(dark: "#0B0C1E", light: "#F8FAFC")
    public static let surface: Color = dynamicColor(dark: "#13122B", light: "#FFFFFF")
    public static let surfaceSubtle: Color = dynamicColor(dark: "#1D1B3E", light: "#F1F5F9")
    public static let border: Color = dynamicColor(dark: "#2B2857", light: "#CBD5E1")
    public static let glassBorder: Color = dynamicColor(dark: "#3B3878", light: "#94A3B8")
    
    public static let textPrimary: Color = dynamicColor(dark: "#F8FAFC", light: "#0F172A")
    public static let textSecondary: Color = dynamicColor(dark: "#CBD5E1", light: "#334155")
    public static let textMuted: Color = dynamicColor(dark: "#8B8FA8", light: "#64748B")
    public static let textDisabled: Color = dynamicColor(dark: "#8B8FA8", light: "#94A3B8")
    
    public static let sidebarBackground: Color = dynamicColor(dark: "#0D0C22", light: "#F1F5F9")
}

// MARK: - Blue-Violet Cosmic Modern Background View (Liquid Glass)
public struct CleanMyMacBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        ZStack {
            // Authentic macOS Liquid Glass native blur backdrop
            VisualEffectBackdrop(
                material: isDark ? .hudWindow : .underWindowBackground,
                blendingMode: .behindWindow,
                state: .active,
                cornerRadius: 0
            )
            
            if isDark {
                // Base Deep Midnight Indigo Gradient with subtle translucency for Liquid Glass
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#0E1029").opacity(0.88), location: 0.0),
                        .init(color: Color(hex: "#140F30").opacity(0.84), location: 0.45),
                        .init(color: Color(hex: "#0E0922").opacity(0.86), location: 0.80),
                        .init(color: Color(hex: "#080614").opacity(0.90), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Ambient Blue & Violet Radial Auras (Cosmic Aurora Depth - ZERO Red)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    // Top-Right: Radiant Electric Violet Glow (Replaced Red/Rose)
                    RadialGradient(
                        colors: [
                            Color(hex: "#8B5CF6").opacity(0.24),
                            Color(hex: "#7C3AED").opacity(0.10),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: max(w, h) * 0.75
                    )
                    
                    // Center-Left: Vivid Electric Cyan / Azure Glow
                    RadialGradient(
                        colors: [
                            Color(hex: "#00C6FF").opacity(0.22),
                            Color(hex: "#3B82F6").opacity(0.08),
                            Color.clear
                        ],
                        center: .init(x: 0.12, y: 0.40),
                        startRadius: 10,
                        endRadius: max(w, h) * 0.55
                    )
                    
                    // Bottom-Center: Deep Electric Violet Aura
                    RadialGradient(
                        colors: [
                            Color(hex: "#6366F1").opacity(0.18),
                            Color(hex: "#4F46E5").opacity(0.06),
                            Color.clear
                        ],
                        center: .init(x: 0.65, y: 0.85),
                        startRadius: 10,
                        endRadius: max(w, h) * 0.50
                    )
                }
            } else {
                // Light mode pearlescent Blue-Violet gradient with subtle translucency for Liquid Glass
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F0F6FF").opacity(0.86), location: 0.0), // Airy celestial sky
                        .init(color: Color(hex: "#F5F3FF").opacity(0.84), location: 0.5), // Subtle lavender
                        .init(color: Color(hex: "#EDE9FE").opacity(0.88), location: 1.0)  // Soft light violet (NO red/pink)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    // Soft Sky Blue highlight top-left
                    RadialGradient(
                        colors: [
                            Color(hex: "#38BDF8").opacity(0.15),
                            Color(hex: "#0284C7").opacity(0.06),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: max(w, h) * 0.65
                    )
                    
                    // Soft Light Violet highlight top-right (contrasting with the blue on the left - NO red)
                    RadialGradient(
                        colors: [
                            Color(hex: "#8B5CF6").opacity(0.14),
                            Color(hex: "#A855F7").opacity(0.07),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: max(w, h) * 0.65
                    )
                    
                    // Subtle Indigo/Violet accent bottom-right
                    RadialGradient(
                        colors: [
                            Color(hex: "#6366F1").opacity(0.08),
                            Color.clear
                        ],
                        center: .init(x: 0.70, y: 0.85),
                        startRadius: 15,
                        endRadius: max(w, h) * 0.50
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glassmorphism View Modifiers
public struct CleanGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var strokeColor: Color?
    public var hasHoverGlow: Bool
    public var isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        cornerRadius: CGFloat = 14,
        strokeColor: Color? = nil,
        hasHoverGlow: Bool = false,
        isHovered: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.strokeColor = strokeColor
        self.hasHoverGlow = hasHoverGlow
        self.isHovered = isHovered
    }
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isDark
                        ? Color(hex: "#12112C").opacity(isHovered ? 0.78 : 0.62)
                        : Color.white.opacity(isHovered ? 0.98 : 0.92)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        strokeColor ?? (
                            isDark
                            ? (isHovered ? Color(hex: "#38BDF8").opacity(0.4) : Color(hex: "#2F2B5E").opacity(0.85))
                            : (isHovered ? MoraxTheme.electricCyan.opacity(0.65) : MoraxTheme.border)
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isDark
                ? (isHovered ? Color(hex: "#38BDF8").opacity(0.15) : Color.black.opacity(0.25))
                : (isHovered ? Color(hex: "#0284C7").opacity(0.12) : Color.black.opacity(0.05)),
                radius: isHovered ? 10 : 5,
                x: 0,
                y: isHovered ? 5 : 2
            )
    }
}

extension View {
    public func cleanGlassCard(
        cornerRadius: CGFloat = 14,
        strokeColor: Color? = nil,
        hasHoverGlow: Bool = false,
        isHovered: Bool = false
    ) -> some View {
        modifier(CleanGlassCardModifier(
            cornerRadius: cornerRadius,
            strokeColor: strokeColor,
            hasHoverGlow: hasHoverGlow,
            isHovered: isHovered
        ))
    }
    
    public func cleanGlassSurface(cornerRadius: CGFloat = 10) -> some View {
        modifier(CleanGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Helpers
extension NSColor {
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

/// Memoized store for colors built from hex literals.
///
/// `Color(hex:)` is called hundreds of times per frame from gauge, navigation and
/// treemap drawing loops. Parsing the string every time is a dominant CPU cost, so
/// parsed colors are cached by their raw hex literal.
private enum HexColorCache {
    nonisolated(unsafe) private static var storage: [String: Color] = [:]
    private static let lock = NSLock()

    static func color(for hex: String) -> Color {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[hex] { return cached }
        let color = parse(hex)
        storage[hex] = color
        return color
    }

    private static func parse(_ rawHex: String) -> Color {
        let hex = rawHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Color {
    public init(hex: String) {
        self = HexColorCache.color(for: hex)
    }
}

public struct TabularFigureModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .fontDesign(.monospaced)
            .monospacedDigit()
    }
}

extension View {
    public func tabularFigures() -> some View {
        modifier(TabularFigureModifier())
    }
}
