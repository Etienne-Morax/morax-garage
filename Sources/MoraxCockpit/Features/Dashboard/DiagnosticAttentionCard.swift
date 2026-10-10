import SwiftUI
import MoraxCockpitKit

struct DiagnosticAttentionCard: View {
    @State private var diagnostics = DiagnosticService.shared
    @State private var expandedFindingIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(diagnostics.findings.isEmpty ? "Diagnostic système" : "Points d'attention",
                      systemImage: diagnostics.findings.isEmpty ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(diagnostics.findings.isEmpty ? MoraxTheme.successGreen : MoraxTheme.warningAmber)
                
                Spacer()
                
                if !diagnostics.findings.isEmpty {
                    Button("Tout masquer") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            diagnostics.dismissAllFindings()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MoraxTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MoraxTheme.surfaceSubtle)
                    .clipShape(Capsule())
                    .help("Masquer tous les signaux actuels")
                }
                
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }

            if diagnostics.findings.isEmpty {
                Text(diagnostics.historyAvailable ? "Aucune anomalie détectée : tout fonctionne normalement." : "Observation en cours : données historiques insuffisantes pour établir un diagnostic.")
                    .font(.system(size: 12))
                    .foregroundStyle(MoraxTheme.textSecondary)
            } else {
                ForEach(diagnostics.findings) { finding in
                    findingRow(finding)
                }
            }
        }
        .padding(14)
        .background(MoraxTheme.surfaceSubtle.opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoraxTheme.border.opacity(0.8), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        if diagnostics.findings.isEmpty {
            return diagnostics.historyAvailable ? "OK" : "HISTORIQUE LIMITÉ"
        }
        return String(diagnostics.findings.count) + " SIGNAL" + (diagnostics.findings.count == 1 ? "" : "S")
    }

    private func findingRow(_ finding: DiagnosticFinding) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 9) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedFindingIDs.contains(finding.id) {
                            expandedFindingIDs.remove(finding.id)
                        } else {
                            expandedFindingIDs.insert(finding.id)
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: icon(for: finding.severity))
                            .foregroundStyle(color(for: finding.severity))
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            Text(finding.explanation)
                                .font(.system(size: 11))
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        
                        Spacer()
                        
                        Image(systemName: expandedFindingIDs.contains(finding.id) ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(MoraxTheme.textMuted)
                            .padding(.top, 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Détails : \(finding.title)")

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        diagnostics.dismissFinding(id: finding.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MoraxTheme.textMuted)
                        .padding(5)
                        .background(MoraxTheme.surfaceSubtle.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Masquer ce signal")
                .accessibilityLabel("Masquer \(finding.title)")
            }

            if expandedFindingIDs.contains(finding.id) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preuves observées")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    ForEach(finding.evidence, id: \.self) {
                        Text("• \($0)").font(.caption).foregroundStyle(MoraxTheme.textSecondary)
                    }
                    
                    Text("Recommandation : \(finding.recommendation)")
                        .font(.caption)
                        .foregroundStyle(MoraxTheme.textSecondary)
                    
                    Text("Indice de confiance : \(confidenceText(finding.confidence))")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textMuted)
                    
                    HStack(spacing: 8) {
                        ForEach(finding.actions, id: \.self) { action in
                            Button(actionTitle(action)) {
                                handleAction(action)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(action == .none)
                        }
                        
                        Button("Masquer") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                diagnostics.dismissFinding(id: finding.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 25)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 5)
    }

    private func handleAction(_ action: DiagnosticAction) {
        switch action {
        case .openStorageMap:
            NotificationCenter.default.post(name: .moraxNavigateToTab, object: GarageNavigationItem.storageMap)
        case .reviewApplications:
            NotificationCenter.default.post(name: .moraxNavigateToTab, object: GarageNavigationItem.apps)
        case .inspect, .showDetails, .none:
            break
        }
    }

    private func icon(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    private func color(for severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: MoraxTheme.textSecondary
        case .warning: MoraxTheme.warningAmber
        case .critical: MoraxTheme.neonRose
        }
    }

    private func actionTitle(_ action: DiagnosticAction) -> String {
        switch action {
        case .inspect: "Inspecter"
        case .showDetails: "Détails"
        case .openStorageMap: "Carte de stockage"
        case .reviewApplications: "Voir l'application"
        case .none: "Aucune action"
        }
    }

    private func confidenceText(_ confidence: DiagnosticConfidence) -> String {
        switch confidence {
        case .insufficientData: "Données insuffisantes"
        case .low: "Faible"
        case .medium: "Modéré"
        case .high: "Élevé"
        }
    }
}
