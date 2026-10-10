import Foundation

public struct InstallerScanner: Sendable {
    private let trashService = TrashService.shared
    public static let minArchiveSizeBytes: Int64 = 50 * 1024 * 1024 // 50 MB
    
    public init() {}
    
    public func scan(
        customSearchDirectories: [URL]? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        var targetDirs: [URL] = customSearchDirectories ?? [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop")
        ]
        
        let brewCache = home.appendingPathComponent("Library/Caches/Homebrew/downloads")
        let brewCacheAlt = home.appendingPathComponent("Library/Caches/Homebrew")
        if fileManager.fileExists(atPath: brewCache.path) {
            targetDirs.append(brewCache)
        } else if fileManager.fileExists(atPath: brewCacheAlt.path) {
            targetDirs.append(brewCacheAlt)
        }
        
        for dir in targetDirs {
            if Task.isCancelled { break }
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            
            progressHandler?("Scanning \(dir.lastPathComponent) for installer packages...")
            let scanned = scanDirectory(dir: dir).map(Self.escalatingCloudSyncedItem)
            items.append(contentsOf: scanned)
        }
        
        return items
    }
    
    /// Raises an item to `.destructive` when it lives in iCloud Drive.
    ///
    /// `~/Desktop` and `~/Documents` are firmlinked into the iCloud container when
    /// Desktop & Documents syncing is on, so trashing what looks like a local
    /// installer removes it from every device on the account.
    private static func escalatingCloudSyncedItem(_ item: FileItem) -> FileItem {
        guard SafetyGate.isCloudSynced(url: item.url) else { return item }
        return FileItem(
            id: item.id,
            url: item.url,
            name: item.name,
            sizeBytes: item.sizeBytes,
            modifiedDate: item.modifiedDate,
            category: item.category,
            riskTier: .destructive,
            riskReason: "iCloud Drive item — trashing it removes the file from every device signed into this account.",
            isRecent: item.isRecent,
            isSelected: false,
            details: item.details
        )
    }

    /// `true` when the file carries a quarantine flag, meaning macOS recorded it as
    /// arriving from a browser or a messaging client.
    ///
    /// An archive without that flag was produced on this Mac — an export, a backup, a
    /// deliverable — and telling the user it "can be re-downloaded" would be wrong.
    private func wasDownloaded(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey])
        return values?.quarantineProperties != nil
    }

    private func scanDirectory(dir: URL) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        let isBrewCache = dir.path.contains("Library/Caches/Homebrew")
        
        for file in files {
            if Task.isCancelled { break }
            
            let ext = file.pathExtension.lowercased()
            let size = trashService.calculateSize(url: file)
            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let dirName = dir.lastPathComponent
            
            if isBrewCache {
                if size > 0 {
                    results.append(FileItem(
                        url: file,
                        name: file.lastPathComponent,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .brewCache,
                        riskTier: .safe,
                        riskReason: "Homebrew bottle/source download cache.",
                        isSelected: false,
                        details: "Homebrew cache (\(dirName))"
                    ))
                }
            } else if ext == "dmg" {
                if size > 0 {
                    results.append(FileItem(
                        url: file,
                        name: file.lastPathComponent,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .installerDMG,
                        riskTier: .rebuildCost,
                        riskReason: "Downloaded disk image — will need to be re-downloaded if installer is needed again.",
                        isSelected: false,
                        details: "Disk Image in \(dirName)"
                    ))
                }
            } else if ext == "pkg" {
                if size > 0 {
                    results.append(FileItem(
                        url: file,
                        name: file.lastPathComponent,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .installerPKG,
                        riskTier: .rebuildCost,
                        riskReason: "Downloaded installer package — will need to be re-downloaded if needed again.",
                        isSelected: false,
                        details: "Installer Package in \(dirName)"
                    ))
                }
            } else if ext == "zip" || ext == "tar" || ext == "gz" || ext == "xz" {
                if size >= Self.minArchiveSizeBytes {
                    let downloaded = wasDownloaded(file)
                    results.append(FileItem(
                        url: file,
                        name: file.lastPathComponent,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .installerArchive,
                        riskTier: downloaded ? .rebuildCost : .destructive,
                        riskReason: downloaded
                            ? "Downloaded archive — will need to be re-downloaded if needed again."
                            : "Archive created on this Mac — there is no download to fall back on.",
                        isSelected: false,
                        details: "Large Archive (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) in \(dirName)"
                    ))
                }
            }
        }
        
        return results
    }
}
