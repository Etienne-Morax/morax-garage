import SwiftUI
import AppKit
import MoraxCockpitKit

public struct AIModelsView: View {
    private var stateService = AIModelsStateService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MoraxTheme.border)
            
            if stateService.isScanning && !stateService.hasLoadedOnce {
                loadingState
            } else if stateService.models.isEmpty {
                emptyState
            } else {
                modelList
                Divider().overlay(MoraxTheme.border)
                selectionFooter
            }
        }
        .background(CleanMyMacBackground())
        .task {
            await stateService.scan()
        }
        .sheet(isPresented: Binding(
            get: { stateService.isConfirmingRemoval },
            set: { stateService.isConfirmingRemoval = $0 }
        )) {
            removalConfirmationSheet
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(StorageCategory.aiAndModels.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modèles IA installés")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text("Ollama, Hugging Face et LM Studio — désinstallation modèle par modèle")
                        .font(.caption2)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
            }
            
            Spacer()
            
            if stateService.totalBytes > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(ByteCountFormatter.string(fromByteCount: stateService.totalBytes, countStyle: .file))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    Text("\(stateService.models.count) modèles")
                        .font(.system(size: 10))
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
            }
            
            Button {
                Task { await stateService.scan(force: true) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Actualiser")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(stateService.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - List
    
    private var modelList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(AIModelProvider.allCases) { provider in
                    let models = stateService.models(for: provider)
                    if !models.isEmpty {
                        providerSection(provider: provider, models: models)
                    }
                }
            }
            .padding(16)
        }
    }
    
    private func providerSection(provider: AIModelProvider, models: [AIModelItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StorageCategory.aiAndModels.color)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text("\(models.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(MoraxTheme.surfaceSubtle)
                    .foregroundStyle(MoraxTheme.textSecondary)
                    .clipShape(.capsule)
                
                Spacer()
                
                Text(ByteCountFormatter.string(
                    fromByteCount: models.reduce(0) { $0 + $1.totalSizeBytes },
                    countStyle: .file
                ))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Text(provider.removalDescription)
                .font(.system(size: 10))
                .foregroundStyle(MoraxTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 0) {
                ForEach(models) { model in
                    modelRow(model)
                    if model.id != models.last?.id {
                        Divider().overlay(MoraxTheme.border)
                    }
                }
            }
            .background(MoraxTheme.surface)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(MoraxTheme.border, lineWidth: 1)
            )
        }
    }
    
    private func modelRow(_ model: AIModelItem) -> some View {
        let isSelected = stateService.selectedModelIDs.contains(model.id)
        
        return HStack(spacing: 10) {
            Button {
                stateService.toggleSelection(model)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? MoraxTheme.infoBlue : MoraxTheme.textMuted)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if model.sharesLayers {
                    Text("Couches partagées — \(model.formattedReclaimable) réellement libérés")
                        .font(.system(size: 9.5))
                        .foregroundStyle(MoraxTheme.warningAmber)
                }
            }
            
            Spacer()
            
            Text(model.formattedSize)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(MoraxTheme.textSecondary)
            
            Button {
                revealInFinder(model)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MoraxTheme.textMuted)
            .help("Révéler dans le Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .onTapGesture { stateService.toggleSelection(model) }
    }
    
    // MARK: - Footer
    
    private var selectionFooter: some View {
        HStack(spacing: 12) {
            if stateService.selectedModelIDs.isEmpty {
                Text("Sélectionnez les modèles à désinstaller.")
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            } else {
                Text("\(stateService.selectedModelIDs.count) sélectionnés — \(ByteCountFormatter.string(fromByteCount: stateService.selectedReclaimableBytes, countStyle: .file)) libérés")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Button("Tout désélectionner") {
                    stateService.clearSelection()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
            
            if let lastResult = stateService.lastRemovalResults.last {
                Label(
                    lastResult.isSuccess ? "\(lastResult.modelName) retiré" : "Échec : \(lastResult.message)",
                    systemImage: lastResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(lastResult.isSuccess ? MoraxTheme.successGreen : MoraxTheme.oxbloodRed)
                .lineLimit(1)
            }
            
            Button {
                stateService.isConfirmingRemoval = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Désinstaller")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MoraxTheme.oxbloodRed)
            .controlSize(.small)
            .disabled(stateService.selectedModelIDs.isEmpty || stateService.isRemoving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - Confirmation
    
    private var removalConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(MoraxTheme.warningAmber)
                Text("Désinstaller \(stateService.selectedModels.count) modèle(s) ?")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            Text("Un modèle retiré devra être re-téléchargé pour être réutilisé.")
                .font(.system(size: 11))
                .foregroundStyle(MoraxTheme.textSecondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stateService.selectedModels) { model in
                        HStack(spacing: 6) {
                            Image(systemName: model.provider.iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(MoraxTheme.textMuted)
                            Text(model.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            Spacer()
                            Text(model.formattedReclaimable)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            
            Text("Espace libéré : \(ByteCountFormatter.string(fromByteCount: stateService.selectedReclaimableBytes, countStyle: .file))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MoraxTheme.textPrimary)
            
            HStack {
                Spacer()
                Button("Annuler") {
                    stateService.isConfirmingRemoval = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Désinstaller") {
                    Task { await stateService.removeSelectedModels() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MoraxTheme.oxbloodRed)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .background(MoraxTheme.surface)
    }
    
    // MARK: - States
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Recherche des modèles installés...")
                .font(.system(size: 12))
                .foregroundStyle(MoraxTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 34))
                .foregroundStyle(MoraxTheme.textMuted)
            Text("Aucun modèle IA détecté")
                .font(.headline)
                .foregroundStyle(MoraxTheme.textPrimary)
            Text("Morax Garage cherche dans ~/.ollama, ~/.cache/huggingface et ~/.lmstudio.")
                .font(.system(size: 11))
                .foregroundStyle(MoraxTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func revealInFinder(_ model: AIModelItem) {
        guard let url = model.paths.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
