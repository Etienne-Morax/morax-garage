import SwiftUI
import MoraxCockpitKit

public struct AuditView: View {
    @Bindable private var stateService = AuditStateService.shared
    
    public init() {}
    
    private var filteredItems: [PersistenceItem] {
        stateService.items.filter { item in
            let matchesLoc = (stateService.selectedLocation == nil) || (item.location == stateService.selectedLocation)
            let matchesOrphan = !stateService.showOrphansOnly || item.isOrphaned
            return matchesLoc && matchesOrphan
        }
    }
    
    private var orphanCount: Int {
        stateService.items.count(where: \.isOrphaned)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Persistence Points Audit (Read-Only)")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        if stateService.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text("Inspect LaunchAgents and LaunchDaemons. Flags orphaned entries where target binaries no longer exist.")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                Toggle("Orphans Only (\(orphanCount))", isOn: $stateService.showOrphansOnly)
                    .toggleStyle(.checkbox)
                
                Button(action: {
                    Task {
                        await stateService.loadAudit(force: true)
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
            
            // Location Picker
            HStack(spacing: 8) {
                FilterPill(title: "All Locations", isSelected: stateService.selectedLocation == nil) {
                    stateService.selectedLocation = nil
                }
                
                ForEach(PersistenceLocation.allCases) { loc in
                    FilterPill(title: loc.rawValue.components(separatedBy: " (").first ?? loc.rawValue, isSelected: stateService.selectedLocation == loc) {
                        stateService.selectedLocation = loc
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(MoraxTheme.surfaceSubtle)
            
            Divider().overlay(MoraxTheme.border)
            
            if stateService.isLoading && stateService.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Scanning persistence points...")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                }
            } else if filteredItems.isEmpty {
                ContentUnavailableView("No Persistence Items Found", systemImage: "checkmark.shield.fill")
            } else {
                List(filteredItems) { item in
                    PersistenceItemRow(item: item)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .background(CleanMyMacBackground())
        .task {
            await stateService.loadAudit(force: false)
        }
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(.caption.weight(isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? MoraxTheme.warmOffWhite : MoraxTheme.surface)
                .foregroundStyle(isSelected ? MoraxTheme.inkBlack : MoraxTheme.textSecondary)
                .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct PersistenceItemRow: View {
    let item: PersistenceItem
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.isOrphaned ? "exclamationmark.triangle.fill" : "gearshape.2")
                .font(.title3)
                .foregroundStyle(item.isOrphaned ? MoraxTheme.oxbloodRed : MoraxTheme.textSecondary)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    if item.isOrphaned {
                        Text("ORPHANED BINARY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MoraxTheme.oxbloodRed.opacity(0.2))
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    
                    if item.runAtLoad {
                        Text("RunAtLoad")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(MoraxTheme.surfaceSubtle)
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                
                if let prog = item.programPath {
                    Text("Executable: \(prog)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(item.binaryExists ? MoraxTheme.textSecondary : MoraxTheme.oxbloodRed)
                        .lineLimit(1)
                }
                
                Text(item.plistURL.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Reveal Plist") {
                NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}
