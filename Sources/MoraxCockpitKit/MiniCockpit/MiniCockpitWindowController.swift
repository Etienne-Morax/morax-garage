import AppKit
import SwiftUI

/// Contrôleur de fenêtre AppKit dédié au HUD flottant Always-On "Mini Cockpit".
@MainActor
public final class MiniCockpitWindowController: NSObject, NSWindowDelegate {
    public static let shared = MiniCockpitWindowController()
    
    private var panel: NSPanel?
    private var onOpenMainWindowCallback: (() -> Void)?
    
    private enum StorageKeys {
        static let originX = "morax_mini_cockpit_origin_x"
        static let originY = "morax_mini_cockpit_origin_y"
        static let hasSavedOrigin = "morax_mini_cockpit_has_saved_origin"
    }
    
    public var isVisible: Bool {
        panel?.isVisible ?? false
    }
    
    private override init() {
        super.init()
    }
    
    /// - Parameter onOpenMainWindow: replaces the "Ouvrir Morax Garage" action when given;
    ///   `nil` keeps the one registered earlier instead of wiping it.
    public func showMiniCockpit(onOpenMainWindow: (() -> Void)? = nil) {
        registerOpenMainWindowCallback(onOpenMainWindow)
        
        let targetPanel: NSPanel
        if let existing = panel {
            targetPanel = existing
        } else {
            targetPanel = createPanel()
            self.panel = targetPanel
        }
        
        // Assurer que le store démarre son acquisition de télémétrie
        MiniCockpitStore.shared.start()
        
        // Validation géométrique sur les écrans actuels
        validateAndRepositionIfNeeded(targetPanel)
        
        // Configuration Always-on-top et Spaces
        let alwaysOnTop = AppSettings.shared.miniCockpitAlwaysOnTop
        applyAlwaysOnTop(alwaysOnTop)
        
        let allSpaces = AppSettings.shared.miniCockpitAllSpaces
        applyAllSpaces(allSpaces)
        
        targetPanel.orderFrontRegardless()
    }
    
    public func hideMiniCockpit() {
        panel?.orderOut(nil)
        MiniCockpitStore.shared.stop()
    }
    
    public func toggleMiniCockpit(onOpenMainWindow: (() -> Void)? = nil) {
        if isVisible {
            hideMiniCockpit()
        } else {
            showMiniCockpit(onOpenMainWindow: onOpenMainWindow)
        }
    }
    
    func registerOpenMainWindowCallback(_ callback: (() -> Void)?) {
        guard let callback else { return }
        onOpenMainWindowCallback = callback
    }
    
    func openMainWindow() {
        onOpenMainWindowCallback?()
    }
    
    public func applyAlwaysOnTop(_ enabled: Bool) {
        panel?.level = enabled ? .floating : .normal
    }
    
    public func applyAllSpaces(_ enabled: Bool) {
        if enabled {
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            panel?.collectionBehavior = [.moveToActiveSpace]
        }
    }
    
    public static let panelWidth: CGFloat = 296
    
    /// Redimensionne dynamiquement la fenêtre AppKit pour s'adapter fidèlement au contenu (Compact, Standard, Détaillé)
    /// en conservant l'ancrage du coin supérieur de la fenêtre à l'écran.
    public func updatePanelHeight(to targetHeight: CGFloat, animate: Bool = true) {
        guard let p = panel else { return }
        let currentFrame = p.frame
        guard abs(currentFrame.height - targetHeight) > 1.0 else { return }
        
        let deltaHeight = targetHeight - currentFrame.height
        let newY = currentFrame.origin.y - deltaHeight
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newY,
            width: Self.panelWidth,
            height: targetHeight
        )
        
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                p.animator().setFrame(newFrame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated {
                    p.invalidateShadow()
                }
            }
        } else {
            p.setFrame(newFrame, display: true)
            p.invalidateShadow()
        }
    }
    
final class MiniCockpitTransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    
    @MainActor required public init(rootView: Content) {
        super.init(rootView: rootView)
        configureLayer()
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }
    
    private func configureLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureLayer()
    }
    
    override func updateLayer() {
        super.updateLayer()
        configureLayer()
    }
    
    override func layout() {
        super.layout()
        configureLayer()
    }
}

    private func createPanel() -> NSPanel {
        let initialHeight = MiniCockpitStore.shared.displayMode.targetHeight
        let p = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: Self.panelWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        p.isFloatingPanel = true
        p.level = AppSettings.shared.miniCockpitAlwaysOnTop ? .floating : .normal
        p.collectionBehavior = AppSettings.shared.miniCockpitAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.delegate = self
        
        let hudView = MiniCockpitHUDView(
            onOpenMainWindow: { [weak self] in
                self?.openMainWindow()
            },
            onClose: { [weak self] in
                self?.hideMiniCockpit()
                AppSettings.shared.miniCockpitEnabled = false
            }
        )
        
        let hostingView = MiniCockpitTransparentHostingView(rootView: hudView)
        hostingView.autoresizingMask = [.width, .height]
        p.contentView = hostingView
        
        p.invalidateShadow()
        return p
    }
    
    // MARK: - Validation Géométrique Multi-écrans & Persistance
    
    public func validateAndRepositionIfNeeded(_ targetPanel: NSPanel? = nil) {
        guard let p = targetPanel ?? panel else { return }
        
        let defaults = UserDefaults.standard
        let hasSaved = defaults.bool(forKey: StorageKeys.hasSavedOrigin)
        let savedX = defaults.double(forKey: StorageKeys.originX)
        let savedY = defaults.double(forKey: StorageKeys.originY)
        
        let currentSize = p.frame.size
        var targetOrigin = CGPoint(x: savedX, y: savedY)
        
        var isWithinScreen = false
        if hasSaved {
            let candidateRect = CGRect(origin: targetOrigin, size: currentSize)
            for screen in NSScreen.screens {
                // Si au moins 40x40 pixels sont visibles sur un écran connecté
                let intersection = screen.visibleFrame.intersection(candidateRect)
                if intersection.width >= 40 && intersection.height >= 40 {
                    isWithinScreen = true
                    break
                }
            }
        }
        
        if !isWithinScreen {
            // Placement par défaut dans le coin supérieur droit de l'écran principal
            let mainScreen = NSScreen.main ?? NSScreen.screens.first
            if let screen = mainScreen {
                let vis = screen.visibleFrame
                targetOrigin = CGPoint(
                    x: vis.maxX - currentSize.width - 24,
                    y: vis.maxY - currentSize.height - 24
                )
            } else {
                targetOrigin = CGPoint(x: 100, y: 100)
            }
        }
        
        p.setFrameOrigin(targetOrigin)
    }
    
    public func savePosition() {
        guard let p = panel else { return }
        let origin = p.frame.origin
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: StorageKeys.originX)
        defaults.set(origin.y, forKey: StorageKeys.originY)
        defaults.set(true, forKey: StorageKeys.hasSavedOrigin)
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowDidMove(_ notification: Notification) {
        savePosition()
    }
}
