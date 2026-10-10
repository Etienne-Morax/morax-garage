import SwiftUI
import AppKit
import SwiftTerm
import MoraxCockpitKit

public struct TerminalView: View {
    @State private var moleInstalled = false
    private let terminalController = TerminalController.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header with Quick Action Buttons
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mole Terminal (Interactive)")
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text("Direct access to the Mole CLI. Quick buttons insert commands into your shell without auto-executing.")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                if moleInstalled {
                    HStack(spacing: 8) {
                        QuickActionButton(title: "mo clean (dry-run)", command: "mo clean --dry-run") { cmd in
                            terminalController.sendText(cmd)
                        }
                        
                        QuickActionButton(title: "mo purge (dry-run)", command: "mo purge --dry-run") { cmd in
                            terminalController.sendText(cmd)
                        }
                        
                        QuickActionButton(title: "mo installer (dry-run)", command: "mo installer --dry-run") { cmd in
                            terminalController.sendText(cmd)
                        }
                        
                        QuickActionButton(title: "mo status", command: "mo status") { cmd in
                            terminalController.sendText(cmd)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(MoraxTheme.warningAmber)
                        Text("Mole not installed (brew install tw93/tap/mole)")
                            .font(.caption)
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MoraxTheme.surfaceSubtle)
                    .clipShape(.rect(cornerRadius: 6))
                }
            }
            .padding(16)
            .background(MoraxTheme.surface)
            
            Divider().overlay(MoraxTheme.border)
            
            // Terminal View
            MacTerminalRepresentable(controller: terminalController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CleanMyMacBackground())
        .task {
            moleInstalled = ToolRegistry.shared.resolveBinaryPath(name: "mo") != nil
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let command: String
    let onInsert: (String) -> Void
    
    var body: some View {
        Button(action: { onInsert(command) }) {
            HStack(spacing: 4) {
                Image(systemName: "text.cursor")
                Text(title)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

@MainActor
public final class TerminalController: @unchecked Sendable {
    public static let shared = TerminalController()
    fileprivate var terminalView: LocalProcessTerminalView?
    
    public init() {}
    
    public func sendText(_ text: String) {
        terminalView?.send(txt: text)
    }
}

private struct MacTerminalRepresentable: NSViewRepresentable {
    let controller: TerminalController
    
    @MainActor
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        if let existing = controller.terminalView {
            return existing
        }
        
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.configureMoraxTheme()
        
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        terminal.startProcess(
            executable: shell,
            args: ["-l"],
            environment: ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" },
            execName: shell
        )
        
        controller.terminalView = terminal
        return terminal
    }
    
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

extension LocalProcessTerminalView {
    func configureMoraxTheme() {
        self.configureNativeColors()
        self.caretColor = NSColor(red: 0.96, green: 0.94, blue: 0.92, alpha: 1.0)
    }
}
