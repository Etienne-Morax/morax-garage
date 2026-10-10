import SwiftUI
import MoraxCockpitKit

struct ScannerCardButton: View {
    let scanner: ScannerType
    let isSelected: Bool
    let description: String
    let onSelect: () -> Void
    
    @Bindable private var cleanupState = CleanupStateService.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: scanner.iconName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? MoraxTheme.infoBlue : MoraxTheme.textSecondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(scanner.rawValue)
                            .font(.headline)
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        if let summary = cleanupState.cachedSummary(for: scanner), summary.isStale {
                            Text("Périmé")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(MoraxTheme.warningAmber.opacity(0.18))
                                .foregroundStyle(MoraxTheme.warningAmber)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .lineLimit(2)
                    
                    // Metrics & estimation state row
                    metricsRow
                        .padding(.top, 2)
                }
                
                Spacer(minLength: 8)
                
                // Action / Radio state
                HStack(spacing: 12) {
                    estimateButton
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? MoraxTheme.infoBlue : MoraxTheme.border)
                }
            }
            .padding(14)
            .background(
                isSelected
                ? MoraxTheme.surfaceSubtle
                : (isHovered ? MoraxTheme.surfaceSubtle.opacity(0.5) : MoraxTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? MoraxTheme.infoBlue : (isHovered ? MoraxTheme.textSecondary.opacity(0.4) : MoraxTheme.border), lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    @ViewBuilder
    private var metricsRow: some View {
        let isEstimatingThis = cleanupState.isEstimating && cleanupState.currentlyEstimatingScanner == scanner
        
        if isEstimatingThis {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(cleanupState.estimationProgressText.isEmpty ? "Estimation en cours..." : cleanupState.estimationProgressText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(MoraxTheme.infoBlue)
                    .lineLimit(1)
            }
        } else if let summary = cleanupState.cachedSummary(for: scanner) {
            HStack(spacing: 6) {
                Text(ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file))
                    .font(.caption.weight(.bold))
                    .tabularFigures()
                    .foregroundStyle(summary.isStale ? MoraxTheme.textSecondary : (summary.bytes > 0 ? MoraxTheme.textPrimary : MoraxTheme.textMuted))
                
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(MoraxTheme.textMuted)
                
                Text("\(summary.itemCount) élément\(summary.itemCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(MoraxTheme.textMuted)
                
                Text(relativeDateString(for: summary.scanDate))
                    .font(.caption2)
                    .foregroundStyle(MoraxTheme.textMuted)
                
                if scanner == .all {
                    let (available, total) = cleanupState.coverageSummary
                    if available < total {
                        Text("(\(available)/\(total) estimés · \(total - available) manquant\(total - available == 1 ? "" : "s"))")
                            .font(.caption2)
                            .foregroundStyle(MoraxTheme.warningAmber)
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MoraxTheme.textMuted)
                
                Text("Non estimé")
                    .font(.caption2)
                    .foregroundStyle(MoraxTheme.textMuted)
                
                if scanner == .all {
                    let (_, total) = cleanupState.coverageSummary
                    Text("(0/\(total) catégories)")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                }
            }
        }
    }
    
    @ViewBuilder
    private var estimateButton: some View {
        let isEstimatingThis = cleanupState.isEstimating && cleanupState.currentlyEstimatingScanner == scanner
        
        if !isEstimatingThis {
            Button(action: {
                cleanupState.estimate(scanner: scanner)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Estimer")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MoraxTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MoraxTheme.border, lineWidth: 1)
                )
                .clipShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(cleanupState.isEstimating)
            .opacity(cleanupState.isEstimating ? 0.4 : 1.0)
            .help("Lancer l'estimation en tâche de fond pour cette catégorie")
        }
    }
    
    private func relativeDateString(for date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "À l'instant"
        } else if seconds < 3600 {
            let mins = max(1, Int(seconds / 60))
            return "il y a \(mins) min"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "il y a \(hours) h"
        } else {
            let days = Int(seconds / 86400)
            return "il y a \(days) j"
        }
    }
}
