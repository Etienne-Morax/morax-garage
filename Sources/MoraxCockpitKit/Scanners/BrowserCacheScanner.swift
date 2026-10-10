import Foundation

public struct BrowserCacheScanner: Sendable {
    private let trashService = TrashService.shared
    private let runningChecker: any RunningAppChecking

    public init(runningChecker: any RunningAppChecking = DefaultRunningAppChecker()) {
        self.runningChecker = runningChecker
    }

    /// Bundle identifiers and display names used to detect a running browser.
    private static let browserIdentity: [CleanupCategory: (ids: [String], names: [String], label: String)] = [
        .browserSafariCache: (["com.apple.safari"], ["safari"], "Safari"),
        .browserChromeCache: (["com.google.chrome"], ["google chrome"], "Google Chrome"),
        .browserArcCache: (["company.thebrowser"], ["arc"], "Arc"),
        .browserBraveCache: (["com.brave.browser"], ["brave"], "Brave"),
        .browserFirefoxCache: (["org.mozilla.firefox"], ["firefox"], "Firefox"),
        .browserEdgeCache: (["com.microsoft.edgemac"], ["microsoft edge"], "Microsoft Edge"),
        .browserOtherCache: (["com.operasoftware", "com.vivaldi", "com.kagi", "org.chromium"], ["opera", "vivaldi", "orion", "chromium"], "This browser")
    ]

    /// Tier and reason for a browser cache, downgraded to blocked while the browser runs.
    ///
    /// Deleting a cache under an open browser can corrupt the profile it belongs to,
    /// and the space is reclaimed just as well one quit later.
    private func tier(for category: CleanupCategory, defaultReason: String) -> (RiskTier, String) {
        guard let identity = Self.browserIdentity[category] else { return (.safe, defaultReason) }
        if runningChecker.isRunning(bundleIdentifiers: identity.ids, names: identity.names) {
            return (.blocked, "\(identity.label) is running — quit it before clearing this cache.")
        }
        return (.safe, defaultReason)
    }
    
    public func scan(
        customCachesDirectory: URL? = nil,
        customAppSupportDirectory: URL? = nil,
        customContainersDirectory: URL? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let cachesDir = customCachesDirectory ?? home.appendingPathComponent("Library/Caches")
        let appSupportDir = customAppSupportDirectory ?? home.appendingPathComponent("Library/Application Support")
        let containersDir = customContainersDirectory ?? home.appendingPathComponent("Library/Containers")
        
        // 1. Safari
        progressHandler?("Scanning Safari browser caches...")
        let safariItems = scanSafariCaches(
            cachesDir: cachesDir,
            containersDir: containersDir,
            cutoffDate: sevenDaysAgo
        )
        items.append(contentsOf: safariItems)
        
        // 2. Google Chrome
        progressHandler?("Scanning Google Chrome caches...")
        let chromeItems = scanChromiumFamily(
            name: "Google Chrome",
            cacheRelativePaths: ["Google/Chrome"],
            appSupportRelativePaths: ["Google/Chrome/Default/Cache", "Google/Chrome/Default/Code Cache", "Google/Chrome/Default/GPUCache"],
            category: .browserChromeCache,
            cachesDir: cachesDir,
            appSupportDir: appSupportDir,
            cutoffDate: sevenDaysAgo
        )
        items.append(contentsOf: chromeItems)
        
        // 3. Arc Browser
        progressHandler?("Scanning Arc Browser caches...")
        let arcItems = scanChromiumFamily(
            name: "Arc Browser",
            cacheRelativePaths: ["company.thebrowser.Browser"],
            appSupportRelativePaths: ["Arc/User Data/Default/Cache", "Arc/User Data/Default/Code Cache", "Arc/User Data/Default/GPUCache"],
            category: .browserArcCache,
            cachesDir: cachesDir,
            appSupportDir: appSupportDir,
            cutoffDate: sevenDaysAgo
        )
        items.append(contentsOf: arcItems)
        
        // 4. Brave Browser
        progressHandler?("Scanning Brave Browser caches...")
        let braveItems = scanChromiumFamily(
            name: "Brave Browser",
            cacheRelativePaths: ["BraveSoftware/Brave-Browser"],
            appSupportRelativePaths: ["BraveSoftware/Brave-Browser/Default/Cache", "BraveSoftware/Brave-Browser/Default/Code Cache", "BraveSoftware/Brave-Browser/Default/GPUCache"],
            category: .browserBraveCache,
            cachesDir: cachesDir,
            appSupportDir: appSupportDir,
            cutoffDate: sevenDaysAgo
        )
        items.append(contentsOf: braveItems)
        
        // 5. Mozilla Firefox
        progressHandler?("Scanning Mozilla Firefox caches...")
        let firefoxItems = scanFirefox(
            cachesDir: cachesDir,
            cutoffDate: sevenDaysAgo
        )
        items.append(contentsOf: firefoxItems)
        
        // 6. Microsoft Edge
        progressHandler?("Scanning Microsoft Edge caches...")
        let edgeItems = scanChromiumFamily(
            name: "Microsoft Edge",
            cacheRelativePaths: ["Microsoft Edge", "com.microsoft.edgemac"],
            appSupportRelativePaths: ["Microsoft Edge/Default/Cache", "Microsoft Edge/Default/Code Cache", "Microsoft Edge/Default/GPUCache"],
            category: .browserEdgeCache,
            cachesDir: cachesDir,
            appSupportDir: appSupportDir,
            cutoffDate: sevenDaysAgo
        )
        items.append(contentsOf: edgeItems)
        
        // 7. Other Browsers (Opera, Vivaldi, Orion)
        progressHandler?("Scanning other web browser caches...")
        let otherItems = scanOtherBrowsers(cachesDir: cachesDir, cutoffDate: sevenDaysAgo)
        items.append(contentsOf: otherItems)
        
        return items
    }
    
    // MARK: - Safari Scanning
    private func scanSafariCaches(
        cachesDir: URL,
        containersDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let candidates: [(URL, String)] = [
            (cachesDir.appendingPathComponent("com.apple.Safari"), "Safari Application Cache"),
            (cachesDir.appendingPathComponent("com.apple.Safari.SearchHelper"), "Safari Search Helper Cache"),
            (cachesDir.appendingPathComponent("com.apple.SafariTechnologyPreview"), "Safari Technology Preview Cache"),
            (cachesDir.appendingPathComponent("com.apple.WebKit.Networking"), "WebKit Network Cache"),
            (cachesDir.appendingPathComponent("com.apple.WebKit.WebContent"), "WebKit Content Cache"),
            (containersDir.appendingPathComponent("com.apple.Safari/Data/Library/Caches"), "Safari Container Cache")
        ]
        
        let safariTier = tier(for: .browserSafariCache, defaultReason: "Regenerated automatically by Safari.")

        for (url, label) in candidates {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = trashService.calculateSize(url: url)
            guard size > 0 else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            results.append(FileItem(
                url: url,
                name: label,
                sizeBytes: size,
                modifiedDate: modDate,
                category: .browserSafariCache,
                riskTier: safariTier.0,
                riskReason: safariTier.1,
                isRecent: isRecent,
                isSelected: false,
                details: "Regenerable web cache for \(label)"
            ))
        }
        
        return results
    }
    
    // MARK: - Chromium Family Scanning (Chrome, Arc, Brave, Edge)
    private func scanChromiumFamily(
        name: String,
        cacheRelativePaths: [String],
        appSupportRelativePaths: [String],
        category: CleanupCategory,
        cachesDir: URL,
        appSupportDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let tierAndReason = tier(for: category, defaultReason: "Regenerated automatically by \(name).")

        for rel in cacheRelativePaths {
            let url = cachesDir.appendingPathComponent(rel)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = trashService.calculateSize(url: url)
            guard size > 0 else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            results.append(FileItem(
                url: url,
                name: "\(name) Cache (\(url.lastPathComponent))",
                sizeBytes: size,
                modifiedDate: modDate,
                category: category,
                riskTier: tierAndReason.0,
                riskReason: tierAndReason.1,
                isRecent: isRecent,
                isSelected: false,
                details: "Browser network and page cache for \(name)"
            ))
        }
        
        for rel in appSupportRelativePaths {
            let url = appSupportDir.appendingPathComponent(rel)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = trashService.calculateSize(url: url)
            guard size > 0 else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            results.append(FileItem(
                url: url,
                name: "\(name)/\(url.lastPathComponent)",
                sizeBytes: size,
                modifiedDate: modDate,
                category: category,
                riskTier: tierAndReason.0,
                riskReason: tierAndReason.1,
                isRecent: isRecent,
                isSelected: false,
                details: "\(name) \(url.lastPathComponent) store"
            ))
        }
        
        return results
    }
    
    // MARK: - Firefox Scanning
    private func scanFirefox(
        cachesDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let targets = [
            cachesDir.appendingPathComponent("Firefox"),
            cachesDir.appendingPathComponent("org.mozilla.firefox"),
            cachesDir.appendingPathComponent("Mozilla/updates")
        ]
        
        let tierAndReason = tier(for: .browserFirefoxCache, defaultReason: "Regenerated automatically by Firefox.")

        for url in targets {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = trashService.calculateSize(url: url)
            guard size > 0 else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            results.append(FileItem(
                url: url,
                name: "Firefox Cache (\(url.lastPathComponent))",
                sizeBytes: size,
                modifiedDate: modDate,
                category: .browserFirefoxCache,
                riskTier: tierAndReason.0,
                riskReason: tierAndReason.1,
                isRecent: isRecent,
                isSelected: false,
                details: "Mozilla Firefox browser runtime and media cache"
            ))
        }
        
        return results
    }
    
    // MARK: - Other Browsers
    private func scanOtherBrowsers(
        cachesDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let candidates: [(String, String)] = [
            ("com.operasoftware.Opera", "Opera"),
            ("com.vivaldi.Vivaldi", "Vivaldi"),
            ("com.kagi.kagimacOS", "Orion"),
            ("Chromium", "Chromium")
        ]
        
        for (rel, browserName) in candidates {
            let tierAndReason = runningChecker.isRunning(bundleIdentifiers: [rel.lowercased()], names: [browserName.lowercased()])
                ? (RiskTier.blocked, "\(browserName) is running — quit it before clearing this cache.")
                : (RiskTier.safe, "Regenerated automatically by \(browserName).")
            let url = cachesDir.appendingPathComponent(rel)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = trashService.calculateSize(url: url)
            guard size > 0 else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            results.append(FileItem(
                url: url,
                name: "\(browserName) Cache",
                sizeBytes: size,
                modifiedDate: modDate,
                category: .browserOtherCache,
                riskTier: tierAndReason.0,
                riskReason: tierAndReason.1,
                isRecent: isRecent,
                isSelected: false,
                details: "Browser cache for \(browserName)"
            ))
        }
        
        return results
    }
}
