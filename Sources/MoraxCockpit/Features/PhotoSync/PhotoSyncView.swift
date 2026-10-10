import SwiftUI
import MoraxCockpitKit

/// Client photo projects along the Mac → SSD → NAS workflow.
public struct PhotoSyncView: View {
    @Bindable private var service = PhotoSyncStateService.shared
    @State private var filter: PhotoSyncFilter = .pending
    @State private var searchQuery = ""
    @State private var isShowingSettings = false
    @State private var errorMessage: String?

    public init() {}

    private var visibleProjects: [PhotoProjectStatus] {
        let retention = service.configuration.ssdRetentionDays
        return service.sortedProjects.filter { project in
            let matchesFilter = filter.includes(project.stage(retentionDays: retention))
            let matchesSearch = searchQuery.isEmpty || project.name.localizedStandardContains(searchQuery)
            return matchesFilter && matchesSearch
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MoraxTheme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryTiles
                    toolbar
                    projectList
                    if !service.jobs.isEmpty {
                        PhotoSyncJobsPanel(service: service)
                    }
                }
                .padding(24)
            }
        }
        .background(CleanMyMacBackground())
        .task { await service.scan(force: false) }
        .alert("Synchronisation impossible", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Sync Photos Clients")
                        .font(.title2).bold()
                        .foregroundStyle(MoraxTheme.textPrimary)
                    if service.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Vérification \(service.scanProgress.checked)/\(service.scanProgress.total)")
                            .font(.caption).tabularFigures()
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                }
                Text(lastScanText)
                    .font(.subheadline)
                    .foregroundStyle(MoraxTheme.textSecondary)
                if let warning = service.scanWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.warningAmber)
                }
            }
            Spacer()
            VolumeChip(title: "Mac", systemImage: "laptopcomputer", isOnline: true)
            VolumeChip(title: "SSD", systemImage: "externaldrive.fill", isOnline: service.isSSDOnline)
            VolumeChip(title: "NAS", systemImage: "server.rack", isOnline: service.isNASOnline)

            Button {
                isShowingSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Dossiers et durée de conservation")
            .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                PhotoSyncSettingsPopover(service: service)
            }

            if service.isScanning {
                Button("Arrêter", systemImage: "stop.fill") { service.cancelScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Vérifier", systemImage: "arrow.clockwise") {
                    Task { await service.scan(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(24)
        .background(MoraxTheme.surface)
    }

    private var lastScanText: String {
        guard let date = service.lastScanDate else {
            return "Compare chaque projet fichier par fichier : Mac → SSD → NAS"
        }
        return "Dernière vérification \(date.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Summary

    private var summaryTiles: some View {
        HStack(spacing: 12) {
            SummaryTile(title: "À copier sur SSD", value: service.count(of: .needsSSDCopy), systemImage: "externaldrive.badge.plus", tint: MoraxTheme.warningAmber)
            SummaryTile(title: "À archiver sur NAS", value: service.count(of: .needsNASArchive), systemImage: "server.rack", tint: MoraxTheme.neonViolet)
            SummaryTile(title: "Libérables du SSD", value: service.count(of: .readyToFreeSSD), systemImage: "checkmark.seal.fill", tint: MoraxTheme.electricCyan)
            SummaryTile(title: "À jour", value: service.count(of: .retainedOnSSD) + service.count(of: .archivedOnly), systemImage: "checkmark.circle.fill", tint: MoraxTheme.successGreen)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter) {
                ForEach(PhotoSyncFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(MoraxTheme.textMuted)
                TextField("Rechercher un projet…", text: $searchQuery).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(MoraxTheme.surfaceSubtle)
            .clipShape(.rect(cornerRadius: 6))
            .frame(maxWidth: 240)

            Spacer()

            Button("Tout copier sur SSD", systemImage: "externaldrive.badge.plus") {
                enqueueAll(leg: .macToSSD)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!service.isSSDOnline || batchCandidates(for: .macToSSD).isEmpty)
            .help("Copie sur le SSD tous les projets du Mac qui n'y sont pas à jour")

            Button("Tout mettre à jour sur NAS", systemImage: "server.rack") {
                enqueueAll(leg: .ssdToNAS)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!service.isNASOnline || batchCandidates(for: .ssdToNAS).isEmpty)
            .help("Complète les projets déjà rangés sur le NAS. Les nouveaux projets demandent de choisir leur catégorie.")
        }
    }

    /// Batch copies only cover projects whose destination is already known.
    private func batchCandidates(for leg: PhotoSyncLeg) -> [PhotoProjectStatus] {
        service.projects.filter { project in
            guard service.activeJob(for: project.key) == nil else { return false }
            switch leg {
            case .macToSSD: return project.macToSSD.needsSync
            case .ssdToNAS: return project.ssdToNAS.needsSync && project.nasPath != nil && !project.macToSSD.needsSync
            }
        }
    }

    private func enqueueAll(leg: PhotoSyncLeg) {
        for project in batchCandidates(for: leg) {
            enqueue(project, leg: leg, nasParent: nil)
        }
    }

    private func enqueue(_ project: PhotoProjectStatus, leg: PhotoSyncLeg, nasParent: String?) {
        do {
            try service.enqueueSync(for: project, leg: leg, nasParent: nasParent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - List

    @ViewBuilder
    private var projectList: some View {
        if service.projects.isEmpty && service.isScanning {
            HStack { Spacer(); ProgressView("Analyse des projets…"); Spacer() }
                .padding(.vertical, 40)
        } else if visibleProjects.isEmpty {
            ContentUnavailableView(
                filter == .pending ? "Tout est synchronisé" : "Aucun projet",
                systemImage: filter == .pending ? "checkmark.circle" : "photo.on.rectangle",
                description: Text(filter == .pending ? "Aucune copie en attente sur le SSD ni sur le NAS." : "Aucun projet ne correspond.")
            )
            .padding(.vertical, 30)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(visibleProjects) { project in
                    PhotoSyncProjectRow(
                        project: project,
                        retentionDays: service.configuration.ssdRetentionDays,
                        job: service.activeJob(for: project.key),
                        destinations: service.destinations,
                        isSSDOnline: service.isSSDOnline,
                        isNASOnline: service.isNASOnline,
                        onSync: { leg, parent in enqueue(project, leg: leg, nasParent: parent) },
                        onIgnore: { service.ignoreProject(project) }
                    )
                }
            }
        }
    }
}

// MARK: - Filter

enum PhotoSyncFilter: String, CaseIterable, Identifiable {
    case pending, ssd, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "À faire"
        case .ssd: return "Sur le SSD"
        case .all: return "Tous"
        }
    }

    func includes(_ stage: PhotoSyncStage) -> Bool {
        switch self {
        case .pending: return [.needsSSDCopy, .needsNASArchive, .readyToFreeSSD, .unknown].contains(stage)
        case .ssd: return [.readyToFreeSSD, .retainedOnSSD].contains(stage)
        case .all: return true
        }
    }
}

// MARK: - Small components

private struct VolumeChip: View {
    let title: String
    let systemImage: String
    let isOnline: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isOnline ? MoraxTheme.successGreen : MoraxTheme.textMuted)
            .background((isOnline ? MoraxTheme.successGreen : MoraxTheme.textMuted).opacity(0.12))
            .clipShape(.capsule)
            .help(isOnline ? "\(title) connecté" : "\(title) non connecté")
    }
}

private struct SummaryTile: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14))
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2.weight(.bold)).tabularFigures()
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .cleanGlassCard(cornerRadius: 12)
    }
}

private struct PhotoSyncSettingsPopover: View {
    let service: PhotoSyncStateService
    @State private var draft: PhotoSyncConfiguration

    init(service: PhotoSyncStateService) {
        self.service = service
        _draft = State(initialValue: service.configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emplacements").font(.headline)
            pathField("Mac (nouveaux jobs)", text: $draft.macRoot)
            pathField("SSD (un dossier par projet)", text: $draft.ssdRoot)
            pathField("NAS (racine des catégories)", text: $draft.nasRoot)
            Stepper(value: $draft.ssdRetentionDays, in: 7...365, step: 7) {
                Text("Garder sur le SSD : \(draft.ssdRetentionDays) jours")
            }
            HStack {
                if !service.configuration.ignoredProjectKeys.isEmpty {
                    Button("Réafficher \(service.configuration.ignoredProjectKeys.count) ignoré(s)") {
                        service.restoreIgnoredProjects()
                        draft = service.configuration
                    }
                }
                Spacer()
                Button("Enregistrer") {
                    let pathsChanged = draft.macRoot != service.configuration.macRoot
                        || draft.ssdRoot != service.configuration.ssdRoot
                        || draft.nasRoot != service.configuration.nasRoot
                    service.updateConfiguration(draft)
                    if pathsChanged {
                        Task { await service.scan(force: true) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == service.configuration)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func pathField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(MoraxTheme.textSecondary)
            HStack {
                TextField("", text: text).textFieldStyle(.roundedBorder)
                Button("Choisir…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.directoryURL = URL(fileURLWithPath: text.wrappedValue)
                    if panel.runModal() == .OK, let url = panel.url {
                        text.wrappedValue = url.path
                    }
                }
            }
        }
    }
}
