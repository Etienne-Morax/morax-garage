import SwiftUI
import MoraxCockpitKit

public enum SettingsSubTab: String, CaseIterable, Identifiable {
    case general = "Général"
    case permissions = "Permissions"
    case terminal = "Mole Terminal"
    case brew = "Homebrew"
    case demo = "Mode Démo & Guide"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .general: return "gearshape.2.fill"
        case .permissions: return "lock.shield.fill"
        case .terminal: return "terminal.fill"
        case .brew: return "mug.fill"
        case .demo: return "sparkles"
        }
    }
    
    public var gradientColors: [Color] {
        switch self {
        case .general:
            return [Color(hex: "#007AFF"), Color(hex: "#5856D6")]
        case .permissions:
            return [Color(hex: "#FF9F0A"), Color(hex: "#FF375F")]
        case .terminal:
            return [Color(hex: "#30D158"), Color(hex: "#107C41")]
        case .brew:
            return [Color(hex: "#FF9500"), Color(hex: "#C67D0A")]
        case .demo:
            return [Color(hex: "#BF5AF2"), Color(hex: "#5E5CE6")]
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .general: return "Apparence & Préférences"
        case .permissions: return "Accès Disque & Sécurité macOS"
        case .terminal: return "Console système interactive"
        case .brew: return "Paquets & Mises à jour"
        case .demo: return "Guide interactif & Scénarios"
        }
    }
}

public struct SettingsView: View {
    @Binding var selectedSubTab: SettingsSubTab
    let onNavigateToMainTab: (GarageNavigationItem) -> Void
    
    @State private var visitedSubTabs: Set<SettingsSubTab>
    
    public init(
        selectedSubTab: Binding<SettingsSubTab>,
        onNavigateToMainTab: @escaping (GarageNavigationItem) -> Void
    ) {
        self._selectedSubTab = selectedSubTab
        self.onNavigateToMainTab = onNavigateToMainTab
        self._visitedSubTabs = State(initialValue: [selectedSubTab.wrappedValue])
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Segmented Selector Bar
            topSettingsNavBar
            
            Divider().overlay(MoraxTheme.border)
            
            // SubTab Content Views with State Preservation
            ZStack {
                ForEach(SettingsSubTab.allCases) { tab in
                    if visitedSubTabs.contains(tab) {
                        subTabView(for: tab)
                            .opacity(selectedSubTab == tab ? 1 : 0)
                            .allowsHitTesting(selectedSubTab == tab)
                            .accessibilityHidden(selectedSubTab != tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CleanMyMacBackground())
        }
        .onChange(of: selectedSubTab) { _, newTab in
            visitedSubTabs.insert(newTab)
        }
    }
    
    // MARK: - Top Settings Navigation Bar
    private var topSettingsNavBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#007AFF"), Color(hex: "#5856D6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: Color(hex: "#007AFF").opacity(0.35), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("RÉGLAGES & OUTILS SYSTÈME")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        Text(selectedSubTab.shortDescription.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MoraxTheme.surfaceSubtle)
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    
                    Text("Configuration du cockpit, autorisations macOS, console terminal, gestion Homebrew et documentation")
                        .font(.system(size: 11))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            
            // SubTabs Buttons Row with CleanMyMac squircle badges
            FullDiskAccessObserver { hasFullDiskAccess, _ in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SettingsSubTab.allCases) { tab in
                            let isSelected = selectedSubTab == tab
                            let isPermCheckNeeded = (tab == .permissions && !hasFullDiskAccess)
                            
                            Button(action: {
                                selectedSubTab = tab
                                visitedSubTabs.insert(tab)
                            }) {
                                HStack(spacing: 8) {
                                    // Mini squircle icon tile
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(
                                                LinearGradient(
                                                    colors: tab.gradientColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 20, height: 20)
                                        
                                        Image(systemName: tab.iconName)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                    
                                    Text(tab.rawValue)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                                        .foregroundStyle(isSelected ? MoraxTheme.textPrimary : MoraxTheme.textSecondary)
                                    
                                    if isPermCheckNeeded {
                                        Text("CHECK")
                                            .font(.system(size: 8, weight: .black))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(MoraxTheme.warningAmber)
                                            .foregroundStyle(Color.black)
                                            .clipShape(.rect(cornerRadius: 3))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(
                                            isSelected
                                            ? MoraxTheme.infoBlue.opacity(0.14)
                                            : MoraxTheme.surfaceSubtle.opacity(0.8)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(
                                            isSelected
                                            ? MoraxTheme.infoBlue.opacity(0.3)
                                            : MoraxTheme.border.opacity(0.7),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(MoraxTheme.surface)
    }

    
    // MARK: - SubTab View Factory
    @ViewBuilder
    private func subTabView(for tab: SettingsSubTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView()
        case .permissions:
            PermissionsView()
        case .terminal:
            TerminalView()
        case .brew:
            BrewView()
        case .demo:
            DemoHubView { targetItem in
                onNavigateToMainTab(targetItem)
            }
        }
    }
}
