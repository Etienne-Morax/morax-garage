import SwiftUI
import AppKit
import MoraxCockpitKit

public struct StorageMapInspectorView: View {
    public let node: StorageNode?
    public let report: StorageScanReport?
    public let onZoomIn: ((StorageNode) -> Void)?
    
    private var stagingService = CleanupStagingService.shared
    @State private var stagedStatusMessage: String? = nil
    @State private var isCopied = false
    @State private var isShowingIssueList = false
    @State private var isShowingProtectedList = false
    
    public init(
        node: StorageNode?,
        report: StorageScanReport? = nil,
        onZoomIn: ((StorageNode) -> Void)? = nil
    ) {
        self.node = node
        self.report = report
        self.onZoomIn = onZoomIn
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(MoraxTheme.textSecondary)
                Text("Inspector")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MoraxTheme.surface)
            
            Divider().overlay(MoraxTheme.border)
            
            if let node = node {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        scanIntegritySection
                        
                        spaceAccountingSection
                        
                        // Title & Category
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: node.category.iconName)
                                .font(.system(size: 20))
                                .foregroundStyle(node.category.color)
                                .frame(width: 32, height: 32)
                                .background(node.category.color.opacity(0.15))
                                .clipShape(.rect(cornerRadius: 6))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(node.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(MoraxTheme.textPrimary)
                                    .lineLimit(2)
                                
                                Text(node.category.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(node.category.color.opacity(0.2))
                                    .foregroundStyle(node.category.color)
                                    .clipShape(.rect(cornerRadius: 4))
                            }
                        }
                        
                        // Full Path
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PATH")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MoraxTheme.textMuted)
                            
                            Text(node.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        
                        Divider().overlay(MoraxTheme.border)
                        
                        // Metrics Grid
                        VStack(spacing: 8) {
                            metricRow(label: "APFS Allocated", value: node.formattedAllocatedSize, isBold: true)
                            metricRow(label: "Logical Size", value: node.formattedLogicalSize, isBold: false)
                            
                            if node.datalessLogicalBytes > 0 {
                                metricRow(
                                    label: "Cloud non téléchargé",
                                    value: ByteCountFormatter.string(fromByteCount: node.datalessLogicalBytes, countStyle: .file),
                                    isBold: false
                                )
                            }
                            
                            if node.isDirectory {
                                metricRow(label: "Items Count", value: "\(node.itemCount) items", isBold: false)
                            }
                            
                            metricRow(label: "Modified", value: node.formattedDate, isBold: false)
                            
                            if node.isPackage {
                                badgeRow(label: "Type", badge: "macOS Package", color: MoraxTheme.infoBlue)
                            }
                            if node.isSymlink {
                                badgeRow(label: "Symlink", badge: "Symbolic Link", color: MoraxTheme.warningAmber)
                            }
                            if node.isCloudPlaceholder {
                                badgeRow(label: "Cloud", badge: "Dataless Cloud File", color: MoraxTheme.infoBlue)
                            }
                        }
                        .padding(10)
                        .background(MoraxTheme.surfaceSubtle)
                        .clipShape(.rect(cornerRadius: 6))
                        
                        // Folder Composition Breakdown
                        if node.isDirectory && !node.breakdownList.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("FOLDER COMPOSITION")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MoraxTheme.textMuted)
                                
                                ForEach(node.breakdownList.prefix(4), id: \.category) { item in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(item.category.color)
                                            .frame(width: 7, height: 7)
                                        Text(item.category.rawValue)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(MoraxTheme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(MoraxTheme.textSecondary)
                                        Text(String(format: "%.0f%%", item.percentage))
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(item.category.color)
                                    }
                                }
                            }
                            .padding(10)
                            .background(MoraxTheme.surfaceSubtle)
                            .clipShape(.rect(cornerRadius: 6))
                        }
                        
                        // Access / Error Warning
                        if let error = node.accessError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(MoraxTheme.warningAmber)
                                Text(error)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MoraxTheme.warningAmber)
                            }
                            .padding(8)
                            .background(MoraxTheme.warningAmber.opacity(0.15))
                            .clipShape(.rect(cornerRadius: 6))
                        }
                        
                        Divider().overlay(MoraxTheme.border)
                        
                        // Action Buttons
                        if node.isAggregate {
                            Text("Regroupement des petits éléments de ce dossier. Leur taille est comptée dans le total ; il n'y a pas de fichier unique à ouvrir ou supprimer.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                        VStack(spacing: 8) {
                            if node.isDirectory {
                                Button(action: { onZoomIn?(node) }) {
                                    HStack {
                                        Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                                        Text("Zoom Into Folder")
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            
                            Button(action: revealInFinder) {
                                HStack {
                                    Image(systemName: "folder")
                                    Text("Reveal in Finder")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(action: copyPath) {
                                HStack {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    Text(isCopied ? "Path Copied!" : "Copy Full Path")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(action: quickLook) {
                                HStack {
                                    Image(systemName: "eye")
                                    Text("Quick Look Preview")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Divider().overlay(MoraxTheme.border)
                            
                            // Safe Cleanup Staging Button
                            Button(action: stageForCleanup) {
                                HStack {
                                    Image(systemName: "trash.badge.plus")
                                    Text("Stage for Cleanup")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(MoraxTheme.oxbloodRed)
                            
                            if let status = stagedStatusMessage {
                                Text(status)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(status.contains("Cannot") ? MoraxTheme.oxbloodRed : MoraxTheme.successGreen)
                                    .padding(.top, 2)
                            }
                        }
                        }
                    }
                    .padding(14)
                }
            } else {
                VStack(spacing: 12) {
                    scanIntegritySection
                        .padding(14)
                    Spacer()
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 28))
                        .foregroundStyle(MoraxTheme.textMuted)
                    Text("Select an item on the Storage Map to inspect its details and actions.")
                        .font(.system(size: 11))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 280)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Space Accounting
    
    /// Every bucket of the volume, so the lines add up to the disk instead of stopping at
    /// what a walk can see.
    @ViewBuilder
    private var spaceAccountingSection: some View {
        if let reconciliation = report?.reconciliation, reconciliation.coversWholeVolume {
            VStack(alignment: .leading, spacing: 6) {
                Text("BILAN DU VOLUME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MoraxTheme.textMuted)
                
                accountingRow(
                    label: "Fichiers parcourus",
                    bytes: reconciliation.scannedAllocatedBytes,
                    color: MoraxTheme.infoBlue
                )

                if let sharedData = report?.sharedData, sharedData.totalBytes > 0 {
                    Text("hors \(ByteCountFormatter.string(fromByteCount: sharedData.totalBytes, countStyle: .file)) déjà comptés sous un autre nom (liens physiques \(ByteCountFormatter.string(fromByteCount: sharedData.hardlinkDuplicateBytes, countStyle: .file)), clones APFS \(ByteCountFormatter.string(fromByteCount: sharedData.cloneDuplicateBytes, countStyle: .file)))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(MoraxTheme.textMuted)
                        .padding(.leading, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(reconciliation.siblingVolumes) { volume in
                    accountingRow(
                        label: "Volume \(volume.displayName)",
                        bytes: volume.usedBytes,
                        color: MoraxTheme.textSecondary,
                        note: volume.isReadable ? nil : "non lisible"
                    )
                }
                
                if reconciliation.unaccountedBytes > 0 {
                    accountingRow(
                        label: "Non parcouru",
                        bytes: reconciliation.unaccountedBytes,
                        color: reconciliation.exceedsTolerance ? MoraxTheme.oxbloodRed : MoraxTheme.warningAmber
                    )
                    
                    if reconciliation.purgeableBytes > 0 {
                        Text("dont ≈ \(ByteCountFormatter.string(fromByteCount: reconciliation.purgeableBytes, countStyle: .file)) purgeables (instantanés locaux, caches que macOS libère sous pression)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(MoraxTheme.textMuted)
                            .padding(.leading, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Divider().overlay(MoraxTheme.border)
                
                accountingRow(
                    label: "Utilisé sur le volume",
                    bytes: reconciliation.volumeUsedBytes,
                    color: MoraxTheme.textPrimary,
                    isBold: true
                )
                accountingRow(
                    label: "Capacité totale",
                    bytes: reconciliation.volumeTotalBytes,
                    color: MoraxTheme.textSecondary
                )
                
                if reconciliation.datalessLogicalBytes > 0 {
                    Text("Hors disque : \(ByteCountFormatter.string(fromByteCount: reconciliation.datalessLogicalBytes, countStyle: .file)) de fichiers cloud non téléchargés.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(MoraxTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(MoraxTheme.surfaceSubtle)
            .clipShape(.rect(cornerRadius: 6))
        }
    }
    
    private func accountingRow(
        label: String,
        bytes: Int64,
        color: Color,
        note: String? = nil,
        isBold: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10.5, weight: isBold ? .semibold : .regular))
                .foregroundStyle(MoraxTheme.textPrimary)
                .lineLimit(1)
            if let note {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(MoraxTheme.textMuted)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.system(size: 10, weight: isBold ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(MoraxTheme.textSecondary)
        }
    }
    
    // MARK: - Scan Integrity
    
    /// A scan that was denied directories is reported here, with the paths, so the total
    /// above is never read as the whole truth.
    @ViewBuilder
    private var scanIntegritySection: some View {
        incompleteScanBlock
        systemProtectedNote
    }

    @ViewBuilder
    private var incompleteScanBlock: some View {
        if let report, report.unreadableCount > 0 || (report.reconciliation?.exceedsTolerance ?? false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MoraxTheme.warningAmber)
                        .font(.system(size: 12))
                    Text("SCAN INCOMPLET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MoraxTheme.warningAmber)
                }
                
                Text(integrityHeadline(report))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let reconciliation = report.reconciliation {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Volume : \(ByteCountFormatter.string(fromByteCount: reconciliation.volumeUsedBytes, countStyle: .file)) utilisés")
                        Text("Scanné : \(ByteCountFormatter.string(fromByteCount: reconciliation.scannedAllocatedBytes, countStyle: .file))")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                if report.datalessLogicalBytes > 0 {
                    Text("Dont \(ByteCountFormatter.string(fromByteCount: report.datalessLogicalBytes, countStyle: .file)) de fichiers cloud non téléchargés (taille logique, aucun octet local).")
                        .font(.system(size: 10))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if !report.blockingIssues.isEmpty {
                    Button(action: { isShowingIssueList.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isShowingIssueList ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(isShowingIssueList ? "Masquer la liste" : "Voir les chemins refusés")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(MoraxTheme.infoBlue)
                    }
                    .buttonStyle(.plain)
                    
                    if isShowingIssueList {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(report.blockingIssues) { issue in
                                    Text(issue.path)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(MoraxTheme.textSecondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                
                                if report.unreadableCount > report.blockingIssues.count {
                                    Text("+ \(report.unreadableCount - report.blockingIssues.count) autres")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(MoraxTheme.textMuted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                }
                
                // Only a TCC refusal is lifted by Full Disk Access; offering it for a POSIX
                // refusal sends the user to a setting that changes nothing.
                if report.needsFullDiskAccess {
                    Button("Accorder l'accès complet au disque") {
                        PermissionsService.shared.openAllFilesSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(MoraxTheme.warningAmber)
                }
            }
            .padding(10)
            .background(MoraxTheme.warningAmber.opacity(0.12))
            .clipShape(.rect(cornerRadius: 6))
        }
    }

    /// Root-only items are listed apart: they do not make the scan incomplete, and no
    /// permission the user can grant would open them.
    @ViewBuilder
    private var systemProtectedNote: some View {
        if let report, report.systemProtectedCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { isShowingProtectedList.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("\(report.systemProtectedCount) éléments système protégés (root)")
                            .font(.system(size: 10.5, weight: .semibold))
                        Image(systemName: isShowingProtectedList ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(MoraxTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Text("Illisibles par toute app sans privilèges root, accès complet au disque compris. Ils n'affectent pas la complétude du scan.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(MoraxTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if isShowingProtectedList {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(report.systemProtectedIssues) { issue in
                            Text(issue.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MoraxTheme.surface)
            .clipShape(.rect(cornerRadius: 6))
        }
    }
    
    private func integrityHeadline(_ report: StorageScanReport) -> String {
        let unreadable = report.unreadableCount
        let unaccounted = report.reconciliation?.exceedsTolerance == true
            ? report.reconciliation?.formattedUnaccounted
            : nil
        
        switch (unreadable, unaccounted) {
        case let (count, .some(bytes)) where count > 0:
            return "\(count) dossiers non lus — \(bytes) potentiellement non comptés"
        case let (count, .none) where count > 0:
            return "\(count) dossiers non lus"
        case let (_, .some(bytes)):
            return "\(bytes) potentiellement non comptés"
        default:
            return "Scan incomplet"
        }
    }
    
    private func metricRow(label: String, value: String, isBold: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(MoraxTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: isBold ? .bold : .regular, design: .monospaced))
                .foregroundStyle(MoraxTheme.textPrimary)
        }
    }
    
    private func badgeRow(label: String, badge: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(MoraxTheme.textSecondary)
            Spacer()
            Text(badge)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.2))
                .foregroundStyle(color)
                .clipShape(.rect(cornerRadius: 3))
        }
    }
    
    private func revealInFinder() {
        guard let node = node else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
    
    private func copyPath() {
        guard let node = node else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
        isCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isCopied = false
        }
    }
    
    private func quickLook() {
        guard let node = node else { return }
        // Preview only: never open or launch the file (a .command would run).
        QuickLookPreviewer.shared.preview(node.url)
    }
    
    private func stageForCleanup() {
        guard let node = node else { return }
        let result = stagingService.stageNode(node)
        switch result {
        case .success:
            stagedStatusMessage = "Added to Cleanup Queue"
        case .failure(let error):
            stagedStatusMessage = "Cannot stage: \(error.localizedDescription)"
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            stagedStatusMessage = nil
        }
    }
}
