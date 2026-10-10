import Foundation

public enum AIModelProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case ollama
    case huggingFace
    case lmStudio
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .huggingFace: return "Hugging Face"
        case .lmStudio: return "LM Studio"
        }
    }
    
    public var iconName: String {
        switch self {
        case .ollama: return "cube.transparent"
        case .huggingFace: return "brain.head.profile"
        case .lmStudio: return "square.stack.3d.up"
        }
    }
    
    /// How a model of this provider is removed.
    public var removalDescription: String {
        switch self {
        case .ollama:
            return "Retiré via « ollama rm », qui supprime le manifeste et les blobs qu'aucun autre modèle n'utilise. Sans la commande, les fichiers partent à la corbeille."
        case .huggingFace:
            return "Le dossier du dépôt part à la corbeille et sera re-téléchargé à la prochaine utilisation."
        case .lmStudio:
            return "Le dossier du modèle part à la corbeille et devra être re-téléchargé dans LM Studio."
        }
    }
}

public struct AIModelItem: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let provider: AIModelProvider
    /// What the provider calls the model: `gemma4:12b`, `Qwen/Qwen3-TTS-12Hz-1.7B-Base`.
    public let name: String
    /// Files and directories that removing this model would delete.
    public let paths: [URL]
    /// Every byte the model references, shared layers included.
    public let totalSizeBytes: Int64
    /// Bytes that removing this model actually frees: layers no other model references.
    public let reclaimableBytes: Int64
    public let modifiedDate: Date
    public let details: String
    
    public init(
        provider: AIModelProvider,
        name: String,
        paths: [URL],
        totalSizeBytes: Int64,
        reclaimableBytes: Int64,
        modifiedDate: Date,
        details: String = ""
    ) {
        self.id = "\(provider.rawValue):\(name)"
        self.provider = provider
        self.name = name
        self.paths = paths
        self.totalSizeBytes = totalSizeBytes
        self.reclaimableBytes = reclaimableBytes
        self.modifiedDate = modifiedDate
        self.details = details
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
    
    public var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: reclaimableBytes, countStyle: .file)
    }
    
    /// True when part of this model's bytes are layers shared with another model, so
    /// removing it frees less than its displayed size.
    public var sharesLayers: Bool {
        reclaimableBytes < totalSizeBytes
    }
}
