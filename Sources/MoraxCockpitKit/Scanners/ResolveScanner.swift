import Foundation

public struct ResolveScanner: Sendable {
    public static let defaultResolveAppSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve")
    
    private let trashService = TrashService.shared
    
    public init() {}
    
    /// Scans DaVinci Resolve render cache, proxies, gallery stills, and logs.
    /// Explicitly excludes project databases, backups, and .drp files.
    public func scan(
        customScratchRoot: URL? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        
        // 1. Scan user scratch directory (or volumes)
        var scratchRoots: [URL] = []
        if let custom = customScratchRoot {
            scratchRoots.append(custom)
        } else {
            // Check default ~/Movies
            let defaultMovies = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
            if fileManager.fileExists(atPath: defaultMovies.path) {
                scratchRoots.append(defaultMovies)
            }
            
            // Check AppSupport Cache
            let appSupportCache = Self.defaultResolveAppSupport.appendingPathComponent("Cache")
            if fileManager.fileExists(atPath: appSupportCache.path) {
                scratchRoots.append(appSupportCache)
            }
            
            // Check mounted external volumes (EXCLUDING the root volume "/" and system mounts)
            let resourceKeys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey]
            if let mounted = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: Array(resourceKeys), options: [.skipHiddenVolumes]) {
                for vol in mounted {
                    let path = vol.path
                    // STRICT GUARD: Never scan root "/" or system volume paths
                    guard path != "/" && !path.hasPrefix("/System") && !path.hasPrefix("/private") else {
                        continue
                    }
                    // Skip read-only volumes (e.g. installer DMGs)
                    if let values = try? vol.resourceValues(forKeys: resourceKeys),
                       let isReadOnly = values.volumeIsReadOnly, isReadOnly {
                        continue
                    }
                    
                    // Inspect known Resolve cache candidate subpaths on the external volume
                    let candidatePaths = [
                        vol.appendingPathComponent("CacheClip"),
                        vol.appendingPathComponent(".gallery"),
                        vol.appendingPathComponent("CaptureLogs"),
                        vol.appendingPathComponent("OptimizedMedia"),
                        vol.appendingPathComponent("ProxyMedia"),
                        vol.appendingPathComponent("DaVinci Resolve/CacheClip"),
                        vol.appendingPathComponent("DaVinci Resolve/.gallery"),
                        vol.appendingPathComponent("Resolve Cache/CacheClip"),
                        vol.appendingPathComponent("Resolve Cache/.gallery"),
                        vol.appendingPathComponent("Movies/CacheClip"),
                        vol.appendingPathComponent("Movies/.gallery")
                    ]
                    for candidate in candidatePaths {
                        if fileManager.fileExists(atPath: candidate.path) {
                            scratchRoots.append(candidate)
                        }
                    }
                }
            }
        }
        
        for root in scratchRoots {
            if Task.isCancelled { break }
            progressHandler?("Scanning for Resolve cache in \(root.lastPathComponent)...")
            
            let cacheItems = scanDirectoryForResolveCaches(at: root)
            items.append(contentsOf: cacheItems)
        }
        
        // 2. Scan Resolve logs in Application Support
        let logsDir = Self.defaultResolveAppSupport.appendingPathComponent("logs")
        if fileManager.fileExists(atPath: logsDir.path) {
            progressHandler?("Scanning Resolve crash logs...")
            let logFiles = scanResolveLogs(at: logsDir)
            items.append(contentsOf: logFiles)
        }
        
        return items
    }
    
    private func scanDirectoryForResolveCaches(at root: URL) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let rootName = root.lastPathComponent
        let rootLower = rootName.lowercased()
        
        // If root itself is already a target Resolve cache directory:
        if rootName == "CacheClip" {
            if let item = processResolveFolder(url: root, category: .resolveRenderCache, namePrefix: "Resolve CacheClip") {
                return [item]
            }
            return []
        } else if rootName == ".gallery" || rootName == "CaptureLogs" {
            if let item = processResolveFolder(url: root, category: .resolveGalleryStills, namePrefix: "Gallery Stills") {
                return [item]
            }
            return []
        } else if rootLower == "optimizedmedia" || rootLower == "optimized media" {
            if let item = processResolveFolder(url: root, category: .resolveOptimizedMedia, namePrefix: "Optimised Media") {
                return [item]
            }
            return []
        } else if rootLower == "proxymedia" || rootLower == "proxy media" {
            if let item = processResolveFolder(url: root, category: .resolveProxies, namePrefix: "Proxy Media") {
                return [item]
            }
            return []
        }
        
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
            let lowerName = name.lowercased()
            
            // Skip common non-media folders to avoid needless crawling
            if name == ".git" || name == ".DS_Store" || name == ".Spotlight-V100" || name == ".Trashes" {
                enumerator.skipDescendants()
                continue
            }
            
            // HARD NEGATIVE CHECK: Skip and prune any project databases or libraries
            if lowerName.contains("resolve project library") ||
               lowerName.contains("project backups") ||
               lowerName.hasSuffix(".drp") ||
               lowerName == "project.db" {
                enumerator.skipDescendants()
                continue
            }
            
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            
            if isDir.boolValue {
                if name == "CacheClip" {
                    if let item = processResolveFolder(url: url, category: .resolveRenderCache, namePrefix: "Resolve CacheClip") {
                        results.append(item)
                    }
                    enumerator.skipDescendants()
                } else if name == ".gallery" || name == "CaptureLogs" {
                    if let item = processResolveFolder(url: url, category: .resolveGalleryStills, namePrefix: "Gallery Stills") {
                        results.append(item)
                    }
                    enumerator.skipDescendants()
                } else if lowerName == "optimizedmedia" || lowerName == "optimized media" {
                    if let item = processResolveFolder(url: url, category: .resolveOptimizedMedia, namePrefix: "Optimised Media") {
                        results.append(item)
                    }
                    enumerator.skipDescendants()
                } else if lowerName == "proxymedia" || lowerName == "proxy media" {
                    if let item = processResolveFolder(url: url, category: .resolveProxies, namePrefix: "Proxy Media") {
                        results.append(item)
                    }
                    enumerator.skipDescendants()
                }
            }
        }
        
        return results
    }
    
    private func processResolveFolder(url: URL, category: CleanupCategory, namePrefix: String) -> FileItem? {
        do {
            try SafetyGate.checkDaVinciResolveSafety(canonicalPath: url.path)
        } catch {
            return nil
        }
        
        let size = trashService.calculateSize(url: url)
        guard size > 0 else { return nil }
        
        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let parentName = url.deletingLastPathComponent().lastPathComponent
        let displayName = parentName.isEmpty ? namePrefix : "\(namePrefix) (\(parentName))"
        
        return FileItem(
            url: url,
            name: displayName,
            sizeBytes: size,
            modifiedDate: modDate,
            category: category,
            riskTier: category.defaultTier,
            riskReason: category.defaultRiskReason,
            isSelected: false,
            details: "Render cache directory: \(url.path)"
        )
    }
    
    private func scanResolveLogs(at logsDir: URL) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for file in files {
            if Task.isCancelled { break }
            let size = trashService.calculateSize(url: file)
            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            
            if size > 0 {
                results.append(FileItem(
                    url: file,
                    name: file.lastPathComponent,
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .resolveLogs,
                    riskTier: .safe,
                    riskReason: "DaVinci Resolve diagnostic and crash log files.",
                    isSelected: false,
                    details: "Log file: \(file.path)"
                ))
            }
        }
        return results
    }
}
