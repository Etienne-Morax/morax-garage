import SwiftUI
import AppKit
import MoraxCockpitKit

public struct StorageMapView: View {
    private let stateService = StorageMapStateService.shared
    private var stagingService = CleanupStagingService.shared
    
    @State private var selectedNode: StorageNode? = nil
    @State private var selectedCategoryFilter: StorageCategory? = nil
    @State private var isShowingPathPrompt: Bool = false
    @State private var isInspectorVisible: Bool = true
    
    public init() {}
    
    private var activeNode: StorageNode? {
        stateService.activeNode
    }
    
    private var breadcrumbs: [StorageNode] {
        guard let active = activeNode else { return [] }
        return active.breadcrumbs
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Header: Controls & Presets
            headerControlsView
            
            Divider().overlay(MoraxTheme.border)
            
            fullDiskAccessBanner
            
            scanIntegrityBanner
            
            // Staged Items Banner (if any)
            if stagingService.hasStagedItems {
                stagedItemsBanner
                Divider().overlay(MoraxTheme.border)
            }
            
            // Breadcrumbs & Zoom Bar
            if let active = activeNode {
                breadcrumbBar(active: active)
                Divider().overlay(MoraxTheme.border)
            }
            
            // Main Map & Inspector Split
            HStack(spacing: 0) {
                // Map Area + Category Breakdown
                VStack(spacing: 0) {
                    if stateService.isScanning {
                        scanningStateView
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else if stateService.isRestoringCache && activeNode == nil {
                        restoringCacheStateView
                            .transition(.opacity)
                    } else if let active = activeNode {
                        treemapContainerView(active: active)
                            .transition(.opacity)
                        
                        Divider().overlay(MoraxTheme.border)
                        
                        // Category breakdown bar
                        categoryBreakdownView(node: active)
                    } else {
                        emptyStateView
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: stateService.isScanning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                
                if isInspectorVisible {
                    Divider().overlay(MoraxTheme.border)
                    
                    // Right Inspector Pane
                    StorageMapInspectorView(
                        node: selectedNode ?? activeNode,
                        report: stateService.scanReport,
                        onZoomIn: { node in
                            if node.isDirectory {
                                stateService.currentZoomNode = node
                                selectedNode = nil
                            }
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(CleanMyMacBackground())
        .sheet(isPresented: $isShowingPathPrompt) {
            DirectPathEntrySheet(
                initialPath: stateService.targetURL.path,
                onSelectURL: { url in
                    selectPreset(url)
                }
            )
        }
        .task {
            // The snapshot is decoded off the main actor, so opening the tab stays instant
            // however large the last scan was.
            await stateService.restoreCacheFromDisk()
            
            // Only auto-start on very first launch, and only once the restore has had its
            // say: starting a scan over a snapshot about to land would throw it away.
            if stateService.hasAttemptedRestore
                && stateService.rootNode == nil
                && !stateService.isScanning
                && stateService.lastScanDate == nil {
                stateService.startScan()
            }
        }
    }
    
    // MARK: - Header Controls
    private var headerControlsView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Title
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.square")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MoraxTheme.infoBlue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Storage Map")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        HStack(spacing: 6) {
                            Text("Squarified APFS treemap with zero-download cloud safety")
                                .font(.caption2)
                                .foregroundStyle(MoraxTheme.textSecondary)
                            
                            if let scanTime = stateService.formattedLastScanDate {
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
                }
                
                Spacer()
                
                // Presets Menu
                Menu {
                    Section("Dossiers Courants") {
                        Button {
                            selectPreset(FileManager.default.homeDirectoryForCurrentUser)
                        } label: {
                            Label("Dossier Utilisateur (~)", systemImage: "house")
                        }
                        
                        Button {
                            selectPreset(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
                        } label: {
                            Label("Documents (~/Documents)", systemImage: "doc")
                        }
                        
                        Button {
                            selectPreset(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                        } label: {
                            Label("Téléchargements (~/Downloads)", systemImage: "arrow.down.circle")
                        }
                        
                        Button {
                            selectPreset(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
                        } label: {
                            Label("Bureau (~/Desktop)", systemImage: "menubar.dock.rectangle")
                        }
                        
                        Button {
                            selectPreset(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects"))
                        } label: {
                            Label("Projets Développeur (~/Projects)", systemImage: "hammer")
                        }
                        
                        Button {
                            let resCache = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve")
                            selectPreset(resCache)
                        } label: {
                            Label("DaVinci Resolve Cache", systemImage: "film")
                        }
                        
                        Button {
                            selectPreset(URL(fileURLWithPath: "/Applications"))
                        } label: {
                            Label("Applications (/Applications)", systemImage: "app.badge")
                        }
                        
                        Button {
                            selectPreset(URL(fileURLWithPath: "/"))
                        } label: {
                            Label("Disque Système (/)", systemImage: "internaldrive")
                        }
                    }
                    
                    Divider()
                    
                    Section("Dossier Personnalisé") {
                        Button {
                            chooseCustomFolder()
                        } label: {
                            Label("Parcourir un dossier...", systemImage: "folder.badge.plus")
                        }
                        
                        Button {
                            isShowingPathPrompt = true
                        } label: {
                            Label("Entrer un chemin direct...", systemImage: "character.cursor.ibeam")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                        Text(folderDisplayName(stateService.targetURL))
                            .lineLimit(1)
                            .help(stateService.targetURL.path)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Scan / Cancel / Refresh Button
                if stateService.isScanning {
                    Button(role: .destructive, action: { stateService.cancelScan() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Annuler")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MoraxTheme.oxbloodRed)
                    .controlSize(.small)
                } else {
                    Button(action: {
                        selectedNode = nil
                        stateService.startScan()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: stateService.rootNode == nil ? "magnifyingglass" : "arrow.clockwise")
                            Text(stateService.rootNode == nil ? "Lancer l'analyse" : "Actualiser")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Full Disk Access Banner
    
    /// Non blocking: the scan still runs without the grant, it just cannot see everything.
    private var fullDiskAccessBanner: some View {
        FullDiskAccessObserver { hasAccess, service in
            if !hasAccess {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(MoraxTheme.warningAmber)
                            .font(.system(size: 14))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Accès complet au disque non accordé")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            Text("Photothèque, sauvegardes iPhone, caches navigateurs et Google Drive restent invisibles : le total affiché sera sous-évalué.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button("Ouvrir les Réglages") {
                            service.openAllFilesSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MoraxTheme.warningAmber)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(MoraxTheme.warningAmber.opacity(0.12))
                    
                    Divider().overlay(MoraxTheme.border)
                }
            }
        }
    }
    
    // MARK: - Scan Integrity Banner
    
    /// An incomplete scan must never look complete, so unreadable paths and a volume level
    /// mismatch are surfaced next to the total they affect.
    @ViewBuilder
    private var scanIntegrityBanner: some View {
        if let report = stateService.scanReport,
           !stateService.isScanning,
           !report.isComplete {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MoraxTheme.oxbloodRed)
                    .font(.system(size: 13))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(scanIntegrityHeadline(report))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    if let reconciliation = report.reconciliation, reconciliation.exceedsTolerance {
                        Text("Le volume déclare \(ByteCountFormatter.string(fromByteCount: reconciliation.volumeUsedBytes, countStyle: .file)) utilisés, le scan n'en retrouve que \(ByteCountFormatter.string(fromByteCount: reconciliation.scannedAllocatedBytes, countStyle: .file)).")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                Text("Détails dans l'inspecteur")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MoraxTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(MoraxTheme.oxbloodRed.opacity(0.12))
            
            Divider().overlay(MoraxTheme.border)
        }
    }
    
    private func scanIntegrityHeadline(_ report: StorageScanReport) -> String {
        let unreadable = report.unreadableCount
        if unreadable > 0, let reconciliation = report.reconciliation, reconciliation.exceedsTolerance {
            return "Scan incomplet : \(unreadable) dossiers non lus — \(reconciliation.formattedUnaccounted) potentiellement non comptés"
        }
        if unreadable > 0 {
            return "Scan incomplet : \(unreadable) dossiers non lus"
        }
        if let reconciliation = report.reconciliation, reconciliation.exceedsTolerance {
            return "Écart avec le volume : \(reconciliation.formattedUnaccounted) non comptés (\(String(format: "%.0f", reconciliation.discrepancyRatio * 100)) %)"
        }
        return "Scan incomplet"
    }
    
    // MARK: - Breadcrumb Navigation Bar
    private func breadcrumbBar(active: StorageNode) -> some View {
        HStack(spacing: 6) {
            // Up Button
            Button(action: zoomOutOneLevel) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(active.parent == nil)
            .foregroundStyle(active.parent == nil ? MoraxTheme.textMuted : MoraxTheme.textPrimary)
            .padding(.trailing, 4)
            
            // Breadcrumbs Trail
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(breadcrumbs) { crumb in
                        let isLast = (crumb.id == active.id)
                        Button(action: {
                            stateService.currentZoomNode = (crumb.id == stateService.rootNode?.id) ? nil : crumb
                            selectedNode = nil
                        }) {
                            HStack(spacing: 4) {
                                if crumb.parent == nil {
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 10))
                                }
                                Text(crumb.name)
                                    .font(.system(size: 11, weight: isLast ? .bold : .regular))
                                    .foregroundStyle(isLast ? MoraxTheme.textPrimary : MoraxTheme.infoBlue)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isLast ? MoraxTheme.surfaceSubtle : Color.clear)
                            .clipShape(.rect(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        
                        if !isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(MoraxTheme.textMuted)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            
            Spacer()
            
            // Depth Selector Menu
            Menu {
                Button("Top Folders Only (1 Level)") { stateService.maxDepth = 1 }
                Button("Standard View (2 Levels)") { stateService.maxDepth = 2 }
                Button("Detailed View (3 Levels)") { stateService.maxDepth = 3 }
                Button("Deep Files View (4 Levels)") { stateService.maxDepth = 4 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 10))
                    Text("Depth: \(stateService.maxDepth)")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MoraxTheme.surfaceSubtle)
                .foregroundStyle(MoraxTheme.textSecondary)
                .clipShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            
            // Sub-tree stats & Inspector toggle
            HStack(spacing: 8) {
                Text(active.formattedAllocatedSize)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                if active.itemCount > 0 {
                    Text("\(active.itemCount) items")
                        .font(.system(size: 10))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isInspectorVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isInspectorVisible ? MoraxTheme.infoBlue : MoraxTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isInspectorVisible ? MoraxTheme.infoBlue.opacity(0.14) : MoraxTheme.surfaceSubtle)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help(isInspectorVisible ? "Masquer l'inspecteur pour agrandir la carte" : "Afficher l'inspecteur de détails")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Treemap Container
    private func treemapContainerView(active: StorageNode) -> some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let items = TreemapLayoutEngine.computeLayout(
                for: active,
                in: bounds,
                maxDepth: stateService.maxDepth
            )
            
            TreemapCanvasView(
                renderItems: items,
                selectedNode: selectedNode,
                onSelectNode: { node in
                    selectedNode = node
                },
                onDoubleClickNode: { node in
                    if node.isDirectory {
                        stateService.currentZoomNode = node
                        selectedNode = nil
                    }
                }
            )
        }
    }
    
    // MARK: - Category Breakdown Footer
    private func categoryBreakdownView(node: StorageNode) -> some View {
        let categoryGroups = computeCategoryTotals(node: node)
        let totalSize = max(1, categoryGroups.reduce(Int64(0)) { $0 + $1.size })
        
        return VStack(spacing: 6) {
            // Segmented colored proportion bar
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(categoryGroups, id: \.category) { group in
                        let width = max(2, geometry.size.width * CGFloat(Double(group.size) / Double(totalSize)))
                        Rectangle()
                            .fill(group.category.color)
                            .frame(width: width)
                    }
                }
                .clipShape(.rect(cornerRadius: 3))
            }
            .frame(height: 6)
            
            // Category badges wrapping dynamically so all categories are always visible
            StorageMapFlowLayout(horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(categoryGroups, id: \.category) { group in
                    let pct = Double(group.size) / Double(totalSize) * 100
                    HStack(spacing: 4) {
                        Circle()
                            .fill(group.category.color)
                            .frame(width: 7, height: 7)
                        
                        Text(group.category.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        Text(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textSecondary)
                        
                        Text("(\((pct / 100).formatted(.percent.precision(.fractionLength(1))))")
                            .font(.system(size: 9))
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                }
            }
            
            // Placeholders are kept out of the proportional bar on purpose: they weigh
            // nothing on this disk. Their logical size is reported on its own line.
            if node.datalessLogicalBytes > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(StorageCategory.cloudNotDownloaded.color)
                        .frame(width: 7, height: 7)
                    Text(StorageCategory.cloudNotDownloaded.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text(ByteCountFormatter.string(fromByteCount: node.datalessLogicalBytes, countStyle: .file))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Text("taille logique — 0 octet local")
                        .font(.system(size: 9))
                        .foregroundStyle(MoraxTheme.textMuted)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Staged Items Notification Banner
    private var stagedItemsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .foregroundStyle(MoraxTheme.oxbloodRed)
                .font(.system(size: 14))
            
            Text("\(stagingService.stagedItems.count) items staged for cleanup (\(stagingService.formattedTotalStagedBytes))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MoraxTheme.textPrimary)
            
            Spacer()
            
            Button("Clear") {
                stagingService.clearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MoraxTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(MoraxTheme.oxbloodRed.opacity(0.12))
    }
    
    // MARK: - Scanning State
    private var scanningStateView: some View {
        VStack(spacing: 20) {
            AnimatedScanningRadarView()
            
            VStack(spacing: 6) {
                Text("Analyse du stockage en cours...")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(MoraxTheme.infoBlue)
                        .font(.system(size: 13))
                    Text(folderDisplayName(stateService.targetURL))
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                
                Text(stateService.targetURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(MoraxTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
            }
            
            // Live Stats Card
            if let progress = stateService.scanProgress {
                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        VStack(spacing: 2) {
                            Text("\(progress.scannedCount)")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(MoraxTheme.infoBlue)
                            Text("éléments analysés")
                                .font(.caption2)
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                        
                        Divider().frame(height: 28)
                        
                        VStack(spacing: 2) {
                            Text(ByteCountFormatter.string(fromByteCount: progress.scannedAllocatedBytes, countStyle: .file))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(MoraxTheme.successGreen)
                            Text("espace répertorié")
                                .font(.caption2)
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(MoraxTheme.surface)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(MoraxTheme.border, lineWidth: 1)
                    )
                    
                    // Live Path Stream
                    HStack(spacing: 6) {
                        Circle()
                            .fill(MoraxTheme.warningAmber)
                            .frame(width: 6, height: 6)
                        
                        Text(progress.currentPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 460)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(MoraxTheme.surface.opacity(0.6))
                    .clipShape(.capsule)
                }
            } else {
                ProgressView()
                    .controlSize(.regular)
            }
            
            // Cancel Button
            Button(role: .destructive, action: { stateService.cancelScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Annuler l'analyse")
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(MoraxTheme.oxbloodRed)
            .controlSize(.small)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
    
    // MARK: - Restoring State
    private var restoringCacheStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            
            Text("Restauration de la dernière analyse...")
                .font(.headline)
                .foregroundStyle(MoraxTheme.textPrimary)
            
            Text("Aucune nouvelle analyse n'est lancée : la carte provient du cache.")
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.system(size: 40))
                .foregroundStyle(MoraxTheme.textMuted)
            
            Text("Aucune carte de stockage disponible")
                .font(.headline)
                .foregroundStyle(MoraxTheme.textPrimary)
            
            Text("Dossier cible : \(folderDisplayName(stateService.targetURL))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MoraxTheme.textSecondary)
            
            Text(stateService.targetURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(MoraxTheme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 450)
            
            if let errorMsg = stateService.lastErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MoraxTheme.oxbloodRed)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.oxbloodRed)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(MoraxTheme.oxbloodRed.opacity(0.12))
                .clipShape(.rect(cornerRadius: 6))
            }
            
            HStack(spacing: 12) {
                Button(action: { stateService.startScan() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Analyser \"\(folderDisplayName(stateService.targetURL))\"")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.infoBlue)
                .controlSize(.regular)
                
                Button(action: { chooseCustomFolder() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                        Text("Changer de dossier...")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    private func selectPreset(_ url: URL) {
        selectedNode = nil
        stateService.startScan(url: url)
    }
    
    private func chooseCustomFolder() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.resolvesAliases = true
            panel.directoryURL = stateService.targetURL
            panel.prompt = "Analyser ce dossier"
            panel.message = "Choisissez n'importe quel dossier à analyser"
            panel.title = "Sélectionner un dossier"
            
            if panel.runModal() == .OK, let url = panel.url {
                selectPreset(url)
            }
        }
    }
    
    private func folderDisplayName(_ url: URL) -> String {
        if url.path == "/" {
            return "Disque Système (/)"
        }
        if url.path == FileManager.default.homeDirectoryForCurrentUser.path {
            return "Dossier Personnel (~)"
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
    
    private func zoomOutOneLevel() {
        guard let current = stateService.currentZoomNode else { return }
        if let parent = current.parent, parent.id != stateService.rootNode?.id {
            stateService.currentZoomNode = parent
        } else {
            stateService.currentZoomNode = nil
        }
        selectedNode = nil
    }
    
    private func computeCategoryTotals(node: StorageNode) -> [(category: StorageCategory, size: Int64)] {
        if !node.categoryBreakdown.isEmpty {
            return node.categoryBreakdown
                .filter { $0.value > 0 }
                .map { ($0.key, $0.value) }
                .sorted { $0.size > $1.size }
        }
        
        var totals: [StorageCategory: Int64] = [:]
        
        func collect(n: StorageNode) {
            if !n.isDirectory || n.isPackage {
                let sz = n.allocatedSizeBytes
                if sz > 0 {
                    totals[n.category, default: 0] += sz
                }
            } else {
                for child in n.children {
                    collect(n: child)
                }
            }
        }
        
        collect(n: node)
        
        return totals
            .filter { $0.value > 0 }
            .map { ($0.key, $0.value) }
            .sorted { $0.size > $1.size }
    }
}

// MARK: - Flow Layout for Legend Badges
public struct StorageMapFlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    
    public init(horizontalSpacing: CGFloat = 10, verticalSpacing: CGFloat = 4) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            currentX += size.width + horizontalSpacing
            maxWidth = max(maxWidth, currentX - horizontalSpacing)
            lineHeight = max(lineHeight, size.height)
        }
        
        return CGSize(width: min(width, maxWidth), height: currentY + lineHeight)
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Direct Path Entry Modal Sheet
public struct DirectPathEntrySheet: View {
    let initialPath: String
    let onSelectURL: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var pathText: String = ""
    @State private var errorMessage: String? = nil
    
    public init(initialPath: String, onSelectURL: @escaping (URL) -> Void) {
        self.initialPath = initialPath
        self.onSelectURL = onSelectURL
        self._pathText = State(initialValue: initialPath)
    }
    
    private func validateAndSubmit() {
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Veuillez entrer un chemin de dossier."
            return
        }
        
        var resolvedPath = trimmed
        if resolvedPath.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            resolvedPath = home + resolvedPath.dropFirst(1)
        }
        
        let url = URL(fileURLWithPath: resolvedPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                dismiss()
                onSelectURL(url)
            } else {
                errorMessage = "Le chemin spécifié est un fichier, pas un dossier."
            }
        } else {
            errorMessage = "Ce dossier n'existe pas : \(url.path)"
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)
                        .foregroundStyle(MoraxTheme.infoBlue)
                    Text("Entrer un chemin de dossier")
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            
            Text("Entrez le chemin absolu ou relatif avec ~ pour scanner n'importe quel répertoire, volume externe ou sous-dossier.")
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
            
            VStack(alignment: .leading, spacing: 6) {
                TextField("Ex: /Users/... ou ~/Documents/Claude ou /Volumes/SSD", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        validateAndSubmit()
                    }
                
                if let err = errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text(err)
                            .font(.caption2)
                    }
                    .foregroundStyle(MoraxTheme.oxbloodRed)
                }
            }
            
            HStack {
                Button("Parcourir avec Finder...") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.resolvesAliases = true
                        panel.prompt = "Analyser ce dossier"
                        if panel.runModal() == .OK, let url = panel.url {
                            onSelectURL(url)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button("Annuler") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(MoraxTheme.textSecondary)
                
                Button("Analyser ce dossier") {
                    validateAndSubmit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
        .background(MoraxTheme.surface)
    }
}

// MARK: - Animated Scanning Radar
public struct AnimatedScanningRadarView: View {
    @State private var isPulsing = false
    @State private var rotationAngle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}
    
    public var body: some View {
        ZStack {
            // Pulse circle 1
            Circle()
                .stroke(MoraxTheme.infoBlue.opacity(0.35), lineWidth: 1.5)
                .frame(width: 80, height: 80)
                .scaleEffect(isPulsing ? 1.45 : 0.8)
                .opacity(isPulsing ? 0.0 : 0.8)
            
            // Pulse circle 2
            Circle()
                .stroke(MoraxTheme.infoBlue.opacity(0.5), lineWidth: 1)
                .frame(width: 60, height: 60)
                .scaleEffect(isPulsing ? 1.3 : 0.9)
                .opacity(isPulsing ? 0.1 : 0.7)
            
            // Rotating radar beam
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            MoraxTheme.infoBlue.opacity(0),
                            MoraxTheme.infoBlue.opacity(0.1),
                            MoraxTheme.infoBlue.opacity(0.6),
                            MoraxTheme.infoBlue
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(rotationAngle))
            
            // Center Folder Icon Base
            Circle()
                .fill(MoraxTheme.surface)
                .frame(width: 48, height: 48)
                .shadow(color: MoraxTheme.infoBlue.opacity(0.3), radius: 8, x: 0, y: 0)
            
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MoraxTheme.infoBlue)
        }
        .frame(width: 100, height: 100)
        .onAppear {
            // Under Reduce Motion the radar stays still instead of looping for the whole scan.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}



