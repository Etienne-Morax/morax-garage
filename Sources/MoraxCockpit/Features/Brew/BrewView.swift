import SwiftUI
import MoraxCockpitKit

public struct BrewView: View {
    private let stateService = BrewStateService.shared
    @State private var copiedCommand: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Homebrew Package Updates")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        if stateService.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text("Outdated formulae and casks. Copy commands to run upgrades deliberately in your shell.")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                if let report = stateService.report, report.totalCount > 0 {
                    Button(
                        copiedCommand == report.combinedUpgradeCommand ? "Copied" : "Copy 'brew upgrade'",
                        systemImage: copiedCommand == report.combinedUpgradeCommand ? "checkmark" : "doc.on.doc"
                    ) {
                        copyCommand(report.combinedUpgradeCommand)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(MoraxTheme.infoBlue)
                }
                
                Button(action: {
                    Task {
                        await stateService.loadOutdated(force: true)
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(stateService.isScanning)
            }
            .padding(24)
            .background(MoraxTheme.surface)
            
            Divider().overlay(MoraxTheme.border)
            
            if stateService.isLoading && stateService.report == nil && stateService.errorMessage == nil {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Querying Homebrew...")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                }
            } else if let error = stateService.errorMessage, stateService.report == nil {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(MoraxTheme.warningAmber)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                }
            } else if let report = stateService.report {
                if report.totalCount == 0 {
                    ContentUnavailableView(
                        "All Packages Up to Date",
                        systemImage: "checkmark.circle.fill",
                        description: Text("No outdated Homebrew formulae or casks found.")
                    )
                } else {
                    List {
                        if !report.formulae.isEmpty {
                            Section("Formulae (\(report.formulae.count))") {
                                ForEach(report.formulae) { item in
                                    BrewItemRow(item: item, isCopied: copiedCommand == item.upgradeCommand) {
                                        copyCommand(item.upgradeCommand)
                                    }
                                }
                            }
                        }
                        
                        if !report.casks.isEmpty {
                            Section("Casks (\(report.casks.count))") {
                                ForEach(report.casks) { item in
                                    BrewItemRow(item: item, isCopied: copiedCommand == item.upgradeCommand) {
                                        copyCommand(item.upgradeCommand)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
        }
        .background(CleanMyMacBackground())
        .task {
            await stateService.loadOutdated(force: false)
        }
    }
    
    private func copyCommand(_ cmd: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        copiedCommand = cmd
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedCommand == cmd {
                copiedCommand = nil
            }
        }
    }
}

private struct BrewItemRow: View {
    let item: BrewOutdatedItem
    let isCopied: Bool
    let onCopy: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                HStack(spacing: 8) {
                    Text("Installed: \(item.installedVersionString)")
                        .font(.caption)
                        .tabularFigures()
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                    
                    Text("Latest: \(item.current_version)")
                        .font(.caption.weight(.semibold))
                        .tabularFigures()
                        .foregroundStyle(MoraxTheme.infoBlue)
                }
            }
            
            Spacer()
            
            Button(isCopied ? "Copied" : "Copy Command", systemImage: isCopied ? "checkmark" : "doc.on.doc", action: onCopy)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
