import SwiftUI
import MoraxCockpitKit

public struct DemoPageDetailView: View {
    let guide: DemoPageGuide
    let onNavigateToPage: (GarageNavigationItem) -> Void
    
    public init(guide: DemoPageGuide, onNavigateToPage: @escaping (GarageNavigationItem) -> Void) {
        self.guide = guide
        self.onNavigateToPage = onNavigateToPage
    }
    
    private var matchingNavigationItem: GarageNavigationItem? {
        GarageNavigationItem.allCases.first { $0.rawValue == guide.pageRawValue }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Hero Header Banner
                heroHeaderBanner
                
                // 2. Purpose & Why it matters
                purposeSection
                
                // 3. Key Features Grid
                featuresSection
                
                // 4. Capabilities & Actions
                capabilitiesSection
                
                // 5. Concrete Real-World Example
                exampleSection
                
                // 6. Safety Guarantee Footer Banner
                safetyGuaranteeBanner
            }
            .padding(24)
        }
        .background(CleanMyMacBackground())
    }
    
    // MARK: - Hero Header Banner
    private var heroHeaderBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(MoraxTheme.infoBlue.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: guide.iconName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(MoraxTheme.infoBlue)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(guide.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text(guide.badgeText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(MoraxTheme.infoBlue.opacity(0.2))
                        .foregroundStyle(MoraxTheme.infoBlue)
                        .clipShape(.rect(cornerRadius: 4))
                }
                
                Text(guide.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
            
            if let targetItem = matchingNavigationItem {
                Button(action: {
                    onNavigateToPage(targetItem)
                }) {
                    HStack(spacing: 6) {
                        Text("Ouvrir la page")
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(MoraxTheme.infoBlue)
            }
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Purpose Section
    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Objectif & Utilité Clé")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(guide.purpose)
                    .font(.body)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(MoraxTheme.warningAmber)
                        .font(.subheadline)
                        .padding(.top, 2)
                    
                    Text(guide.whyItMatters)
                        .font(.callout)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Features Section
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Fonctionnalités Principales")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(guide.features) { feat in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: feat.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MoraxTheme.infoBlue)
                                .frame(width: 20)
                            
                            Text(feat.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                        
                        Text(feat.description)
                            .font(.system(size: 12))
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let tip = feat.tip {
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MoraxTheme.warningAmber)
                                    .padding(.top, 2)
                                
                                Text(tip)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MoraxTheme.warningAmber)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(MoraxTheme.surfaceSubtle)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Capabilities Section
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Possibilités & Actions Disponibles")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            VStack(spacing: 8) {
                ForEach(guide.capabilities) { cap in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(MoraxTheme.infoBlue)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(cap.actionTitle)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(MoraxTheme.textPrimary)
                                
                                Spacer()
                                
                                Text(cap.safetyLevel)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MoraxTheme.successGreen.opacity(0.15))
                                    .foregroundStyle(MoraxTheme.successGreen)
                                    .clipShape(.rect(cornerRadius: 4))
                            }
                            
                            Text("Déclencheur : \(cap.trigger)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MoraxTheme.textMuted)
                            
                            Text(cap.impact)
                                .font(.system(size: 12))
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(MoraxTheme.surfaceSubtle)
                    .clipShape(.rect(cornerRadius: 6))
                }
            }
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Example Section
    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "play.laptopcomputer")
                    .foregroundStyle(MoraxTheme.oxbloodRed)
                Text("Exemple Concret d'Utilisation")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
                
                Text("CAS RÉEL")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MoraxTheme.oxbloodRed.opacity(0.18))
                    .foregroundStyle(MoraxTheme.oxbloodRed)
                    .clipShape(.rect(cornerRadius: 4))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(guide.example.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Text(guide.example.context)
                    .font(.callout)
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                Divider().overlay(MoraxTheme.border)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Déroulé pas à pas :")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    ForEach(guide.example.stepByStep, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(MoraxTheme.successGreen)
                                .padding(.top, 2)
                            
                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(MoraxTheme.textPrimary)
                        }
                    }
                }
                .padding(12)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 8))
                
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .foregroundStyle(MoraxTheme.successGreen)
                    Text("Gain mesurable :")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text(guide.example.metricsGain)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MoraxTheme.successGreen)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Safety Guarantee Banner
    private var safetyGuaranteeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(MoraxTheme.successGreen)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Garantie de Sécurité Morax")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Text(guide.safetyGuarantee)
                    .font(.system(size: 12))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(MoraxTheme.successGreen.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MoraxTheme.successGreen.opacity(0.3), lineWidth: 1)
        )
    }
}
