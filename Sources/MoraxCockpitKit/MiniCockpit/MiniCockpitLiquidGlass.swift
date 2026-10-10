import SwiftUI
import AppKit

// MARK: - Native AppKit Visual Effect View Backdrop

/// Encapsulation AppKit de `NSVisualEffectView` pour garantir un flou matériel authentique (Liquid Glass)
/// en arrière-plan de la fenêtre HUD sur macOS, parfaitement masqué aux coins arrondis.
public struct VisualEffectBackdrop: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let state: NSVisualEffectView.State
    public let isEmphasized: Bool
    public let cornerRadius: CGFloat
    
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        isEmphasized: Bool = false,
        cornerRadius: CGFloat = 16
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
        self.cornerRadius = cornerRadius
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = state
        visualEffectView.isEmphasized = isEmphasized
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.cornerCurve = .continuous
        visualEffectView.layer?.masksToBounds = true
        applyMask(to: visualEffectView, cornerRadius: cornerRadius)
        return visualEffectView
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
        nsView.layer?.cornerRadius = cornerRadius
        applyMask(to: nsView, cornerRadius: cornerRadius)
    }
    
    private func applyMask(to visualEffectView: NSVisualEffectView, cornerRadius: CGFloat) {
        guard cornerRadius > 0 else {
            visualEffectView.maskImage = nil
            return
        }
        let diameter = max(32.0, cornerRadius * 2)
        let maskImage = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.set()
            path.fill()
            return true
        }
        maskImage.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        maskImage.resizingMode = .stretch
        visualEffectView.maskImage = maskImage
    }
}

// MARK: - Liquid Glass Container Style

/// Modificateur de vue appliquant l'esthétique Liquid Glass macOS avec reflets spéculaires,
/// profondeur, contours ultra-fins et adaptation automatique clair / sombre.
public struct LiquidGlassBackgroundModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let isDarkMode: Bool
    public let isHovered: Bool
    public let reduceTransparency: Bool
    
    public init(
        cornerRadius: CGFloat = 16,
        isDarkMode: Bool,
        isHovered: Bool = false,
        reduceTransparency: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.isDarkMode = isDarkMode
        self.isHovered = isHovered
        self.reduceTransparency = reduceTransparency
    }
    
    public func body(content: Content) -> some View {
        content
            .background(backgroundLayers)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(specularBorderOverlay)
    }
    
    @ViewBuilder
    private var backgroundLayers: some View {
        ZStack {
            if reduceTransparency {
                // Mode Contraste Élevé / Réduction de transparence
                if isDarkMode {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(hex: "#0F111E"))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(hex: "#F8FAFC"))
                }
            } else {
                if isDarkMode {
                    // Obsidian Glass authentique sans débordement de CABackdropLayer WindowServer
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#0E1022").opacity(isHovered ? 0.94 : 0.88),
                                    Color(hex: "#090A15").opacity(isHovered ? 0.98 : 0.94)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Reflet spéculaire doux en haut à gauche
                    RadialGradient(
                        colors: [
                            Color(hex: "#6366F1").opacity(isHovered ? 0.12 : 0.06),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 220
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    // Crystal Frost Glass avec matériau clair
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AnyShapeStyle(.thinMaterial))
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.88 : 0.80),
                                    Color(hex: "#F1F5F9").opacity(isHovered ? 0.94 : 0.88)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Reflet spéculaire clair
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.40 : 0.25),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 180
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
        }
    }
    
    private var specularBorderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: isDarkMode ? [
                        Color.white.opacity(isHovered ? 0.35 : 0.20),
                        Color.white.opacity(isHovered ? 0.12 : 0.06),
                        Color.white.opacity(0.02)
                    ] : [
                        Color.white.opacity(isHovered ? 0.90 : 0.75),
                        Color.black.opacity(0.05),
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
    }
}

// MARK: - Mini Tile Glass Background

/// Fond de tuile individuel Liquid Glass
public struct MiniTileGlassModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let isDarkMode: Bool
    public let isInteractive: Bool
    public let isHovered: Bool
    
    public init(
        cornerRadius: CGFloat = 8,
        isDarkMode: Bool,
        isInteractive: Bool = false,
        isHovered: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.isDarkMode = isDarkMode
        self.isInteractive = isInteractive
        self.isHovered = isHovered
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    if isDarkMode {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white.opacity(isHovered ? 0.07 : 0.04))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(isHovered ? 0.05 : 0.03))
                    }
                }
            )
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isDarkMode
                            ? Color.white.opacity(isHovered ? 0.14 : 0.07)
                            : Color.black.opacity(isHovered ? 0.10 : 0.05),
                        lineWidth: 0.5
                    )
            )
    }
}

public extension View {
    func miniCockpitLiquidGlass(
        cornerRadius: CGFloat = 16,
        isDarkMode: Bool,
        isHovered: Bool = false,
        reduceTransparency: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassBackgroundModifier(
                cornerRadius: cornerRadius,
                isDarkMode: isDarkMode,
                isHovered: isHovered,
                reduceTransparency: reduceTransparency
            )
        )
    }
    
    func miniTileGlass(
        cornerRadius: CGFloat = 10,
        isDarkMode: Bool,
        isInteractive: Bool = false,
        isHovered: Bool = false
    ) -> some View {
        modifier(
            MiniTileGlassModifier(
                cornerRadius: cornerRadius,
                isDarkMode: isDarkMode,
                isInteractive: isInteractive,
                isHovered: isHovered
            )
        )
    }
}
