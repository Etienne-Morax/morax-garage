import SwiftUI
import MoraxCockpitKit

struct CleanupResultsView: View {
    @Bindable private var cleanupState = CleanupStateService.shared
    @Binding var confirmationText: String
    @State private var expandedTiers: Set<RiskTier> = [.safe]
    
    var body: some View {
        let totalRisk = cleanupState.totalRiskSummary
        let safeTotalFormatted = ByteCountFormatter.string(fromByteCount: totalRisk.safe, countStyle: .file)
        let rebuildTotalFormatted = ByteCountFormatter.string(fromByteCount: totalRisk.rebuild, countStyle: .file)
        let destructiveTotalFormatted = ByteCountFormatter.string(fromByteCount: totalRisk.destructive, countStyle: .file)
        
        return VStack(spacing: 0) {
            if cleanupState.isSnapshotStale {
                staleSnapshotBanner
            }
            if cleanupState.staleSkippedCount > 0 {
                changedItemsBanner(count: cleanupState.staleSkippedCount)
            }
            if let trashError = cleanupState.lastTrashErrorMessage {
                trashFailureBanner(message: trashError)
            }
            
            // Top Bar
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // Back to selection button
                    Button(action: {
                        cleanupState.switchToScannerSelection()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Cibles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("[", modifiers: .command)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Retour à la sélection des cibles (Escape ou ⌘[)")
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(cleanupState.selectedScanner.rawValue) :")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            Text("\(cleanupState.scannedItems.count) items")
                                .font(.subheadline)
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(MoraxTheme.successGreen).frame(width: 7, height: 7)
                                Text("Safe: \(safeTotalFormatted)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                            
                            HStack(spacing: 4) {
                                Circle().fill(MoraxTheme.warningAmber).frame(width: 7, height: 7)
                                Text("Rebuild: \(rebuildTotalFormatted)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                            
                            HStack(spacing: 4) {
                                Circle().fill(MoraxTheme.oxbloodRed).frame(width: 7, height: 7)
                                Text("Destructive: \(destructiveTotalFormatted)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            cleanupState.startScan()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Actualiser")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Text("Selected: \(cleanupState.selectedCount) (\(ByteCountFormatter.string(fromByteCount: cleanupState.totalReclaimableBytes, countStyle: .file)))")
                            .font(.subheadline)
                            .tabularFigures()
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        Button("Select safe (\(safeTotalFormatted))") {
                            cleanupState.selectAllSafe()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Deselect all") {
                            cleanupState.deselectAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            confirmationText = ""
                            cleanupState.flowState = .confirming
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Trash Selected (\(ByteCountFormatter.string(fromByteCount: cleanupState.totalReclaimableBytes, countStyle: .file)))")
                            }
                            .foregroundStyle(cleanupState.selectedCount > 0 ? MoraxTheme.oxbloodRed : MoraxTheme.textMuted)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(cleanupState.selectedCount == 0)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(MoraxTheme.surfaceSubtle)
            
            Divider().overlay(MoraxTheme.border)
            
            // Items List Grouped by RiskTier first, Category second
            List {
                let presentTiers = RiskTier.allCases.filter { tier in
                    cleanupState.scannedItems.contains(where: { $0.riskTier == tier })
                }
                
                ForEach(presentTiers, id: \.self) { tier in
                    Section {
                        if expandedTiers.contains(tier) {
                            let tierItems = cleanupState.scannedItems.filter { $0.riskTier == tier }
                            let tierCategories = Array(Set(tierItems.map { $0.category })).sorted { $0.rawValue < $1.rawValue }
                            
                            ForEach(tierCategories) { cat in
                                Section {
                                    ForEach($cleanupState.scannedItems) { $item in
                                        if item.riskTier == tier && item.category == cat {
                                            FileItemRow(item: $item)
                                        }
                                    }
                                } header: {
                                    categoryHeader(cat, tier: tier)
                                }
                            }
                        }
                    } header: {
                        tierHeader(tier)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }
    
    private func tierHeader(_ tier: RiskTier) -> some View {
        let tierItems = cleanupState.scannedItems.filter { $0.riskTier == tier }
        let tierSize = tierItems.reduce(0) { $0 + $1.sizeBytes }
        let isExpanded = expandedTiers.contains(tier)
        
        let (badgeColor, badgeText, icon): (Color, String, String) = {
            switch tier {
            case .safe:
                return (MoraxTheme.successGreen, "SAFE", "checkmark.shield.fill")
            case .rebuildCost:
                return (MoraxTheme.warningAmber, "REBUILD COST", "clock.arrow.circlepath")
            case .destructive:
                return (MoraxTheme.oxbloodRed, "DESTRUCTIVE", "exclamationmark.triangle.fill")
            case .blocked:
                return (MoraxTheme.textMuted, "BLOCKED", "lock.shield.fill")
            }
        }()
        
        return HStack(spacing: 10) {
            Button(action: {
                if isExpanded {
                    expandedTiers.remove(tier)
                } else {
                    expandedTiers.insert(tier)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(badgeColor)
                    
                    Text(tier.title)
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.18))
                        .foregroundStyle(badgeColor)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if tier == .rebuildCost {
                Button("Select all Rebuild Cost") {
                    cleanupState.select(tier: .rebuildCost)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            } else if tier == .destructive {
                Button("Select Destructive") {
                    cleanupState.select(tier: .destructive)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            
            Text(ByteCountFormatter.string(fromByteCount: tierSize, countStyle: .file))
                .font(.subheadline.weight(.semibold))
                .tabularFigures()
                .foregroundStyle(MoraxTheme.textSecondary)
        }
        .padding(.vertical, 6)
    }
    
    private func categoryHeader(_ category: CleanupCategory, tier: RiskTier) -> some View {
        let catItems = cleanupState.scannedItems.filter { $0.category == category && $0.riskTier == tier }
        let catSize = catItems.reduce(0) { $0 + $1.sizeBytes }
        return HStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
            Text(category.rawValue)
                .font(.caption.weight(.bold))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: catSize, countStyle: .file))
                .font(.caption2)
                .tabularFigures()
        }
        .foregroundStyle(MoraxTheme.textSecondary)
        .padding(.vertical, 2)
    }
    
    private var staleSnapshotBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(MoraxTheme.warningAmber)
            Text("These results come from a scan older than 24 hours. Rescan before cleaning — items that changed since then are skipped automatically.")
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
            Spacer()
            Button("Rescan") {
                cleanupState.startScan()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(MoraxTheme.warningAmber.opacity(0.1))
    }

    private func changedItemsBanner(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(MoraxTheme.infoBlue)
            Text("\(count) selected item(s) changed on disk since the scan and were left untouched. Rescan to pick them up again.")
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
            Spacer()
        }
        .padding(10)
        .background(MoraxTheme.infoBlue.opacity(0.1))
    }

    private func trashFailureBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(MoraxTheme.oxbloodRed)
            Text(message)
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(MoraxTheme.oxbloodRed.opacity(0.1))
    }
}
