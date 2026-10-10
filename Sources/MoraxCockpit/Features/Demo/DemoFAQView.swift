import SwiftUI
import MoraxCockpitKit

public struct DemoFAQView: View {
    let items: [DemoFAQItem]
    let onNavigateToPageName: (String) -> Void
    
    @State private var searchQuery: String = ""
    @State private var selectedCategory: String = "Tous"
    
    public init(items: [DemoFAQItem], onNavigateToPageName: @escaping (String) -> Void) {
        self.items = items
        self.onNavigateToPageName = onNavigateToPageName
    }
    
    private var categories: [String] {
        var set = Set<String>()
        set.insert("Tous")
        for item in items {
            set.insert(item.category)
        }
        return ["Tous"] + Array(set.filter { $0 != "Tous" }).sorted()
    }
    
    private var filteredItems: [DemoFAQItem] {
        items.filter { item in
            let matchesCategory = (selectedCategory == "Tous") || (item.category == selectedCategory)
            let matchesSearch = searchQuery.isEmpty ||
                item.question.localizedCaseInsensitiveContains(searchQuery) ||
                item.answer.localizedCaseInsensitiveContains(searchQuery)
            return matchesCategory && matchesSearch
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header & Search
                headerAndSearchBar
                
                // Categories Bar
                categoriesBar
                
                // FAQ Accordions
                VStack(spacing: 12) {
                    if filteredItems.isEmpty {
                        emptySearchView
                    } else {
                        ForEach(filteredItems) { item in
                            faqCard(item: item)
                        }
                    }
                }
                
                // Maintenance Routine Cheat Sheet
                routineCheatSheet
            }
            .padding(24)
        }
        .background(CleanMyMacBackground())
    }
    
    // MARK: - Header & Search
    private var headerAndSearchBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foire Aux Questions & Guide de Maintenance")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text("Tout ce qu'il faut savoir pour utiliser sereinement Morax Garage au quotidien.")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MoraxTheme.textMuted)
                    TextField("Rechercher dans la FAQ...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: 240)
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
    
    // MARK: - Categories Bar
    private var categoriesBar: some View {
        HStack(spacing: 8) {
            ForEach(categories, id: \.self) { cat in
                Button(action: {
                    selectedCategory = cat
                }) {
                    Text(cat)
                        .font(.system(size: 12, weight: selectedCategory == cat ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategory == cat ? MoraxTheme.infoBlue : MoraxTheme.surfaceSubtle)
                        .foregroundStyle(selectedCategory == cat ? Color.white : MoraxTheme.textPrimary)
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
    
    // MARK: - FAQ Card
    private func faqCard(item: DemoFAQItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(item.category.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(MoraxTheme.infoBlue.opacity(0.18))
                    .foregroundStyle(MoraxTheme.infoBlue)
                    .clipShape(.rect(cornerRadius: 4))
                
                Text(item.question)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
                
                if let page = item.pageLink {
                    Button(action: {
                        onNavigateToPageName(page)
                    }) {
                        HStack(spacing: 4) {
                            Text(page)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            
            Text(item.answer)
                .font(.system(size: 13))
                .foregroundStyle(MoraxTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Routine Cheat Sheet
    private var routineCheatSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Routine de Maintenance Recommandée")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🗓️ Hebdomadaire (30 secondes)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text("• Jeter un œil aux 5 cadrans du Dashboard (Swap & Disque)\n• Vérifier les mises à jour Homebrew\n• Scannez vos dossiers de projets actifs")
                        .font(.system(size: 12))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("📦 Fin de Projet / Mensuel (2 minutes)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text("• Purger les répertoires CacheClip DaVinci Resolve\n• Nettoyer les node_modules / target des vieux repos\n• Faire un Persistence Audit des LaunchAgents")
                        .font(.system(size: 12))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                .padding(14)
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
    
    // MARK: - Empty Search View
    private var emptySearchView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(MoraxTheme.textMuted)
            Text("Aucune question trouvée pour '\(searchQuery)'")
                .font(.headline)
                .foregroundStyle(MoraxTheme.textPrimary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}
