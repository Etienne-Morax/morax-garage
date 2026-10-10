import Foundation

public struct AIModelRemovalResult: Sendable, Equatable, Identifiable {
    public let modelID: String
    public let modelName: String
    public let isSuccess: Bool
    public let reclaimedBytes: Int64
    public let method: Method
    public let message: String
    
    public var id: String { modelID }
    
    public enum Method: String, Sendable, Equatable {
        /// Removed through the provider's own CLI, which also updates its bookkeeping.
        case providerCommand
        /// Files moved to the Trash, recoverable until the user empties it.
        case trash
        case failed
    }
    
    public init(
        modelID: String,
        modelName: String,
        isSuccess: Bool,
        reclaimedBytes: Int64,
        method: Method,
        message: String
    ) {
        self.modelID = modelID
        self.modelName = modelName
        self.isSuccess = isSuccess
        self.reclaimedBytes = reclaimedBytes
        self.method = method
        self.message = message
    }
}

/// Removes locally installed AI models.
///
/// Ollama is asked to remove its own models rather than having its files deleted: it keeps
/// a manifest tree and a shared blob store, and deleting files underneath it leaves
/// dangling references that make later pulls behave strangely. Everything else is moved to
/// the Trash, so a mistake stays recoverable.
public struct AIModelUninstaller: Sendable {
    private let processRunner: ProcessRunner
    private let trashService: TrashService
    private let operationLog: OperationLog
    
    /// Where Homebrew and the official installer put the CLI. `PATH` is not inherited by a
    /// GUI app, so the binary is looked up by location.
    static let ollamaExecutableCandidates = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/opt/local/bin/ollama"
    ]
    
    public init(
        processRunner: ProcessRunner = .shared,
        trashService: TrashService = .shared,
        operationLog: OperationLog = .shared
    ) {
        self.processRunner = processRunner
        self.trashService = trashService
        self.operationLog = operationLog
    }
    
    /// Ollama reports a stopped daemon on stderr rather than with a distinct exit code.
    static func isServerUnavailable(_ output: String) -> Bool {
        let lowercased = output.lowercased()
        return lowercased.contains("could not connect")
            || lowercased.contains("connection refused")
            || lowercased.contains("ollama serve")
    }
    
    public static func ollamaExecutableURL(fileManager: FileManager = .default) -> URL? {
        ollamaExecutableCandidates
            .first { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
    
    public func remove(_ model: AIModelItem) async -> AIModelRemovalResult {
        switch model.provider {
        case .ollama:
            return await removeOllamaModel(model)
        case .huggingFace, .lmStudio:
            return removeByTrashing(model)
        }
    }
    
    public func remove(_ models: [AIModelItem]) async -> [AIModelRemovalResult] {
        var results: [AIModelRemovalResult] = []
        for model in models {
            results.append(await remove(model))
        }
        return results
    }
    
    // MARK: - Ollama
    
    private func removeOllamaModel(_ model: AIModelItem) async -> AIModelRemovalResult {
        guard let executable = Self.ollamaExecutableURL() else {
            // No CLI: fall back to the Trash, which at least keeps the removal reversible.
            return removeByTrashing(
                model,
                note: "Commande ollama introuvable : les fichiers ont été mis à la corbeille."
            )
        }
        
        do {
            let result = try await processRunner.run(
                executableURL: executable,
                arguments: ["rm", model.name],
                timeout: 60
            )
            
            guard result.isSuccess else {
                let reason = result.standardError.isEmpty ? result.standardOutput : result.standardError
                
                // `ollama rm` talks to a local server that is not always running. Its own
                // on-disk removal is exactly what the fallback does — drop the manifest and
                // the layers no other tag references — so a stopped server is no reason to
                // leave the model in place.
                if Self.isServerUnavailable(reason) {
                    return removeByTrashing(
                        model,
                        note: "Serveur Ollama arrêté : le manifeste et les couches exclusives ont été mis à la corbeille."
                    )
                }
                operationLog.append(entry: OperationLogEntry(
                    absolutePath: model.paths.first?.path ?? model.name,
                    action: "ai-model-remove",
                    outcome: "failed",
                    details: "ollama rm \(model.name): \(reason)",
                    isError: true
                ))
                return AIModelRemovalResult(
                    modelID: model.id,
                    modelName: model.name,
                    isSuccess: false,
                    reclaimedBytes: 0,
                    method: .failed,
                    message: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            
            operationLog.append(entry: OperationLogEntry(
                absolutePath: model.paths.first?.path ?? model.name,
                action: "ai-model-remove",
                outcome: "removed",
                details: "ollama rm \(model.name)",
                isError: false
            ))
            return AIModelRemovalResult(
                modelID: model.id,
                modelName: model.name,
                isSuccess: true,
                reclaimedBytes: model.reclaimableBytes,
                method: .providerCommand,
                message: "Retiré par Ollama."
            )
        } catch {
            return AIModelRemovalResult(
                modelID: model.id,
                modelName: model.name,
                isSuccess: false,
                reclaimedBytes: 0,
                method: .failed,
                message: error.localizedDescription
            )
        }
    }
    
    // MARK: - Trash
    
    private func removeByTrashing(_ model: AIModelItem, note: String? = nil) -> AIModelRemovalResult {
        var reclaimed: Int64 = 0
        var failures: [String] = []
        
        for url in model.paths {
            do {
                let result = try trashService.trashItem(url: url)
                if result.isSuccess {
                    reclaimed += result.sizeBytes
                } else if let error = result.error {
                    failures.append(error)
                }
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        
        guard failures.isEmpty else {
            return AIModelRemovalResult(
                modelID: model.id,
                modelName: model.name,
                isSuccess: false,
                reclaimedBytes: reclaimed,
                method: .failed,
                message: failures.joined(separator: " · ")
            )
        }
        
        return AIModelRemovalResult(
            modelID: model.id,
            modelName: model.name,
            isSuccess: true,
            reclaimedBytes: reclaimed,
            method: .trash,
            message: note ?? "Déplacé vers la corbeille."
        )
    }
}
