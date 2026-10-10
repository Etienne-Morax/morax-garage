import Foundation
import AppKit

public struct AppInventoryItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let bundleURL: URL
    public let bundleIdentifier: String?
    public let version: String?
    public let sizeBytes: Int64
    public let lastUsedDate: Date?
    
    public init(
        name: String,
        bundleURL: URL,
        bundleIdentifier: String?,
        version: String?,
        sizeBytes: Int64,
        lastUsedDate: Date?
    ) {
        self.id = bundleURL.path
        self.name = name
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.sizeBytes = sizeBytes
        self.lastUsedDate = lastUsedDate
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct AppsService: Sendable {
    public static let shared = AppsService()
    private let trashService = TrashService.shared
    
    public init() {}
    
    /// Builds the application inventory.
    ///
    /// Measuring a bundle means walking every file it contains, so bundles are
    /// measured concurrently: the walk is IO bound and one bundle per core keeps
    /// the wall-clock cost close to that of the largest bundle rather than the sum.
    public func scanApplications() async -> [AppInventoryItem] {
        let appURLs = Self.discoverApplicationBundles()
        let trashService = self.trashService

        let items = await withTaskGroup(of: AppInventoryItem.self) { group in
            for url in appURLs {
                group.addTask {
                    Self.inventoryItem(for: url, trashService: trashService)
                }
            }

            var collected: [AppInventoryItem] = []
            collected.reserveCapacity(appURLs.count)
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func discoverApplicationBundles() -> [URL] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var appURLs: [URL] = []
        for root in roots {
            guard fileManager.fileExists(atPath: root.path),
                  let contents = try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }
            appURLs.append(contentsOf: contents.filter { $0.pathExtension == "app" })
        }
        return appURLs
    }

    private static func inventoryItem(for url: URL, trashService: TrashService) -> AppInventoryItem {
        let bundle = Bundle(url: url)
        let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return AppInventoryItem(
            name: name,
            bundleURL: url,
            bundleIdentifier: bundle?.bundleIdentifier,
            version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
            sizeBytes: trashService.calculateSize(url: url),
            lastUsedDate: modDate
        )
    }

    /// Hands off application uninstallation to Pearcleaner
    @MainActor
    public func handoffToPearcleaner(appURL: URL) {
        // Try Pearcleaner URL scheme or app open
        let pearAppURL = ToolRegistry.shared.resolveAppPath(name: "Pearcleaner")
        
        if let pearAppURL = pearAppURL {
            let pearURL = URL(fileURLWithPath: pearAppURL)
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = [appURL.path]
            
            NSWorkspace.shared.open([appURL], withApplicationAt: pearURL, configuration: config) { app, error in
                if error != nil {
                    // Fallback to reveal in Finder
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                }
            }
        } else {
            // Fallback: Reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }
    }
    
    @MainActor
    public func revealInFinder(appURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}
