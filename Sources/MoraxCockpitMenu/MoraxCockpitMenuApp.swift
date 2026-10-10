import SwiftUI
import AppKit
import MoraxCockpitKit

@main
struct MoraxCockpitMenuApp: App {
    @NSApplicationDelegateAdaptor(MenuAppDelegate.self) var appDelegate
    @State private var metrics = SystemMetricsService.shared
    
    var body: some Scene {
        MenuBarExtra {
            MoraxMenuBarContent(metrics: metrics, onOpenMainWindow: openMainApp)
        } label: {
            MoraxMenuBarLabel(metrics: metrics)
        }
        .menuBarExtraStyle(.window)
    }
    
    private func openMainApp() {
        openMainAppStandalone()
    }
}

@MainActor
final class MenuAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppSettings.shared.miniCockpitEnabled {
            MiniCockpitWindowController.shared.showMiniCockpit(onOpenMainWindow: {
                openMainAppStandalone()
            })
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        MiniCockpitWindowController.shared.hideMiniCockpit()
        TelemetryCoordinator.shared.releaseAll()
        ProcessRunner.shared.terminateAll()
        TelemetryHistoryStore.flushPendingWrites()
    }
}

private func openMainAppStandalone() {
    let appBundleId = "com.morax.garage"
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleId) {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.morax.cockpit") {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    } else {
        let localAppPath = "/Applications/Morax Garage.app"
        let altAppPath = "/Applications/MoraxGarage.app"
        let legacyAppPath = "/Applications/MoraxCockpit.app"
        if FileManager.default.fileExists(atPath: localAppPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: localAppPath))
        } else if FileManager.default.fileExists(atPath: altAppPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: altAppPath))
        } else if FileManager.default.fileExists(atPath: legacyAppPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: legacyAppPath))
        }
    }
}
