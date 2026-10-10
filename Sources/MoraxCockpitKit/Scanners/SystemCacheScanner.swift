import Foundation

public struct SystemCacheScanner: Sendable {
    private let trashService = TrashService.shared
    
    public init() {}
    
    public func scan(
        customCachesDirectory: URL? = nil,
        customLogsDirectory: URL? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let cachesDir = customCachesDirectory ?? home.appendingPathComponent("Library/Caches")
        let logsDir = customLogsDirectory ?? home.appendingPathComponent("Library/Logs")
        
        // 1. Scan QuickLook and Media thumbnail caches
        progressHandler?("Scanning QuickLook thumbnail caches...")
        // CloudKit is deliberately not part of this list: it holds the queue of
        // record changes that have not reached the server yet, so it is reported
        // separately as destructive rather than as a thumbnail cache.
        let qlTargets = [
            cachesDir.appendingPathComponent("com.apple.QuickLook.thumbnailcache"),
            cachesDir.appendingPathComponent("com.apple.mediaanalysisd")
        ]
        for url in qlTargets {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = trashService.calculateSize(url: url)
            guard size > 0 else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            items.append(FileItem(
                url: url,
                name: url.lastPathComponent,
                sizeBytes: size,
                modifiedDate: modDate,
                category: .systemQuickLook,
                riskTier: .safe,
                riskReason: "QuickLook thumbnail cache — regenerated on file preview.",
                isRecent: isRecent,
                isSelected: false,
                details: "QuickLook and media thumbnail generation cache"
            ))
        }

        let cloudKitDir = cachesDir.appendingPathComponent("CloudKit")
        if fileManager.fileExists(atPath: cloudKitDir.path) {
            let size = trashService.calculateSize(url: cloudKitDir)
            if size > 0 {
                let modDate = (try? cloudKitDir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                items.append(FileItem(
                    url: cloudKitDir,
                    name: cloudKitDir.lastPathComponent,
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .systemPendingSync,
                    riskTier: .destructive,
                    riskReason: "CloudKit operation queue — pending record changes that have not synced yet are lost with it.",
                    isRecent: modDate > cutoffDate,
                    isSelected: false,
                    details: "CloudKit local record cache and pending operation queue"
                ))
            }
        }
        
        // 2. Scan User Application Caches in ~/Library/Caches (excluding already scanned creative/browser domains)
        progressHandler?("Scanning user application caches...")
        let knownControlledNames: Set<String> = Set(AppCacheScanner.ownedCacheDirectoryNames).union([
            "com.adobe.Photoshop", "Adobe/CCX Welcome/photoshop", "Adobe/Lightroom", "com.adobe.LightroomClassicCC7",
            "com.adobe.lightroomCC", "Adobe Camera Raw 2", "Adobe Camera Raw BigTableGroupCache",
            "com.captureone.", "Capture One", "RollbarCrash/Capture One",
            "com.apple.Safari", "com.apple.Safari.SearchHelper", "com.apple.SafariTechnologyPreview",
            "com.apple.WebKit.Networking", "com.apple.WebKit.WebContent",
            "Google/Chrome", "company.thebrowser.Browser", "BraveSoftware/Brave-Browser",
            "Firefox", "org.mozilla.firefox", "Microsoft Edge", "com.microsoft.edgemac",
            "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "Chromium",
            "com.apple.QuickLook.thumbnailcache", "com.apple.mediaanalysisd", "CloudKit"
        ])
        
        if let cacheContents = try? fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let candidateFolders = cacheContents.filter { folder in
                let name = folder.lastPathComponent
                return !knownControlledNames.contains(name) && !knownControlledNames.contains(where: { name.hasPrefix($0) })
            }
            
            // A cache directory is only tiered `.safe` when it is on the proven list.
            // Everything else in ~/Library/Caches is an unknown: several applications
            // keep offline media, local indexes or licence state there.
            let provenSafeCachePrefixes: [String] = [
                "com.apple.QuickLook", "com.apple.mediaanalysisd", "com.apple.iconservices",
                "com.apple.helpd", "com.apple.nsurlsessiond", "com.apple.appstore",
                "Homebrew", "go-build", "typescript", "electron", "node-gyp",
                "com.apple.dt.Xcode", "SwiftPM", "org.swift.swiftpm"
            ]

            let userCacheItems: [FileItem] = await withTaskGroup(of: FileItem?.self) { group in
                for folder in candidateFolders {
                    group.addTask {
                        let name = folder.lastPathComponent
                        let size = TrashService.shared.calculateSize(url: folder)
                        guard size > 10 * 1024 * 1024 else { return nil } // Only report caches > 10MB to avoid clutter
                        let modDate = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                        let isRecent = modDate > cutoffDate
                        let isProvenSafe = provenSafeCachePrefixes.contains { name.hasPrefix($0) }
                        
                        return FileItem(
                            url: folder,
                            name: name,
                            sizeBytes: size,
                            modifiedDate: modDate,
                            category: .systemUserCaches,
                            riskTier: isProvenSafe ? .safe : .rebuildCost,
                            riskReason: isProvenSafe
                                ? "macOS user app cache — regenerated by applications as needed."
                                : "Unrecognised application cache — some applications keep offline data here, so it is not assumed to regenerate.",
                            isRecent: isRecent,
                            isSelected: false,
                            details: "User application runtime cache: \(name)"
                        )
                    }
                }
                
                var results: [FileItem] = []
                for await item in group {
                    if let item {
                        results.append(item)
                    }
                }
                return results
            }
            items.append(contentsOf: userCacheItems.sorted { $0.name < $1.name })
        }
        
        // 3. Scan User Diagnostic & Crash Logs in ~/Library/Logs
        progressHandler?("Scanning diagnostic and crash logs...")
        if let logContents = try? fileManager.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for logURL in logContents {
                let size = trashService.calculateSize(url: logURL)
                guard size > 0 else { continue }
                let modDate = (try? logURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                items.append(FileItem(
                    url: logURL,
                    name: logURL.lastPathComponent,
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .systemLogs,
                    riskTier: isRecent ? .rebuildCost : .safe,
                    riskReason: isRecent
                        ? "Log written within the last 7 days — an application may still be appending to it."
                        : "Stale system or application diagnostic log.",
                    isRecent: isRecent,
                    isSelected: false,
                    details: isRecent ? "Recent diagnostic/crash log" : "Stale diagnostic log file/folder"
                ))
            }
        }
        
        return items
    }
}
