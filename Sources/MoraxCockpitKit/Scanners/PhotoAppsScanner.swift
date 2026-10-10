import Foundation

public struct PhotoAppsScanner: Sendable {
    private let trashService = TrashService.shared
    
    private let runningChecker: any RunningAppChecking

    public init(runningChecker: any RunningAppChecking = DefaultRunningAppChecker()) {
        self.runningChecker = runningChecker
    }

    /// Creative applications keep working state inside directories that look like
    /// caches. While one of them is open its cache is refused outright: a corrupted
    /// session costs far more than the disk space it frees.
    private func blockedWhileRunning(
        ids: [String],
        names: [String],
        label: String,
        defaultReason: String
    ) -> (RiskTier, String) {
        if runningChecker.isRunning(bundleIdentifiers: ids, names: names) {
            return (.blocked, "\(label) is running — quit it before clearing this cache.")
        }
        return (.safe, defaultReason)
    }
    
    /// Default locations for photo libraries and caches
    public static var defaultPicturesRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pictures = home.appendingPathComponent("Pictures")
        if FileManager.default.fileExists(atPath: pictures.path) {
            return [pictures]
        }
        return []
    }
    
    public func scan(
        picturesRoots: [URL] = defaultPicturesRoots,
        customCachesDirectory: URL? = nil,
        customAppSupportDirectory: URL? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let home = fileManager.homeDirectoryForCurrentUser
        
        let cachesDir = customCachesDirectory ?? home.appendingPathComponent("Library/Caches")
        let appSupportDir = customAppSupportDirectory ?? home.appendingPathComponent("Library/Application Support")
        
        // 1. Scan Lightroom & Capture One in Pictures Directories
        for root in picturesRoots {
            if Task.isCancelled { break }
            guard fileManager.fileExists(atPath: root.path) else { continue }
            
            progressHandler?("Scanning \(root.lastPathComponent) for photo previews & session caches...")
            let picturesItems = scanPicturesRoot(root: root, cutoffDate: sevenDaysAgo, progress: progressHandler)
            items.append(contentsOf: picturesItems)
        }
        
        // 2. Scan Adobe Camera Raw & Photoshop Caches
        if fileManager.fileExists(atPath: cachesDir.path) || fileManager.fileExists(atPath: appSupportDir.path) {
            progressHandler?("Scanning Adobe Camera Raw & Photoshop caches...")
            let adobeItems = scanAdobeCaches(cachesDir: cachesDir, appSupportDir: appSupportDir, cutoffDate: sevenDaysAgo)
            items.append(contentsOf: adobeItems)
        }
        
        // 3. Scan Capture One Application & OpenCL Caches
        if fileManager.fileExists(atPath: cachesDir.path) || fileManager.fileExists(atPath: appSupportDir.path) {
            progressHandler?("Scanning Capture One application & OpenCL kernel caches...")
            let c1AppItems = scanCaptureOneAppCaches(cachesDir: cachesDir, appSupportDir: appSupportDir, cutoffDate: sevenDaysAgo)
            items.append(contentsOf: c1AppItems)
        }
        
        return items
    }
    
    // MARK: - Pictures Directory Scanning (Lightroom Previews & Capture One Sessions)
    
    private func scanPicturesRoot(
        root: URL,
        cutoffDate: Date,
        progress: (@Sendable (String) -> Void)?
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }
        
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let name = url.lastPathComponent
            let lower = name.lowercased()
            
            // Skip .git, system files, and settings
            if name == ".git" || name == ".DS_Store" || name == "Settings" || lower.hasPrefix("settings") {
                enumerator.skipDescendants()
                continue
            }
            
            // 1. Lightroom Previews & Helper Caches (* Previews.lrdata, * Smart Previews.lrdata, * Helper.lrdata)
            if lower.hasSuffix(".lrdata") {
                enumerator.skipDescendants()
                
                let size = trashService.calculateSize(url: url)
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                let isSmart = lower.contains("smart previews")
                let category: CleanupCategory = isSmart ? .lightroomSmartPreviews : .lightroomPreviews
                
                if size > 0 {
                    results.append(FileItem(
                        url: url,
                        name: "Lightroom/\(name)",
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: category,
                        riskTier: .rebuildCost,
                        riskReason: isSmart ? "Lightroom Smart Previews — will need to be regenerated from original RAW files." : "Lightroom catalog previews — will need time to regenerate in Lightroom.",
                        isRecent: isRecent,
                        isSelected: false,
                        details: isRecent ? "Recent Lightroom preview cache (active within 7 days)" : "Regenerable Lightroom catalog preview cache"
                    ))
                }
                continue
            }
            
            // 2. Capture One Catalog Package Cache (*.cocatalog/Cache)
            if lower.hasSuffix(".cocatalog") {
                enumerator.skipDescendants()
                let cacheURL = url.appendingPathComponent("Cache")
                if fileManager.fileExists(atPath: cacheURL.path) {
                    let size = trashService.calculateSize(url: cacheURL)
                    let modDate = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                    let isRecent = modDate > cutoffDate
                    
                    if size > 0 {
                        results.append(FileItem(
                            url: cacheURL,
                            name: "\(name)/Cache",
                            sizeBytes: size,
                            modifiedDate: modDate,
                            category: .captureOneCatalogCache,
                            riskTier: .rebuildCost,
                            riskReason: "Capture One catalog proxies and thumbnails — regenerated on demand in Capture One.",
                            isRecent: isRecent,
                            isSelected: false,
                            details: isRecent ? "Active Capture One catalog preview & proxy cache" : "Regenerable Capture One catalog proxy cache"
                        ))
                    }
                }
                continue
            }
            
            // 3. Capture One Session Cache (CaptureOne/Cache)
            if name == "CaptureOne" {
                enumerator.skipDescendants()
                let cacheURL = url.appendingPathComponent("Cache")
                if fileManager.fileExists(atPath: cacheURL.path) {
                    let size = trashService.calculateSize(url: cacheURL)
                    let modDate = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                    let isRecent = modDate > cutoffDate
                    
                    let sessionDir = url.deletingLastPathComponent()
                    let sessionName = sessionDir.lastPathComponent
                    
                    if size > 0 {
                        results.append(FileItem(
                            url: cacheURL,
                            name: "\(sessionName)/CaptureOne/Cache",
                            sizeBytes: size,
                            modifiedDate: modDate,
                            category: .captureOneSessionCache,
                            riskTier: .rebuildCost,
                            riskReason: "Capture One session proxies and thumbnails — regenerated on demand in Capture One.",
                            isRecent: isRecent,
                            isSelected: false,
                            details: isRecent ? "Recent session proxies (.cop) & thumbnails (.cot)" : "Regenerable session proxies & thumbnails"
                        ))
                    }
                }
                continue
            }
        }
        
        return results
    }
    
    // MARK: - Adobe & Photoshop Caches
    
    private func scanAdobeCaches(
        cachesDir: URL,
        appSupportDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        // 1. Adobe Camera Raw (ACR) Caches
        let acrCacheTargets = [
            cachesDir.appendingPathComponent("Adobe Camera Raw 2"),
            cachesDir.appendingPathComponent("Adobe Camera Raw BigTableGroupCache"),
            appSupportDir.appendingPathComponent("Adobe/CameraRaw/Cache"),
            appSupportDir.appendingPathComponent("Adobe/CameraRaw/GPU")
        ]
        
        let adobeTier = blockedWhileRunning(
            ids: ["com.adobe.photoshop", "com.adobe.lightroom"],
            names: ["photoshop", "lightroom"],
            label: "An Adobe application",
            defaultReason: "Adobe Camera Raw image decode cache."
        )

        for acrURL in acrCacheTargets {
            if fileManager.fileExists(atPath: acrURL.path) {
                let size = trashService.calculateSize(url: acrURL)
                let modDate = (try? acrURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                if size > 0 {
                    results.append(FileItem(
                        url: acrURL,
                        name: "CameraRaw/\(acrURL.lastPathComponent)",
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .photoshopCache,
                        riskTier: adobeTier.0,
                        riskReason: adobeTier.1,
                        isRecent: isRecent,
                        isSelected: false,
                        details: "Adobe Camera Raw image decode cache"
                    ))
                }
            }
        }
        
        // 2. Photoshop & Creative Cloud CEF Caches
        let psCacheTargets = [
            cachesDir.appendingPathComponent("com.adobe.Photoshop"),
            cachesDir.appendingPathComponent("Adobe/CCX Welcome/photoshop"),
            cachesDir.appendingPathComponent("Adobe/Lightroom"),
            cachesDir.appendingPathComponent("com.adobe.LightroomClassicCC7")
        ]
        
        for psURL in psCacheTargets {
            if fileManager.fileExists(atPath: psURL.path) {
                let size = trashService.calculateSize(url: psURL)
                let modDate = (try? psURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                let isLR = psURL.lastPathComponent.lowercased().contains("lightroom")
                let category: CleanupCategory = isLR ? .lightroomAppCache : .photoshopCache
                
                if size > 0 {
                    results.append(FileItem(
                        url: psURL,
                        name: "\(psURL.lastPathComponent)",
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: category,
                        riskTier: adobeTier.0,
                        riskReason: adobeTier.0 == .blocked
                            ? adobeTier.1
                            : "\(isLR ? "Lightroom" : "Photoshop") application runtime cache.",
                        isRecent: isRecent,
                        isSelected: false,
                        details: "\(isLR ? "Lightroom" : "Photoshop") application runtime cache"
                    ))
                }
            }
        }
        
        // 3. Photoshop AutoRecover folders (inspect for stale files older than 7 days)
        let adobeAppSupport = appSupportDir.appendingPathComponent("Adobe")
        if let adobeContents = try? fileManager.contentsOfDirectory(at: adobeAppSupport, includingPropertiesForKeys: nil, options: []) {
            for folder in adobeContents where folder.lastPathComponent.hasPrefix("Adobe Photoshop") {
                let autoRecoverDir = folder.appendingPathComponent("AutoRecover")
                if fileManager.fileExists(atPath: autoRecoverDir.path) {
                    let size = trashService.calculateSize(url: autoRecoverDir)
                    let modDate = newestModificationDate(in: autoRecoverDir) ?? Date()
                    let isRecent = modDate > cutoffDate
                    
                    // AutoRecover is the only copy of unsaved work after a crash. It is
                    // never offered while anything in it is recent, and never as `.safe`.
                    if size > 0 && !isRecent && !runningChecker.isRunning(bundleIdentifiers: ["com.adobe.photoshop"], names: ["photoshop"]) {
                        results.append(FileItem(
                            url: autoRecoverDir,
                            name: "\(folder.lastPathComponent)/AutoRecover",
                            sizeBytes: size,
                            modifiedDate: modDate,
                            category: .photoshopCache,
                            riskTier: .destructive,
                            riskReason: "Photoshop crash-recovery state — this is the only copy of documents that were never saved.",
                            isRecent: false,
                            isSelected: false,
                            details: "Photoshop auto-recovery state, untouched for more than 7 days"
                        ))
                    }
                }
            }
        }
        
        return results
    }
    
    /// Most recent modification timestamp anywhere inside a directory.
    ///
    /// The directory's own timestamp does not move when a file deep inside it is
    /// rewritten, which would make live crash-recovery state look stale.
    private func newestModificationDate(in directory: URL) -> Date? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else { return nil }

        var newest: Date? = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        for case let url as URL in enumerator {
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            if newest == nil || date > newest! { newest = date }
        }
        return newest
    }

    // MARK: - Capture One App & OpenCL Caches
    
    private func scanCaptureOneAppCaches(
        cachesDir: URL,
        appSupportDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let captureOneRuntimeTier = blockedWhileRunning(
            ids: ["com.captureone", "com.phaseone"],
            names: ["capture one"],
            label: "Capture One",
            defaultReason: "Capture One application runtime cache."
        )

        // 1. Capture One Caches in ~/Library/Caches
        if let cacheContents = try? fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil, options: []) {
            for item in cacheContents where item.lastPathComponent.hasPrefix("com.captureone.") || item.lastPathComponent == "Capture One" {
                let size = trashService.calculateSize(url: item)
                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                if size > 0 {
                    results.append(FileItem(
                        url: item,
                        name: item.lastPathComponent,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .captureOneAppCache,
                        riskTier: captureOneRuntimeTier.0,
                        riskReason: captureOneRuntimeTier.1,
                        isRecent: isRecent,
                        isSelected: false,
                        details: "Capture One application runtime cache"
                    ))
                }
            }
        }
        
        // 2. RollbarCrash/Capture One
        let rollbarC1 = cachesDir.appendingPathComponent("RollbarCrash/Capture One")
        if fileManager.fileExists(atPath: rollbarC1.path) {
            let size = trashService.calculateSize(url: rollbarC1)
            let modDate = (try? rollbarC1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            if size > 0 {
                results.append(FileItem(
                    url: rollbarC1,
                    name: "RollbarCrash/Capture One",
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .captureOneAppCache,
                    riskTier: .safe,
                    riskReason: "Capture One crash diagnostics & reports.",
                    isRecent: isRecent,
                    isSelected: false,
                    details: "Capture One crash diagnostics & reports"
                ))
            }
        }
        
        // 3. Capture One ImageCore (OpenCL compiled kernels) & Batch Queue
        let c1AppSupport = appSupportDir.appendingPathComponent("Capture One")
        // "Batch Queue" is deliberately excluded: it holds exports that have been
        // queued but not yet processed, which is pending work rather than a cache.
        let targets = [
            c1AppSupport.appendingPathComponent("ImageCore"),
            c1AppSupport.appendingPathComponent("Logs")
        ]
        let captureOneTier = blockedWhileRunning(
            ids: ["com.captureone", "com.phaseone"],
            names: ["capture one"],
            label: "Capture One",
            defaultReason: "Capture One runtime cache."
        )
        
        for target in targets {
            if fileManager.fileExists(atPath: target.path) {
                let size = trashService.calculateSize(url: target)
                let modDate = (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                if size > 0 {
                    results.append(FileItem(
                        url: target,
                        name: "Capture One/\(target.lastPathComponent)",
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .captureOneAppCache,
                        riskTier: captureOneTier.0,
                        riskReason: captureOneTier.1,
                        isRecent: isRecent,
                        isSelected: false,
                        details: "Capture One \(target.lastPathComponent) cache"
                    ))
                }
            }
        }
        
        return results
    }
}
