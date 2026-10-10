import SwiftUI
import AppKit
import MoraxCockpitKit

extension Notification.Name {
    static let moraxNavigateToTab = Notification.Name("moraxNavigateToTab")
}

@main
struct MoraxCockpitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.menuBarEnabledKey) private var menuBarEnabled = true

    private static let mainWindowID = "main_window"

    var body: some Scene {
        // The opener outlives every window, so the Mini Cockpit and the Dock can
        // bring the main window back after it was closed.
        let _ = MainWindowOpener.shared.register { [openWindow] in
            openWindow(id: Self.mainWindowID)
        }

        WindowGroup("Morax Garage", id: Self.mainWindowID) {
            RootView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Keep monitoring light when in background
            }
        }

        // Menu bar item. Lives in the main app so the wrench is available without
        // the separate Morax Garage Menu helper, which users have to launch by hand.
        MenuBarExtra(isInserted: $menuBarEnabled) {
            MoraxMenuBarContent {
                MainWindowOpener.shared.open()
            }
        } label: {
            MoraxMenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply user Dock icon visibility preference (regular or accessory)
        AppSettings.shared.applyDockVisibility()
        AppSettings.shared.syncLaunchAtLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure window is on-screen and properly brought to front
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            self.ensureMainWindowVisible()
        }
        
        // Initial permission check on launch
        PermissionsService.shared.checkAllPermissions()
        
        // The cache telemetry owns a daily scan, so it belongs to the application
        // lifetime rather than to whichever view happens to be on screen.
        CacheTelemetryService.shared.startMonitoring()
        
        // Automated update check if enabled in settings
        UpdateService.shared.checkOnLaunchIfNeeded(frequency: AppSettings.shared.updateCheckFrequency)
        
        // Restore Mini Cockpit HUD if previously enabled
        if AppSettings.shared.miniCockpitEnabled {
            MiniCockpitWindowController.shared.showMiniCockpit(onOpenMainWindow: {
                MainWindowOpener.shared.open()
            })
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if main window is closed
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Once the opener has shown or created the window, returning false stops
        // AppKit from also creating an untitled one.
        !MainWindowOpener.shared.open()
    }
    
    func ensureMainWindowVisible() {
        for window in NSApp.windows where window.canBecomeMain && !window.className.contains("NSStatusBarWindow") {
            validateWindowPlacement(window)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
    
    func validateWindowPlacement(_ window: NSWindow) {
        MainWindowOpener.validatePlacement(window)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        MiniCockpitWindowController.shared.hideMiniCockpit()
        TelemetryCoordinator.shared.releaseAll()
        CacheTelemetryService.shared.stopMonitoring()
        ProcessRunner.shared.terminateAll()
        TelemetryHistoryStore.flushPendingWrites()
    }
}
