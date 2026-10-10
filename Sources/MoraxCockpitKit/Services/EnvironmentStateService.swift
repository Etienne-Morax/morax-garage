import Foundation
import Observation

@Observable
@MainActor
public final class EnvironmentStateService {
    public static let shared = EnvironmentStateService()

    public private(set) var tools: [ToolInfo] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isScanning: Bool = false
    public private(set) var lastScanDate: Date? = nil

    private let toolRegistry = ToolRegistry.shared
    private let cache: CachedScanStore<ToolInfo>
    private var scanTask: Task<Void, Never>? = nil

    public init(customCacheDirectory: URL? = nil) {
        self.cache = CachedScanStore(
            fileName: "environment_tools_cache.plist",
            directory: customCacheDirectory
        )

        // A stale tool list is still worth showing while a rescan runs.
        if let snapshot = cache.load() {
            self.tools = snapshot.items
            self.lastScanDate = snapshot.scanDate
        }
    }

    public var hasLoadedOnce: Bool {
        lastScanDate != nil || !tools.isEmpty
    }

    /// `true` while the persisted tool list is recent enough to be reused as-is.
    public var hasFreshCache: Bool {
        cache.isFresh(lastScanDate)
    }

    public func loadTools(force: Bool = false) async {
        if !force && hasFreshCache {
            return
        }

        if tools.isEmpty {
            isLoading = true
        }
        isScanning = true

        scanTask?.cancel()
        scanTask = Task.detached(priority: .userInitiated) { [toolRegistry, cache] in
            let discovered = await toolRegistry.discoverAll()
            let scanDate = Date()
            cache.save(items: discovered, scanDate: scanDate)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.tools = discovered
                self.lastScanDate = scanDate
                self.isLoading = false
                self.isScanning = false
            }
        }

        await scanTask?.value
    }
}
