import SwiftUI
import AppKit
import MoraxCockpitKit

struct PhotoSyncProjectRow: View {
    let project: PhotoProjectStatus
    let retentionDays: Int
    let job: PhotoSyncJob?
    let destinations: [PhotoSyncDestination]
    let isSSDOnline: Bool
    let isNASOnline: Bool
    let onSync: (PhotoSyncLeg, String?) -> Void
    let onIgnore: () -> Void

    private var stage: PhotoSyncStage { project.stage(retentionDays: retentionDays) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(stageTint)
                .frame(width: 34, height: 34)
                .background(stageTint.opacity(0.14))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption).tabularFigures()
                    .foregroundStyle(MoraxTheme.textSecondary)
                    .lineLimit(1)
                if let nasPath = project.nasPath {
                    Text(nasLocation(nasPath))
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 180, alignment: .leading)

            Spacer(minLength: 8)

            LegBadge(title: "Mac → SSD", status: project.macToSSD)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(MoraxTheme.textMuted)
            LegBadge(title: "SSD → NAS", status: project.ssdToNAS)

            actionArea
                .frame(width: 170, alignment: .trailing)
        }
        .padding(12)
        .cleanGlassCard(cornerRadius: 12)
        .contextMenu { contextMenuItems }
    }

    // MARK: - Text

    private var detailText: String {
        var parts = [
            ByteCountFormatter.string(fromByteCount: project.referenceBytes, countStyle: .file),
            "\(project.referenceFileCount) fichiers"
        ]
        if let days = project.daysOnSSD() {
            parts.append(stage == .readyToFreeSSD
                ? "SSD depuis \(days) j · libérable"
                : "SSD depuis \(days) j · encore \(max(0, retentionDays - days)) j")
        } else if project.macPath != nil {
            parts.append("sur le Mac uniquement")
        }
        return parts.joined(separator: " · ")
    }

    private func nasLocation(_ path: String) -> String {
        "NAS › " + URL(fileURLWithPath: path).deletingLastPathComponent().pathComponents.suffix(2).joined(separator: " › ")
    }

    private var stageTint: Color {
        switch stage {
        case .needsSSDCopy: return MoraxTheme.warningAmber
        case .needsNASArchive: return MoraxTheme.neonViolet
        case .readyToFreeSSD: return MoraxTheme.electricCyan
        case .retainedOnSSD, .archivedOnly: return MoraxTheme.successGreen
        case .unknown: return MoraxTheme.textMuted
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionArea: some View {
        if let job {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(MoraxTheme.electricCyan)
                Text(job.state == .queued ? "En attente…" : "\(job.transferredFiles)/\(job.expectedFiles) fichiers")
                    .font(.caption2).tabularFigures()
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
        } else if project.macToSSD.needsSync {
            Button("Copier sur SSD", systemImage: "externaldrive.badge.plus") { onSync(.macToSSD, nil) }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.warningAmber)
                .controlSize(.small)
                .disabled(!isSSDOnline)
        } else if project.ssdToNAS.needsSync {
            nasButton
        } else if stage == .readyToFreeSSD, let ssdPath = project.ssdPath {
            Button("Voir sur SSD", systemImage: "folder") { reveal(ssdPath) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Archivé et vérifié sur le NAS : tu peux le supprimer du SSD.")
        }
    }

    @ViewBuilder
    private var nasButton: some View {
        if project.nasPath != nil {
            Button("Compléter NAS", systemImage: "server.rack") { onSync(.ssdToNAS, nil) }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.neonViolet)
                .controlSize(.small)
                .disabled(!isNASOnline)
        } else {
            Menu {
                Section("Ranger dans…") {
                    ForEach(destinations) { category in
                        if category.children.isEmpty {
                            Button(category.name) { onSync(.ssdToNAS, category.path) }
                        } else {
                            Menu(category.name) {
                                Button("\(category.name) (racine)") { onSync(.ssdToNAS, category.path) }
                                Divider()
                                ForEach(category.children) { child in
                                    Button(child.name) { onSync(.ssdToNAS, child.path) }
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Archiver sur NAS", systemImage: "server.rack")
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .fixedSize()
            .disabled(!isNASOnline || destinations.isEmpty)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let macPath = project.macPath {
            Button("Afficher sur le Mac") { reveal(macPath) }
        }
        if let ssdPath = project.ssdPath {
            Button("Afficher sur le SSD") { reveal(ssdPath) }
        }
        if let nasPath = project.nasPath {
            Button("Afficher sur le NAS") { reveal(nasPath) }
        }
        Divider()
        Button("Ignorer ce dossier") { onIgnore() }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

private struct LegBadge: View {
    let title: String
    let status: CopyStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(MoraxTheme.textMuted)
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(width: 118, alignment: .leading)
        .help(helpText)
    }

    private var label: String {
        switch status {
        case .synced: return "À jour"
        case .missing: return "Absent"
        case .incomplete(let files, _): return "\(files) manquant\(files > 1 ? "s" : "")"
        case .volumeOffline: return "Débranché"
        case .noSource: return "—"
        case .unverifiable: return "Illisible"
        }
    }

    private var icon: String {
        switch status {
        case .synced: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .incomplete: return "exclamationmark.triangle.fill"
        case .volumeOffline: return "bolt.horizontal.circle"
        case .noSource: return "minus.circle"
        case .unverifiable: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .synced: return MoraxTheme.successGreen
        case .missing: return MoraxTheme.vividRose
        case .incomplete, .unverifiable: return MoraxTheme.warningAmber
        case .volumeOffline, .noSource: return MoraxTheme.textMuted
        }
    }

    private var helpText: String {
        switch status {
        case .incomplete(let files, let bytes):
            return "\(files) fichier(s) absents ou différents (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
        case .noSource:
            return "Plus de copie source (déjà retiré du Mac)"
        case .unverifiable:
            return "Lecture incomplète (dossier illisible ou disque débranché) : rien n'est garanti, relance Vérifier"
        default:
            return label
        }
    }
}

struct PhotoSyncJobsPanel: View {
    let service: PhotoSyncStateService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Copies")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                Spacer()
                Button("Effacer terminées") { service.clearFinishedJobs() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(service.jobs.allSatisfy(\.isActive))
            }
            ForEach(service.jobs.reversed()) { job in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: job.state))
                        .foregroundStyle(tint(for: job.state))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(job.projectName) — \(job.plan.leg == .macToSSD ? "Mac → SSD" : "SSD → NAS")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        Text(description(for: job))
                            .font(.caption2)
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if job.isActive {
                        Button("Annuler") { service.cancelJob(job) }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .cleanGlassCard(cornerRadius: 12)
    }

    private func description(for job: PhotoSyncJob) -> String {
        switch job.state {
        case .queued: return "En attente"
        case .running: return "\(job.transferredFiles)/\(job.expectedFiles) fichiers copiés"
        case .finished: return "Copié et vérifié fichier par fichier"
        case .failed(let message): return message
        case .cancelled: return "Annulée — relance pour reprendre là où elle s'est arrêtée"
        }
    }

    private func icon(for state: PhotoSyncJob.State) -> String {
        switch state {
        case .queued: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.octagon.fill"
        case .cancelled: return "stop.circle"
        }
    }

    private func tint(for state: PhotoSyncJob.State) -> Color {
        switch state {
        case .queued, .cancelled: return MoraxTheme.textMuted
        case .running: return MoraxTheme.electricCyan
        case .finished: return MoraxTheme.successGreen
        case .failed: return MoraxTheme.vividRose
        }
    }
}
