import SwiftUI
import MoraxCockpitKit

struct ScannerSelectionView: View {
    private var stagingService = CleanupStagingService.shared
    @Bindable private var cleanupState = CleanupStateService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    MoraxMascotView(size: 64)
                    
                    Text("Select Cleanup Target")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text("All scans run as dry-run. No files are selected by default.")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .padding(.top, 12)
                
                // Top Global Estimation Bar
                estimationGlobalBar
                    .frame(maxWidth: 560)
                
                if !cleanupState.scannedItems.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundStyle(MoraxTheme.successGreen)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dernier scan en mémoire (\(cleanupState.selectedScanner.rawValue))")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            
                            HStack(spacing: 6) {
                                Text("\(cleanupState.scannedItems.count) éléments scannés")
                                    .font(.caption2)
                                    .foregroundStyle(MoraxTheme.textSecondary)
                                
                                if let dateStr = cleanupState.formattedLastScanDate {
                                    Text("• \(dateStr)")
                                        .font(.caption2)
                                        .foregroundStyle(MoraxTheme.infoBlue)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            cleanupState.flowState = .results
                        }) {
                            Text("Afficher les résultats")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MoraxTheme.successGreen)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .frame(maxWidth: 560)
                    .background(MoraxTheme.successGreen.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(MoraxTheme.successGreen.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 6))
                }
                
                if stagingService.hasStagedItems {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.3x3.square")
                            .font(.title3)
                            .foregroundStyle(MoraxTheme.infoBlue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Items Staged from Storage Map (\(stagingService.stagedItems.count) items)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            Text("\(stagingService.formattedTotalStagedBytes) ready for safety validation and cleanup.")
                                .font(.caption2)
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            cleanupState.scannedItems = stagingService.stagedItems
                            cleanupState.flowState = .results
                        }) {
                            Text("Review & Clean")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MoraxTheme.infoBlue)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .frame(maxWidth: 560)
                    .background(MoraxTheme.infoBlue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(MoraxTheme.infoBlue.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 6))
                }
                
                FullDiskAccessObserver { hasFullDiskAccess, permissionsService in
                    if !hasFullDiskAccess {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.shield")
                                .font(.title3)
                                .foregroundStyle(MoraxTheme.warningAmber)
                        
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Full Disk Access recommended")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(MoraxTheme.textPrimary)
                                Text("DaVinci Resolve and photo app cache scans require Full Disk Access to inspect user application support folders.")
                                    .font(.caption2)
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                        
                            Spacer()
                        
                            Button(action: { permissionsService.openAllFilesSettings() }) {
                                Text("Configure")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .frame(maxWidth: 560)
                        .background(MoraxTheme.surfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MoraxTheme.warningAmber.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(.rect(cornerRadius: 6))
                    }
                }
                
                VStack(spacing: 12) {
                    ForEach(ScannerType.allCases) { scanner in
                        ScannerCardButton(
                            scanner: scanner,
                            isSelected: cleanupState.selectedScanner == scanner,
                            description: scannerDescription(for: scanner),
                            onSelect: { cleanupState.selectScanner(scanner) }
                        )
                    }
                }
                .frame(maxWidth: 560)
                
                Button(action: { cleanupState.startScan() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Start Dry-Run Scan")
                    }
                    .font(.headline)
                    .frame(minWidth: 220)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.infoBlue)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
    
    @ViewBuilder
    private var estimationGlobalBar: some View {
        HStack(spacing: 12) {
            if cleanupState.isEstimating {
                ProgressView()
                    .controlSize(.small)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Estimation des tailles en arrière-plan...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text(cleanupState.estimationProgressText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button("Annuler") {
                    cleanupState.cancelEstimation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(MoraxTheme.infoBlue)
                    Text("Tailles par catégorie")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                
                Spacer()
                
                Button(action: {
                    cleanupState.estimateAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Tout estimer")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(MoraxTheme.surfaceSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 6))
    }
    
    private func scannerDescription(for scanner: ScannerType) -> String {
        switch scanner {
        case .resolve:
            return "Render Cache (CacheClip), Optimised Media, Proxies, Gallery Stills, and Crash Logs."
        case .photo:
            return "Lightroom Previews (.lrdata), Capture One Session Caches (.cop/.cot), and Photoshop/ACR."
        case .apps:
            return "WhatsApp, Spotify, Telegram, Slack, Discord, Teams, Notion, VS Code and Claude caches."
        case .dev:
            return "node_modules, .next, dist, target (Rust), .venv, and Xcode DerivedData."
        case .claude:
            return "Worktrees (.claude/worktrees), preadopt backups, transcripts, plugin cache, and telemetry."
        case .browsers:
            return "Safari, Google Chrome, Arc, Brave, Firefox, and Edge page/media caches."
        case .system:
            return "User application caches (~/Library/Caches), QuickLook thumbnails, and diagnostic logs."
        case .installers:
            return ".dmg, .pkg, large archives (>50MB) in Downloads/Desktop and Homebrew cache."
        case .all:
            return "Runs all eight scanners in a single comprehensive sweep."
        }
    }
}
