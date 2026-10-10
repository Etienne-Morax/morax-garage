import SwiftUI
import MoraxCockpitKit

public struct DemoSafetyView: View {
    let principles: [DemoSafetyPrinciple]
    
    public init(principles: [DemoSafetyPrinciple]) {
        self.principles = principles
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                headerBanner
                
                // Principles List
                VStack(spacing: 16) {
                    ForEach(principles) { principle in
                        principleCard(principle: principle)
                    }
                }
            }
            .padding(24)
        }
        .background(CleanMyMacBackground())
    }
    
    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(MoraxTheme.oxbloodRed)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Les 3 Règles d'Or de Sécurité Non-Négociables")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Text("Conçu dès le premier jour pour garantir l'intégrité de vos fichiers et de votre système sans aucun compromis.")
                    .font(.subheadline)
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Principle Card
    private func principleCard(principle: DemoSafetyPrinciple) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MoraxTheme.oxbloodRed.opacity(0.15))
                        .frame(width: 38, height: 38)
                    
                    Text("RÈGLE #\(principle.ruleNumber)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(MoraxTheme.oxbloodRed)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(principle.title)
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text(principle.shortSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
            }
            
            Text(principle.deepExplanation)
                .font(.body)
                .foregroundStyle(MoraxTheme.textPrimary)
            
            Divider().overlay(MoraxTheme.border)
            
            // Side-by-side comparison
            HStack(alignment: .top, spacing: 14) {
                // Forbidden Practices Column
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                        Text("Pratiques Strictement Proscrites")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MoraxTheme.oxbloodRed)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(principle.forbiddenPractices, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(MoraxTheme.oxbloodRed)
                                Text(item)
                                    .font(.system(size: 11))
                                    .foregroundStyle(MoraxTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.oxbloodRed.opacity(0.06))
                .clipShape(.rect(cornerRadius: 8))
                
                // Morax Approach Column
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(MoraxTheme.successGreen)
                        Text("L'Approche Morax Garage")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MoraxTheme.successGreen)
                    }
                    
                    Text(principle.moraxStrictPractice)
                        .font(.system(size: 11))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text(principle.technicalJustification)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MoraxTheme.textMuted)
                        .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.successGreen.opacity(0.08))
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
