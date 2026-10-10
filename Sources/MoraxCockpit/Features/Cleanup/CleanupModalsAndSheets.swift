import SwiftUI
import MoraxCockpitKit

struct ConfirmationModalView: View {
    @Binding var confirmationText: String
    @Bindable private var cleanupState = CleanupStateService.shared
    
    var body: some View {
        let riskSummary = cleanupState.selectionRiskSummary
        let hasDestructive = cleanupState.hasSelectedDestructiveItems
        let isLargeBatch = cleanupState.totalReclaimableBytes >= CleanupView.typedConfirmationSizeThreshold
        let needsTypedConfirmation = hasDestructive || isLargeBatch
        let isConfirmed = !needsTypedConfirmation || (confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "TRASH")
        
        return VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: hasDestructive ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(MoraxTheme.oxbloodRed)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(needsTypedConfirmation ? "Destructive Confirmation Required" : "Confirm Move to Trash")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text("Items will be moved to macOS Trash. Nothing is permanently deleted.")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
            }
            
            Divider().overlay(MoraxTheme.border)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Total items to trash:")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                    Text("\(cleanupState.selectedCount) items")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                
                HStack {
                    Text("Estimated space freed:")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cleanupState.totalReclaimableBytes, countStyle: .file))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                
                Divider().overlay(MoraxTheme.border.opacity(0.5))
                
                // Risk Breakdown
                VStack(spacing: 6) {
                    if riskSummary.safe > 0 {
                        HStack {
                            Circle().fill(MoraxTheme.successGreen).frame(width: 8, height: 8)
                            Text("Safe items:")
                                .font(.caption)
                                .foregroundStyle(MoraxTheme.textSecondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: riskSummary.safe, countStyle: .file))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                    }
                    
                    if riskSummary.rebuild > 0 {
                        HStack {
                            Circle().fill(MoraxTheme.warningAmber).frame(width: 8, height: 8)
                            Text("Rebuild cost items:")
                                .font(.caption)
                                .foregroundStyle(MoraxTheme.textSecondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: riskSummary.rebuild, countStyle: .file))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                    }
                    
                    if riskSummary.destructive > 0 {
                        HStack {
                            Circle().fill(MoraxTheme.oxbloodRed).frame(width: 8, height: 8)
                            Text("Destructive items (data loss / transcripts):")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(MoraxTheme.oxbloodRed)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: riskSummary.destructive, countStyle: .file))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(MoraxTheme.oxbloodRed)
                        }
                    }
                }
            }
            .padding(16)
            .background(MoraxTheme.surfaceSubtle)
            .clipShape(.rect(cornerRadius: 8))
            
            if needsTypedConfirmation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                        Text(hasDestructive
                             ? "Selected items include user data, transcripts, project snapshots, or active session state."
                             : "Large batch selected — review the list before confirming.")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                    }
                    
                    Text("Type TRASH to confirm moving destructive items:")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    TextField("TRASH", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(12)
                .background(MoraxTheme.oxbloodRed.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MoraxTheme.oxbloodRed.opacity(0.3), lineWidth: 1)
                )
                .clipShape(.rect(cornerRadius: 6))
            }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    confirmationText = ""
                    cleanupState.flowState = .results
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
                .keyboardShortcut("[", modifiers: .command)
                
                Button(action: {
                    cleanupState.executeTrash(confirmDestructive: true)
                }) {
                    Text("Move to Trash")
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.oxbloodRed)
                .disabled(!isConfirmed)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(MoraxTheme.surface)
    }
}

struct FileItemRow: View {
    @Binding var item: FileItem
    
    var body: some View {
        HStack(spacing: 12) {
            if item.riskTier == .blocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textMuted)
                    .frame(width: 16, height: 16)
            } else {
                Toggle("", isOn: $item.isSelected)
                    .labelsHidden()
                    .accessibilityLabel("Select \(item.name)")
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(item.riskTier == .blocked ? MoraxTheme.textSecondary : MoraxTheme.textPrimary)
                    
                    tierBadge(tier: item.riskTier)
                    
                    if item.isRecent {
                        Text("RECENT (7D)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(MoraxTheme.warningAmber.opacity(0.2))
                            .foregroundStyle(MoraxTheme.warningAmber)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                
                Text(item.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if !item.riskReason.isEmpty && item.riskTier != .safe {
                    Text(item.riskReason)
                        .font(.caption2)
                        .foregroundStyle(reasonColor(for: item.riskTier))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedSize)
                    .font(.callout.weight(.semibold))
                    .tabularFigures()
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Text(item.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(MoraxTheme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func tierBadge(tier: RiskTier) -> some View {
        switch tier {
        case .safe:
            EmptyView()
        case .rebuildCost:
            Text("REBUILD")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(MoraxTheme.warningAmber.opacity(0.18))
                .foregroundStyle(MoraxTheme.warningAmber)
                .clipShape(.rect(cornerRadius: 4))
        case .destructive:
            Text("DESTRUCTIVE")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(MoraxTheme.oxbloodRed.opacity(0.18))
                .foregroundStyle(MoraxTheme.oxbloodRed)
                .clipShape(.rect(cornerRadius: 4))
        case .blocked:
            Text("BLOCKED")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(MoraxTheme.textMuted.opacity(0.18))
                .foregroundStyle(MoraxTheme.textMuted)
                .clipShape(.rect(cornerRadius: 4))
        }
    }
    
    private func reasonColor(for tier: RiskTier) -> Color {
        switch tier {
        case .destructive:
            return MoraxTheme.oxbloodRed
        case .rebuildCost:
            return MoraxTheme.warningAmber
        case .blocked:
            return MoraxTheme.textMuted
        case .safe:
            return MoraxTheme.textSecondary
        }
    }
}

struct OperationLogSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logEntries: [OperationLogEntry] = []
    @State private var errorsOnly = false
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Operation Audit Log")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
                
                Toggle("Errors Only", isOn: $errorsOnly)
                    .onChange(of: errorsOnly) {
                        loadLog()
                    }
                
                Button(action: copyLog) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy Log")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(MoraxTheme.surface)
            
            Divider().overlay(MoraxTheme.border)
            
            List(logEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.action.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MoraxTheme.surfaceSubtle)
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .clipShape(.rect(cornerRadius: 4))
                        
                        Text(entry.outcome.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(entry.isError ? MoraxTheme.oxbloodRed.opacity(0.2) : MoraxTheme.successGreen.opacity(0.2))
                            .foregroundStyle(entry.isError ? MoraxTheme.oxbloodRed : MoraxTheme.successGreen)
                            .clipShape(.rect(cornerRadius: 4))
                        
                        Spacer()
                        
                        Text(entry.formattedLine.components(separatedBy: "] ").first?.replacing("[", with: "") ?? "")
                            .font(.caption2.monospaced())
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                    
                    Text(entry.absolutePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    if !entry.details.isEmpty {
                        Text(entry.details)
                            .font(.caption2)
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(CleanMyMacBackground())
        .onAppear {
            loadLog()
        }
    }
    
    private func loadLog() {
        logEntries = OperationLog.shared.readEntries(errorsOnly: errorsOnly)
    }
    
    private func copyLog() {
        let raw = OperationLog.shared.readRawLog()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
        isCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
}
