import SwiftUI
import MoraxCockpitKit

public enum DemoTabSection: String, CaseIterable, Identifiable {
    case pageGuides = "Guide des Pages"
    case scenarios = "Scénarios Pratiques"
    case safety = "Règles de Sécurité"
    case faq = "FAQ & Astuces"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .pageGuides: return "book.pages"
        case .scenarios: return "play.laptopcomputer"
        case .safety: return "lock.shield"
        case .faq: return "questionmark.circle"
        }
    }
}

public struct DemoHubView: View {
    let onNavigateToPage: (GarageNavigationItem) -> Void
    
    @State private var activeSection: DemoTabSection = .pageGuides
    @State private var selectedPageId: String = "dashboard"
    private let demoService = DemoGuideService.shared
    
    public init(onNavigateToPage: @escaping (GarageNavigationItem) -> Void) {
        self.onNavigateToPage = onNavigateToPage
    }
    
    private var activePageGuide: DemoPageGuide? {
        demoService.pageGuides.first { $0.id == selectedPageId } ?? demoService.pageGuides.first
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Section Switcher
            topHeaderBar
            
            Divider().overlay(MoraxTheme.border)
            
            // Section Content Switcher
            Group {
                switch activeSection {
                case .pageGuides:
                    pageGuidesSplitLayout
                case .scenarios:
                    DemoScenariosView(
                        scenarios: demoService.scenarios,
                        onNavigateToPageName: { name in
                            if let item = GarageNavigationItem.allCases.first(where: { $0.rawValue == name }) {
                                onNavigateToPage(item)
                            }
                        }
                    )
                case .safety:
                    DemoSafetyView(principles: demoService.safetyPrinciples)
                case .faq:
                    DemoFAQView(
                        items: demoService.faqItems,
                        onNavigateToPageName: { name in
                            if let item = GarageNavigationItem.allCases.first(where: { $0.rawValue == name }) {
                                onNavigateToPage(item)
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CleanMyMacBackground())
    }
    
    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MoraxTheme.infoBlue)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("MODE DÉMO & GUIDE INTERACTIF")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        Text("OFFICIEL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(MoraxTheme.infoBlue.opacity(0.18))
                            .foregroundStyle(MoraxTheme.infoBlue)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    
                    Text("Explications complètes de chaque page, chaque bouton, chaque possibilité et cas d'usage réels")
                        .font(.system(size: 11))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
            }
            
            Spacer()
            
            // Section Switcher
            HStack(spacing: 6) {
                ForEach(DemoTabSection.allCases) { section in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeSection = section
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: section.iconName)
                                .font(.system(size: 12, weight: activeSection == section ? .bold : .medium))
                            Text(section.rawValue)
                                .font(.system(size: 12, weight: activeSection == section ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(activeSection == section ? MoraxTheme.infoBlue : MoraxTheme.surfaceSubtle)
                        )
                        .foregroundStyle(activeSection == section ? Color.white : MoraxTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Page Guides Split Layout
    private var pageGuidesSplitLayout: some View {
        HSplitView {
            // Left List: 9 Pages Selector
            VStack(spacing: 0) {
                HStack {
                    Text("LES 9 PAGES DU COCKPIT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textSecondary)
                    Spacer()
                    Text("9 modules")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MoraxTheme.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(demoService.pageGuides) { guide in
                            pageSelectorRow(guide: guide)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
            .background(MoraxTheme.sidebarBackground)
            
            // Right Area: Active Page Detail
            if let guide = activePageGuide {
                DemoPageDetailView(
                    guide: guide,
                    onNavigateToPage: onNavigateToPage
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 40))
                        .foregroundStyle(MoraxTheme.textMuted)
                    Text("Sélectionnez une page pour voir ses détails")
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Page Selector Row
    private func pageSelectorRow(guide: DemoPageGuide) -> some View {
        let isSelected = selectedPageId == guide.id
        
        return Button(action: {
            selectedPageId = guide.id
        }) {
            HStack(spacing: 10) {
                Image(systemName: guide.iconName)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.white : MoraxTheme.infoBlue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(guide.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.white : MoraxTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text(guide.pageRawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                Text(guide.badgeText)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.white.opacity(0.25) : MoraxTheme.infoBlue.opacity(0.15))
                    .foregroundStyle(isSelected ? Color.white : MoraxTheme.infoBlue)
                    .clipShape(.rect(cornerRadius: 3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? MoraxTheme.infoBlue : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
