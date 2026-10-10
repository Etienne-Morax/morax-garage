import SwiftUI
import MoraxCockpitKit

public struct AppsView: View {
    @Bindable private var stateService = AppsStateService.shared
    
    public init() {}
    
    private var filteredApps: [AppInventoryItem] {
        if stateService.searchQuery.isEmpty {
            return stateService.apps
        }
        return stateService.apps.filter {
            $0.name.localizedStandardContains(stateService.searchQuery) ||
            ($0.bundleIdentifier?.localizedStandardContains(stateService.searchQuery) ?? false)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Applications Inventory")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        if stateService.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text("Application sizes and handoff to Pearcleaner for safe uninstallation")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MoraxTheme.textMuted)
                    TextField("Search applications...", text: $stateService.searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: 220)
                
                // Manual Refresh Button
                Button(action: {
                    Task {
                        await stateService.loadApps(force: true)
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
            
            if stateService.isLoading && stateService.apps.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Scanning applications...")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                }
            } else if stateService.apps.isEmpty {
                ContentUnavailableView("No Applications Found", systemImage: "app.badge")
            } else {
                List(filteredApps) { app in
                    AppRowView(app: app)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .background(CleanMyMacBackground())
        .task {
            await stateService.loadApps(force: false)
        }
    }
}

private struct AppRowView: View {
    let app: AppInventoryItem
    
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    if let ver = app.version {
                        Text("v\(ver)")
                            .font(.caption)
                            .tabularFigures()
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                }
                
                Text(app.bundleIdentifier ?? app.bundleURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(app.formattedSize)
                .font(.subheadline.weight(.semibold))
                .tabularFigures()
                .foregroundStyle(MoraxTheme.textPrimary)
                .frame(width: 90, alignment: .trailing)
            
            HStack(spacing: 8) {
                Button("Reveal") {
                    AppsService.shared.revealInFinder(appURL: app.bundleURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Pearcleaner", systemImage: "arrow.up.right.square") {
                    AppsService.shared.handoffToPearcleaner(appURL: app.bundleURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}
