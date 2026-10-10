import Foundation
import Observation

@Observable
@MainActor
public final class AuditStateService {
    public static let shared = AuditStateService()

    public private(set) var items: [PersistenceItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isScanning: Bool = false
    public private(set) var lastScanDate: Date? = nil
    public var selectedLocation: PersistenceLocation? = nil
    public var showOrphansOnly: Bool = false

    private let auditService = AuditService.shared
    private let cache: CachedScanStore<PersistenceItem>
    private var scanTask: Task<Void, Never>? = nil

    public init(customCacheDirectory: URL? = nil) {
        self.cache = CachedScanStore(
            fileName: "persistence_audit_cache.plist",
            directory: customCacheDirectory
        )

        // A stale audit is still worth showing while a rescan runs.
        if let snapshot = cache.load() {
            self.items = snapshot.items
            self.lastScanDate = snapshot.scanDate
        }
    }

    public var hasLoadedOnce: Bool {
        lastScanDate != nil || !items.isEmpty
    }

    /// `true` while the persisted audit is recent enough to be reused as-is.
    public var hasFreshCache: Bool {
        cache.isFresh(lastScanDate)
    }

    public func loadAudit(force: Bool = false) async {
        if !force && hasFreshCache {
            return
        }

        if items.isEmpty {
            isLoading = true
        }
        isScanning = true

        scanTask?.cancel()
        scanTask = Task.detached(priority: .userInitiated) { [auditService, cache] in
            let auditedItems = auditService.auditPersistence()
            let scanDate = Date()
            cache.save(items: auditedItems, scanDate: scanDate)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.items = auditedItems
                self.lastScanDate = scanDate
                self.isLoading = false
                self.isScanning = false
            }
        }

        await scanTask?.value
    }
}
