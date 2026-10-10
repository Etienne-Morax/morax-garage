import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
public final class CleanupStagingService {
    public static let shared = CleanupStagingService()
    
    public private(set) var stagedItems: [FileItem] = []
    public private(set) var blockedCount: Int = 0
    public private(set) var lastErrorMessage: String? = nil
    
    public init() {}
    
    public var hasStagedItems: Bool {
        !stagedItems.isEmpty
    }
    
    public var totalStagedBytes: Int64 {
        stagedItems.reduce(0) { $0 + $1.sizeBytes }
    }
    
    public var formattedTotalStagedBytes: String {
        ByteCountFormatter.string(fromByteCount: totalStagedBytes, countStyle: .file)
    }
    
    /// Stages a StorageNode for cleanup after validating via SafetyGate
    @discardableResult
    public func stageNode(_ node: StorageNode) -> Result<FileItem, SafetyGateError> {
        // An aggregate node stands for a directory's small entries, not for a file: its
        // URL is the parent folder, so staging it would queue the whole folder.
        guard !node.isAggregate else {
            self.blockedCount += 1
            self.lastErrorMessage = "Cet élément regroupe plusieurs fichiers et ne peut pas être supprimé directement."
            return .failure(SafetyGateError.invalidPath(node.path))
        }

        do {
            try SafetyGate.validateForTrash(url: node.url)
        } catch let err as SafetyGateError {
            self.blockedCount += 1
            self.lastErrorMessage = err.localizedDescription
            return .failure(err)
        } catch {
            let wrapped = SafetyGateError.invalidPath(node.path)
            self.blockedCount += 1
            self.lastErrorMessage = error.localizedDescription
            return .failure(wrapped)
        }
        
        // Map StorageCategory to CleanupCategory.
        //
        // Only a node the storage scanner positively identified as a cache may inherit
        // a cache category. Everything else is arbitrary user data that merely happens
        // to be large, so it is staged as such: mislabelling a Documents folder as a
        // regenerable cache is the one mistake this flow cannot afford.
        let cleanupCategory: CleanupCategory
        switch node.category {
        case .systemAndCache:
            cleanupCategory = .systemUserCaches
        case .devAndBuild, .aiAndModels:
            cleanupCategory = .devBuildArtifacts
        case .installersAndArchives:
            cleanupCategory = .installerArchive
        case .videoAndRender, .photoAndRaw, .applications, .documents, .audio, .cloudNotDownloaded, .other:
            // Cloud placeholders hold no local bytes: staging one frees nothing and would
            // delete the remote file, so it stays plain user data at the strictest tier.
            cleanupCategory = .stagedUserData
        }

        // A staged node is never trusted below the tier of its category, and anything
        // living in iCloud Drive is destructive by definition: the Trash on this Mac
        // removes it from every other device too.
        var tier = max(cleanupCategory.defaultTier, RiskTier.rebuildCost)
        var reason = cleanupCategory.defaultRiskReason
        if SafetyGate.isCloudSynced(url: node.url) {
            tier = .destructive
            reason = "iCloud Drive item — trashing it removes the file from every device signed into this account."
        }

        let fileItem = FileItem(
            id: UUID(),
            url: node.url,
            name: node.name,
            sizeBytes: max(node.allocatedSizeBytes, node.logicalSizeBytes),
            modifiedDate: node.modifiedDate,
            category: cleanupCategory,
            riskTier: tier,
            riskReason: reason,
            isRecent: false,
            isSelected: false, // Never pre-selected: the user confirms each staged item
            details: "Staged from Storage Map (\(node.category.rawValue))"
        )
        
        if !self.stagedItems.contains(where: { $0.url.standardizedFileURL == node.url.standardizedFileURL }) {
            self.stagedItems.append(fileItem)
        }
        
        return .success(fileItem)
    }
    
    /// Removes a staged item by ID
    public func removeItem(id: UUID) {
        self.stagedItems.removeAll(where: { $0.id == id })
    }
    
    /// Removes the staged items whose (standardized) URL is in `urls`, e.g. after they were trashed.
    public func removeItems(urls: Set<URL>) {
        self.stagedItems.removeAll(where: { urls.contains($0.url.standardizedFileURL) })
    }

    /// Clears all staged items
    public func clearAll() {
        self.stagedItems.removeAll()
        self.blockedCount = 0
        self.lastErrorMessage = nil
    }
}
