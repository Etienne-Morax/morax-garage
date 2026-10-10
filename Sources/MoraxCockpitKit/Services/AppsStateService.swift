import Foundation
import Observation

@Observable
@MainActor
public final class AppsStateService {
    public static let shared = AppsStateService()

    public private(set) var apps: [AppInventoryItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isScanning: Bool = false
    public private(set) var lastScanDate: Date? = nil
    public var searchQuery: String = ""

    private let appsService = AppsService.shared
    private let cache: CachedScanStore<AppInventoryItem>
    private var scanTask: Task<Void, Never>? = nil

    public init(customCacheDirectory: URL? = nil) {
        self.cache = CachedScanStore(
            fileName: "apps_inventory_cache.plist",
            directory: customCacheDirectory
        )

        // A stale inventory is still worth showing while a rescan runs.
        if let snapshot = cache.load() {
            self.apps = snapshot.items
            self.lastScanDate = snapshot.scanDate
        }
    }

    public var hasLoadedOnce: Bool {
        lastScanDate != nil || !apps.isEmpty
    }

    /// `true` while the persisted inventory is recent enough to be reused as-is.
    public var hasFreshCache: Bool {
        cache.isFresh(lastScanDate)
    }

    public func loadApps(force: Bool = false) async {
        if !force && hasFreshCache {
            return
        }

        if apps.isEmpty {
            isLoading = true
        }
        isScanning = true

        scanTask?.cancel()
        scanTask = Task.detached(priority: .userInitiated) { [appsService, cache] in
            let scanned = await appsService.scanApplications()
            let scanDate = Date()
            cache.save(items: scanned, scanDate: scanDate)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.apps = scanned
                self.lastScanDate = scanDate
                self.isLoading = false
                self.isScanning = false
            }
        }

        await scanTask?.value
    }
}
