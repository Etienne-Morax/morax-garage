import AppKit
import SwiftUI
import MoraxCockpitKit

public struct CleanupView: View {
    /// Selection size above which the typed confirmation is demanded regardless of tier.
    static let typedConfirmationSizeThreshold: Int64 = 5 * 1024 * 1024 * 1024
    /// Per-item trash errors shown inline on the completion summary; the rest are in the log.
    static let maxListedTrashErrors = 5
    
    @Bindable private var cleanupState = CleanupStateService.shared
    @State private var showLogSheet = false
    @State private var confirmationText = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Cleanup & Cache Manager")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    HStack(spacing: 8) {
                        Text("Deterministic scanner with strict SafetyGate protection and Trash recovery")
                            .font(.subheadline)
                            .foregroundStyle(MoraxTheme.textSecondary)
                        
                        if let scanTime = cleanupState.formattedLastScanDate {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(MoraxTheme.textMuted)
                            
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text("Dernier scan : \(scanTime)")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(MoraxTheme.infoBlue)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { showLogSheet = true }) {
                    Label("Operation Log", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(24)
            .background(MoraxTheme.surface)
            
            Divider()
                .background(MoraxTheme.border)
            
            // Flow content
            Group {
                switch cleanupState.flowState {
                case .idle:
                    ScannerSelectionView()
                case .scanning(let progress):
                    scanningProgressView(progress: progress)
                case .results, .confirming:
                    CleanupResultsView(confirmationText: $confirmationText)
                case .trashing(let progress, let done, let total):
                    trashingProgressView(progress: progress, done: done, total: total)
                case .completed(let result):
                    completionSummaryView(result: result)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CleanMyMacBackground())
        .sheet(isPresented: $showLogSheet) {
            OperationLogSheetView()
        }
        .sheet(isPresented: $cleanupState.isConfirming) {
            ConfirmationModalView(confirmationText: $confirmationText)
        }
        .onChange(of: cleanupState.isConfirming) { _, isConfirming in
            if !isConfirming {
                confirmationText = ""
            }
        }
        // Background keyboard shortcuts for non-destructive step back navigation
        .background {
            backShortcutHandler
        }
    }
    
    @ViewBuilder
    private var backShortcutHandler: some View {
        Group {
            Button(action: handleBackNavigation) {
                EmptyView()
            }
            .keyboardShortcut("[", modifiers: .command)
            .opacity(0)
            
            Button(action: handleBackNavigation) {
                EmptyView()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
        }
    }
    
    private func handleBackNavigation() {
        switch cleanupState.flowState {
        case .idle:
            break
        case .scanning:
            cleanupState.cancelScan()
        case .results:
            cleanupState.switchToScannerSelection()
        case .confirming:
            confirmationText = ""
            cleanupState.flowState = .results
        case .trashing:
            // Intentional: Escape is ignored during trashing to protect ongoing batch
            break
        case .completed:
            cleanupState.resetToIdle()
        }
    }
    
    // MARK: - Step 2: Scanning Progress
    private func scanningProgressView(progress: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .controlSize(.large)
            
            Text("Scanning Filesystem...")
                .font(.headline)
                .foregroundStyle(MoraxTheme.textPrimary)
            
            Text(progress)
                .font(.caption.monospaced())
                .foregroundStyle(MoraxTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button(action: { cleanupState.cancelScan() }) {
                Text("Cancel Scan")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
            .keyboardShortcut("[", modifiers: .command)
            
            Spacer()
        }
    }
    
    // MARK: - Step 6: Trashing Progress
    private func trashingProgressView(progress: String, done: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView(value: Double(done), total: Double(max(1, total)))
                .frame(width: 320)
                .tint(MoraxTheme.oxbloodRed)
            
            Text("Trashing Items...")
                .font(.headline)
                .foregroundStyle(MoraxTheme.textPrimary)
            
            Text("\(done) of \(total) items processed")
                .font(.caption.monospacedDigit())
                .foregroundStyle(MoraxTheme.textSecondary)
            
            Button("Cancel") {
                cleanupState.cancelTrash()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
        }
    }
    
    private func openTrash() {
        guard let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first else { return }
        NSWorkspace.shared.open(trashURL)
    }

    // MARK: - Step 7: Completion Summary
    private func completionSummaryView(result: TrashBatchResult) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            MoraxMascotView(size: 72)
            
            VStack(spacing: 6) {
                Text("Cleanup Complete")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Text("Successfully reclaimed \(ByteCountFormatter.string(fromByteCount: result.totalReclaimedBytes, countStyle: .file))")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textSecondary)

                // The app never empties the Trash itself (spec rule 1), so the space is
                // only free once the user does.
                Text("Items are in the Trash — empty it to free the disk space.")
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textMuted)
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Succeeded items:")
                    Spacer()
                    Text("\(result.succeededCount)")
                        .fontWeight(.bold)
                }
                if result.skippedCount > 0 {
                    HStack {
                        Text("Skipped / errors:")
                        Spacer()
                        Text("\(result.skippedCount)")
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                            .fontWeight(.bold)
                    }
                    // Failed items were not trashed and remain in the results list.
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(result.errors.prefix(Self.maxListedTrashErrors).enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.caption2.monospaced())
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        if result.errors.count > Self.maxListedTrashErrors {
                            Text("+\(result.errors.count - Self.maxListedTrashErrors) more in the operation log")
                                .font(.caption2)
                                .foregroundStyle(MoraxTheme.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.caption)
            .frame(width: result.skippedCount > 0 ? 420 : 280)
            .padding(16)
            .background(MoraxTheme.surface)
            .clipShape(.rect(cornerRadius: 8))
            
            HStack(spacing: 12) {
                Button("Done") {
                    cleanupState.resetToIdle()
                }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.infoBlue)
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.escape, modifiers: [])
                .keyboardShortcut("[", modifiers: .command)

                if result.skippedCount > 0 {
                    Button("Review Remaining Items") {
                        cleanupState.flowState = .results
                    }
                    .buttonStyle(.bordered)
                }

                Button("View Operation Log") {
                    showLogSheet = true
                }
                .buttonStyle(.bordered)

                Button("Open Trash", action: openTrash)
                    .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding(24)
    }
}
