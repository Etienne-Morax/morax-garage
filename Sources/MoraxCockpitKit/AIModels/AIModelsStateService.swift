import Foundation
import Observation

@Observable
@MainActor
public final class AIModelsStateService {
    public static let shared = AIModelsStateService()
    
    public private(set) var models: [AIModelItem] = []
    public private(set) var isScanning: Bool = false
    public private(set) var lastScanDate: Date? = nil
    public private(set) var isRemoving: Bool = false
    public private(set) var lastRemovalResults: [AIModelRemovalResult] = []
    public var selectedModelIDs: Set<String> = []
    /// Removal is destructive, so the sheet asks before anything is touched.
    public var isConfirmingRemoval: Bool = false
    
    private let scanner: AIModelScanner
    private let uninstaller: AIModelUninstaller
    private let cache: CachedScanStore<AIModelItem>
    private var scanTask: Task<Void, Never>? = nil
    
    public init(
        scanner: AIModelScanner = AIModelScanner(),
        uninstaller: AIModelUninstaller = AIModelUninstaller(),
        customCacheDirectory: URL? = nil
    ) {
        self.scanner = scanner
        self.uninstaller = uninstaller
        self.cache = CachedScanStore(
            fileName: "ai_models_cache.plist",
            directory: customCacheDirectory
        )
        
        // A stale inventory is still worth showing while a rescan runs.
        if let snapshot = cache.load() {
            self.models = snapshot.items
            self.lastScanDate = snapshot.scanDate
        }
    }
    
    public var hasLoadedOnce: Bool {
        lastScanDate != nil || !models.isEmpty
    }
    
    public var totalBytes: Int64 {
        models.reduce(0) { $0 + $1.totalSizeBytes }
    }
    
    public var selectedModels: [AIModelItem] {
        models.filter { selectedModelIDs.contains($0.id) }
    }
    
    /// What removing the current selection would actually free, shared layers excluded.
    public var selectedReclaimableBytes: Int64 {
        selectedModels.reduce(0) { $0 + $1.reclaimableBytes }
    }
    
    public func models(for provider: AIModelProvider) -> [AIModelItem] {
        models.filter { $0.provider == provider }
    }
    
    public func toggleSelection(_ model: AIModelItem) {
        if selectedModelIDs.contains(model.id) {
            selectedModelIDs.remove(model.id)
        } else {
            selectedModelIDs.insert(model.id)
        }
    }
    
    public func clearSelection() {
        selectedModelIDs.removeAll()
    }
    
    public func scan(force: Bool = false) async {
        if !force && cache.isFresh(lastScanDate) { return }
        
        isScanning = true
        scanTask?.cancel()
        scanTask = Task.detached(priority: .userInitiated) { [scanner, cache] in
            let scanned = await scanner.scan()
            let scanDate = Date()
            cache.save(items: scanned, scanDate: scanDate)
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.models = scanned
                self.lastScanDate = scanDate
                self.isScanning = false
                // A model that no longer exists must not stay selected.
                let knownIDs = Set(scanned.map(\.id))
                self.selectedModelIDs.formIntersection(knownIDs)
            }
        }
        await scanTask?.value
    }
    
    public func removeSelectedModels() async {
        let targets = selectedModels
        guard !targets.isEmpty else { return }
        
        isRemoving = true
        isConfirmingRemoval = false
        let results = await uninstaller.remove(targets)
        lastRemovalResults = results
        
        let removedIDs = Set(results.filter(\.isSuccess).map(\.modelID))
        models.removeAll { removedIDs.contains($0.id) }
        selectedModelIDs.subtract(removedIDs)
        isRemoving = false
        
        cache.save(items: models, scanDate: lastScanDate ?? Date())
        
        // Sizes shift once shared layers lose a reference, so the inventory is rebuilt.
        if !removedIDs.isEmpty {
            await scan(force: true)
        }
    }
}
