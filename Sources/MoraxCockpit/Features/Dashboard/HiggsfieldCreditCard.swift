import SwiftUI
import AppKit
import MoraxCockpitKit

/// Carte CleanMyMac / Liquid Glass affichant la jauge et les crédits du compte Higgsfield.ai,
/// avec connexion en 1-clic et configuration directe du numéro / ID de workspace.
public struct HiggsfieldCreditCard: View {
    @State private var service = HiggsfieldCreditService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var workspaceInput: String = ""
    @State private var isApplyingWorkspace = false
    @State private var showWorkspaceInput = false
    @State private var actionFeedbackMessage: String? = nil
    @State private var availableWorkspaces: [String] = []
    @State private var isLoadingWorkspaces = false
    
    public init() {}
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    public var body: some View {
        let state = service.state
        let snapshot = service.cachedSnapshot
        
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDarkMode
                                ? [Color(hex: "#8B5CF6").opacity(0.25), Color(hex: "#EC4899").opacity(0.20)]
                                : [MoraxTheme.cleanPurple.opacity(0.18), MoraxTheme.hotPink.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MoraxTheme.cleanPurple)
                }
                
                HStack(spacing: 6) {
                    Text("HIGGSFIELD AI")
                        .font(.system(size: 12.5, weight: .black, design: .rounded))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("CRÉDITS")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            isDarkMode
                            ? Color(hex: "#A855F7").opacity(0.18)
                            : MoraxTheme.cleanPurple.opacity(0.14)
                        )
                        .foregroundStyle(MoraxTheme.cleanPurple)
                        .clipShape(.rect(cornerRadius: 3.5))
                }
                
                Spacer()
                
                // Status Badge / Connection Button
                if case .unauthenticated = state {
                    Button(action: {
                        launchOneClickLogin()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 8.5))
                            Text("Connexion")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(Color.white)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help("Lancer la connexion OAuth dans le navigateur via le CLI")
                } else {
                    statusBadge(for: state)
                }
                
                // Manual Refresh Button
                Button(action: {
                    Task {
                        await service.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(MoraxTheme.textSecondary)
                        .rotationEffect(.degrees(service.isRefreshing ? 360 : 0))
                        .animation(service.isRefreshing ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default, value: service.isRefreshing)
                        .padding(5)
                        .background(MoraxTheme.surfaceSubtle)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(MoraxTheme.border.opacity(0.8), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .disabled(service.isRefreshing)
                .help("Actualiser le solde Higgsfield")
            }
            
            // Content Body
            HStack(alignment: .center, spacing: 10) {
                // Left: Credit Visual Dial Pod
                creditDialPod(snapshot: snapshot, state: state)
                    .frame(width: 112)
                
                // Right: Solde restant
                VStack(alignment: .leading, spacing: 6) {
                    if let credits = snapshot?.formattedCredits {
                        metadataRow(
                            icon: "creditcard",
                            label: "Solde restant",
                            value: "\(credits) crédits",
                            accent: snapshot?.isStale == true ? MoraxTheme.warningAmber : MoraxTheme.textPrimary
                        )
                    } else {
                        metadataRow(
                            icon: "creditcard",
                            label: "Solde restant",
                            value: "—",
                            accent: MoraxTheme.textMuted
                        )
                    }
                    
                    // Temporary Action Feedback (e.g. "Connexion lancée !")
                    if let feedback = actionFeedbackMessage {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(MoraxTheme.successGreen)
                            Text(feedback)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(MoraxTheme.successGreen)
                        }
                        .padding(.vertical, 1)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Contextual workspace configuration when required
            if case .workspaceRequired = state {
                workspaceControlSection(for: state)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: state, snapshot: snapshot))
    }
    
    // MARK: - Credit Dial Pod
    @ViewBuilder
    private func creditDialPod(snapshot: HiggsfieldCreditSnapshot?, state: HiggsfieldCreditState) -> some View {
        let hasValue = snapshot?.credits != nil
        let creditsString = snapshot?.formattedCredits ?? "—"
        let isStale = snapshot?.isStale ?? false
        
        VStack(spacing: 4) {
            ZStack {
                // Background Track Arc
                CleanArcRingShape(startAngle: 140, sweepAngle: 260)
                    .stroke(
                        isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.10),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                
                // Active Glowing Arc if data is live/stale
                if hasValue {
                    CleanArcRingShape(startAngle: 140, sweepAngle: 260 * 0.75)
                        .stroke(
                            LinearGradient(
                                colors: isStale
                                    ? (isDarkMode ? [MoraxTheme.warningAmber, Color(hex: "#FB923C")] : [Color(hex: "#B45309"), Color(hex: "#EA580C")])
                                    : (isDarkMode ? [Color(hex: "#A855F7"), Color(hex: "#EC4899")] : [Color(hex: "#7E22CE"), Color(hex: "#BE185D")]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                }
                
                // Central Digital Readout
                VStack(spacing: 1) {
                    Text(creditsString)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(hasValue ? MoraxTheme.textPrimary : MoraxTheme.textMuted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: 60)
                    
                    Text("CRÉDITS")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(hasValue ? (isStale ? MoraxTheme.warningAmber : (isDarkMode ? Color(hex: "#C084FC") : Color(hex: "#7E22CE"))) : MoraxTheme.textMuted)
                }
            }
            .frame(width: 80, height: 70)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(MoraxTheme.surfaceSubtle.opacity(0.5))
        .clipShape(.rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(MoraxTheme.border.opacity(0.7), lineWidth: 0.75)
        )
    }
    
    // MARK: - Metadata Row Component
    private func metadataRow(icon: String, label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
                .foregroundStyle(MoraxTheme.textMuted)
                .frame(width: 14)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MoraxTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
    }
    
    // MARK: - Workspace Control & Input Section
    @ViewBuilder
    private func workspaceControlSection(for state: HiggsfieldCreditState) -> some View {
        let isWorkspaceNeeded: Bool = {
            if case .workspaceRequired = state { return true }
            return false
        }()
        
        VStack(alignment: .leading, spacing: 6) {
            // Workspace Header / Toggle
            HStack(spacing: 5) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(hex: "#A855F7"))
                
                Text("WORKSPACE / NUMÉRO DE COMPTE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                Spacer()
                
                if !isWorkspaceNeeded {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showWorkspaceInput.toggle()
                        }
                    }) {
                        Text(showWorkspaceInput ? "Masquer" : "Changer")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color(hex: "#C084FC"))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Input Bar (always visible if workspaceRequired, or toggleable)
            if isWorkspaceNeeded || showWorkspaceInput {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        TextField("Numéro ou ID (ex: 12345)", text: $workspaceInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(MoraxTheme.surfaceSubtle)
                            .clipShape(.rect(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(MoraxTheme.border, lineWidth: 0.75)
                            )
                            .onSubmit {
                                applyWorkspaceID()
                            }
                        
                        // Apply Button
                        Button(action: {
                            applyWorkspaceID()
                        }) {
                            if isApplyingWorkspace {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 48, height: 20)
                            } else {
                                Text("Valider")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4.5)
                                    .background(Color(hex: "#A855F7"))
                                    .foregroundStyle(Color.white)
                                    .clipShape(.rect(cornerRadius: 5))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(workspaceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isApplyingWorkspace)
                        
                        // Reset / Unset Workspace Button
                        Button(action: {
                            unsetWorkspaceID()
                        }) {
                            Text("Par défaut")
                                .font(.system(size: 8.5, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4.5)
                                .background(MoraxTheme.surfaceSubtle)
                                .foregroundStyle(MoraxTheme.textSecondary)
                                .clipShape(.rect(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(MoraxTheme.border.opacity(0.8), lineWidth: 0.75)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Réinitialiser le workspace vers le compte personnel par défaut")
                    }
                    
                    // Helper List of Workspaces (if available)
                    if !availableWorkspaces.isEmpty {
                        HStack(spacing: 4) {
                            Text("Disponibles :")
                                .font(.system(size: 8.5))
                                .foregroundStyle(MoraxTheme.textMuted)
                            ForEach(availableWorkspaces.prefix(3), id: \.self) { ws in
                                Button(action: {
                                    workspaceInput = ws
                                    applyWorkspaceID()
                                }) {
                                    Text(ws)
                                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(Color(hex: "#A855F7").opacity(0.15))
                                        .foregroundStyle(Color(hex: "#C084FC"))
                                        .clipShape(.rect(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 1)
                    }
                }
                .padding(6)
                .background(Color(hex: "#A855F7").opacity(0.06))
                .clipShape(.rect(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(hex: "#A855F7").opacity(0.2), lineWidth: 0.75)
                )
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: - Status Badge
    private func statusBadge(for state: HiggsfieldCreditState) -> some View {
        let (label, color): (String, Color) = {
            switch state {
            case .live:
                return ("Live", MoraxTheme.successGreen)
            case .stale:
                return ("Périmé", MoraxTheme.warningAmber)
            case .loading:
                return ("Chargement", MoraxTheme.infoBlue)
            case .unauthenticated:
                return ("Non connecté", MoraxTheme.warningAmber)
            case .workspaceRequired:
                return ("Workspace Requis", MoraxTheme.warningAmber)
            case .cliUnavailable:
                return ("CLI Indisponible", MoraxTheme.textMuted)
            case .timeout:
                return ("Timeout", MoraxTheme.warningAmber)
            case .malformedResponse:
                return ("Réponse invalide", MoraxTheme.neonRose)
            case .disabled:
                return ("Désactivé", MoraxTheme.textMuted)
            case .error:
                return ("Erreur", MoraxTheme.neonRose)
            }
        }()
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
            
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(.capsule)
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 0.75)
        )
    }
    
    // MARK: - Actions
    
    /// Lance la connexion OAuth 1-clic dans le navigateur via le Terminal
    private func launchOneClickLogin() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("higgsfield auth login", forType: .string)
        
        let appleScript = """
        tell application "Terminal"
            activate
            do script "higgsfield auth login"
        end tell
        """
        
        if let scriptObject = NSAppleScript(source: appleScript) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
        } else {
            if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        
        showFeedback("Connexion lancée dans le navigateur !")
        
        // Auto refresh in background after 4s and 10s to capture successful login
        Task {
            try? await Task.sleep(for: .seconds(4))
            await service.refresh()
            try? await Task.sleep(for: .seconds(6))
            await service.refresh()
        }
    }
    
    private func applyWorkspaceID() {
        let trimmed = workspaceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isApplyingWorkspace = true
        Task {
            let success = await service.setWorkspace(id: trimmed)
            isApplyingWorkspace = false
            if success {
                showFeedback("Workspace \(trimmed) appliqué !")
                showWorkspaceInput = false
            } else {
                showFeedback("Erreur lors de la configuration du workspace")
            }
        }
    }
    
    private func unsetWorkspaceID() {
        isApplyingWorkspace = true
        Task {
            let success = await service.unsetWorkspace()
            isApplyingWorkspace = false
            workspaceInput = ""
            if success {
                showFeedback("Workspace réinitialisé !")
            }
        }
    }
    
    private func showFeedback(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            actionFeedbackMessage = text
        }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeInOut(duration: 0.2)) {
                if actionFeedbackMessage == text {
                    actionFeedbackMessage = nil
                }
            }
        }
    }
    
    // MARK: - Accessibility
    private func accessibilityLabel(for state: HiggsfieldCreditState, snapshot: HiggsfieldCreditSnapshot?) -> String {
        if let snapshot = snapshot, snapshot.credits != nil {
            return "Higgsfield AI : \(snapshot.formattedCredits) crédits restants\(snapshot.plan.map { ", Plan \($0)" } ?? "")\(snapshot.isStale ? ", relevé périmé" : "")"
        }
        switch state {
        case .unauthenticated:
            return "Higgsfield AI : non authentifié, bouton Me connecter au compte disponible"
        case .workspaceRequired:
            return "Higgsfield AI : numéro ou identifiant de workspace requis, champ de saisie disponible"
        case .cliUnavailable:
            return "Higgsfield AI : CLI non détecté"
        case .loading:
            return "Higgsfield AI : chargement du solde de crédits"
        case .timeout:
            return "Higgsfield AI : délai de connexion dépassé"
        default:
            return "Higgsfield AI : solde de crédits indisponible"
        }
    }
}

// MARK: - CleanArcRingShape
struct CleanArcRingShape: Shape {
    let startAngle: Double
    let sweepAngle: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(2, min(rect.width, rect.height) / 2.0 - 4)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweepAngle),
            clockwise: false
        )
        return path
    }
}
