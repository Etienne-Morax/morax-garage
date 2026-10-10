import SwiftUI
import MoraxCockpitKit

public struct EnvironmentView: View {
    private let stateService = EnvironmentStateService.shared
    @State private var copiedToolId: String? = nil
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Environment & Orchestrated Tools")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            
                            if stateService.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        Text("Morax Garage detects user-installed CLI and cask tools without bundling third-party binaries.")
                            .font(.subheadline)
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await stateService.loadTools(force: true)
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(stateService.isScanning)
                }
                .padding(.bottom, 8)
                
                if stateService.isLoading && stateService.tools.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Detecting installed tools...")
                            .font(.callout)
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    .padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(stateService.tools) { tool in
                            ToolCard(tool: tool, isCopied: copiedToolId == tool.id) {
                                copyInstallCommand(tool: tool)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(CleanMyMacBackground())
        .task {
            await stateService.loadTools(force: false)
        }
    }
    
    private func copyInstallCommand(tool: ToolInfo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tool.installCommand, forType: .string)
        copiedToolId = tool.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedToolId == tool.id {
                copiedToolId = nil
            }
        }
    }
}

private struct ToolCard: View {
    let tool: ToolInfo
    let isCopied: Bool
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tool.displayName)
                            .font(.headline)
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        if tool.isPrerequisite {
                            Text("PREREQUISITE")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MoraxTheme.surfaceSubtle)
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }
                    
                    Text(tool.roleDescription)
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(tool.isInstalled ? MoraxTheme.successGreen : MoraxTheme.oxbloodRed)
                        .frame(width: 8, height: 8)
                    
                    Text(tool.isInstalled ? "Installed" : "Missing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tool.isInstalled ? MoraxTheme.textPrimary : MoraxTheme.oxbloodRed)
                    
                    if let version = tool.version {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundStyle(MoraxTheme.textMuted)
                            .tabularFigures()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 6))
            }
            
            Divider()
                .overlay(MoraxTheme.border)
            
            if tool.isInstalled, let path = tool.resolvedPath {
                HStack {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textMuted)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install with command:")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    HStack {
                        Text(tool.installCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(MoraxTheme.surfaceSubtle)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MoraxTheme.border, lineWidth: 1))
                            .clipShape(.rect(cornerRadius: 4))
                        
                        Spacer()
                        
                        Button(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc", action: onCopy)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
    }
}
