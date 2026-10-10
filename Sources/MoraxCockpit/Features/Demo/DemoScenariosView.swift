import SwiftUI
import MoraxCockpitKit

public struct DemoScenariosView: View {
    let scenarios: [DemoScenario]
    let onNavigateToPageName: (String) -> Void
    
    @State private var selectedScenarioId: String
    
    public init(scenarios: [DemoScenario], onNavigateToPageName: @escaping (String) -> Void) {
        self.scenarios = scenarios
        self.onNavigateToPageName = onNavigateToPageName
        _selectedScenarioId = State(initialValue: scenarios.first?.id ?? "")
    }
    
    private var activeScenario: DemoScenario? {
        scenarios.first { $0.id == selectedScenarioId } ?? scenarios.first
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Scenario Selector Tabs
            scenarioSelectorBar
            
            Divider().overlay(MoraxTheme.border)
            
            // Scenario Content
            if let scenario = activeScenario {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header Card
                        scenarioHeroCard(scenario: scenario)
                        
                        // Step-by-Step Interactive Progression
                        stepsFlowCard(scenario: scenario)
                        
                        // Outcome & Gains Card
                        outcomeCard(outcome: scenario.outcome)
                    }
                    .padding(24)
                }
            }
        }
        .background(CleanMyMacBackground())
    }
    
    // MARK: - Scenario Selector Bar
    private var scenarioSelectorBar: some View {
        HStack(spacing: 10) {
            ForEach(scenarios) { sc in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedScenarioId = sc.id
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: sc.iconName)
                            .font(.system(size: 13, weight: selectedScenarioId == sc.id ? .bold : .medium))
                        
                        Text(sc.title)
                            .font(.system(size: 13, weight: selectedScenarioId == sc.id ? .semibold : .regular))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedScenarioId == sc.id ? MoraxTheme.infoBlue : MoraxTheme.surfaceSubtle)
                    )
                    .foregroundStyle(selectedScenarioId == sc.id ? Color.white : MoraxTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Scenario Hero Card
    private func scenarioHeroCard(scenario: DemoScenario) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(scenario.tag)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: scenario.accentColorHex).opacity(0.18))
                    .foregroundStyle(Color(hex: scenario.accentColorHex))
                    .clipShape(.rect(cornerRadius: 4))
                
                Text(scenario.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
            }
            
            Text(scenario.narrative)
                .font(.body)
                .foregroundStyle(MoraxTheme.textSecondary)
        }
        .padding(20)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Steps Flow Card
    private func stepsFlowCard(scenario: DemoScenario) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Déroulé Pas à Pas dans Morax Garage")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            VStack(spacing: 12) {
                ForEach(scenario.steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        // Step number badge
                        ZStack {
                            Circle()
                                .fill(MoraxTheme.infoBlue)
                                .frame(width: 28, height: 28)
                            
                            Text("\(step.stepNumber)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(step.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(MoraxTheme.textPrimary)
                                
                                Spacer()
                                
                                Button(action: {
                                    onNavigateToPageName(step.pageTarget)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: step.iconName)
                                        Text("Aller à \(step.pageTarget)")
                                        Image(systemName: "arrow.right")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            
                            Text(step.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                    }
                    .padding(14)
                    .background(MoraxTheme.surfaceSubtle)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        .padding(20)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Outcome Card
    private func outcomeCard(outcome: DemoScenarioOutcome) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(MoraxTheme.successGreen)
                Text("Bilan & Résultats Obtenus")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.fill.badge.checkmark")
                            .foregroundStyle(MoraxTheme.successGreen)
                        Text("Stockage Récupéré")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                    Text(outcome.storageReclaimed)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(MoraxTheme.infoBlue)
                        Text("Gain de Performance")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                    Text(outcome.performanceGain)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(MoraxTheme.warningAmber)
                        Text("Garantie Sécurité")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MoraxTheme.textMuted)
                    }
                    Text(outcome.safetyAssurance)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(20)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
}
