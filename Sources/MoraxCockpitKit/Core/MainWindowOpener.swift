import AppKit

/// Brings the main window back from anywhere in the app, including after it was closed.
///
/// The Mini Cockpit, the Dock and the menu bar used to post a notification whose
/// only receiver lived inside the main window's view tree, so once that window was
/// closed nothing could reopen it. The opener belongs to the application instead:
/// the app registers how to create a new main window once, and every caller goes
/// through `open()`, which reuses an existing window before creating one.
@MainActor
public final class MainWindowOpener {
    public static let shared = MainWindowOpener()

    private var openNewWindow: (@MainActor () -> Void)?
    private let activateApp: @MainActor () -> Void
    private let bringExistingWindowToFront: @MainActor () -> Bool

    init(
        activateApp: @escaping @MainActor () -> Void = MainWindowOpener.activateApplication,
        bringExistingWindowToFront: @escaping @MainActor () -> Bool = MainWindowOpener.bringMainWindowToFront
    ) {
        self.activateApp = activateApp
        self.bringExistingWindowToFront = bringExistingWindowToFront
    }

    /// Registers how to create a new main window (typically SwiftUI's `openWindow`).
    public func register(openNewWindow: @escaping @MainActor () -> Void) {
        self.openNewWindow = openNewWindow
    }

    /// Shows the main window, creating one when none is left.
    /// - Returns: `false` when no window exists and no way to create one was registered.
    @discardableResult
    public func open() -> Bool {
        activateApp()
        if bringExistingWindowToFront() {
            return true
        }
        guard let openNewWindow else {
            TelemetryLogger.lifecycle.warning("MainWindowOpener: no main window and no opener registered")
            return false
        }
        openNewWindow()
        return true
    }

    /// Whether `window` is a main application window the user can get back to:
    /// panels (Mini Cockpit HUD, menu bar popover) and status bar windows are not,
    /// and neither are windows that were closed but not yet deallocated.
    public static func isMainWindowCandidate(_ window: NSWindow) -> Bool {
        window.canBecomeMain
            && !(window is NSPanel)
            && !window.className.contains("NSStatusBarWindow")
            && (window.isVisible || window.isMiniaturized)
    }

    /// Recentres a window left entirely off-screen (e.g. after a display was unplugged).
    public static func validatePlacement(_ window: NSWindow) {
        let isVisibleOnAnyScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(window.frame)
        }
        if !isVisibleOnAnyScreen {
            window.center()
        }
    }

    private static func activateApplication() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func bringMainWindowToFront() -> Bool {
        guard let window = NSApp.windows.first(where: isMainWindowCandidate) else {
            return false
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        validatePlacement(window)
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
