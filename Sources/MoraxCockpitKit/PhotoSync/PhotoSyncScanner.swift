import Foundation

/// A NAS folder a new project can be archived into.
public struct PhotoSyncDestination: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let children: [PhotoSyncDestination]

    public init(name: String, path: String, children: [PhotoSyncDestination] = []) {
        self.name = name
        self.path = path
        self.children = children
    }
}

/// Read-only discovery and verification of project copies. Never writes to disk.
public struct PhotoSyncScanner: Sendable {
    /// Folder names on the Mac that are working areas rather than client jobs.
    public static let defaultExcludedMacFolders: Set<String> = ["export", "lightroom"]
    /// Top-level NAS folders that never contain client projects.
    public static let excludedNASFolders: Set<String> = ["#recycle", "backup", "download", "restic-morax", "@eadir"]
    /// Photo catalogs and libraries show up as folders but are not projects.
    static let libraryExtensions: Set<String> = [
        "photoslibrary", "lrlibrary", "lrdata", "cocatalog", "cosessiondb", "app", "fcpbundle"
    ]
    /// Metadata files that operating systems scatter around and rsync skips.
    static let ignoredFileNames: Set<String> = ["thumbs.db", "desktop.ini", "icon\r"]
    /// Regenerable preview caches: Capture One rebuilds them, so they are neither
    /// compared nor copied (they churn on every open and would never read as synced).
    public static let regenerableCacheFolders: [(parent: String, name: String)] = [("CaptureOne", "Cache")]
    /// Category / sub-category / project is the deepest layout used on the NAS.
    public static let nasIndexDepth = 3

    public init() {}

    // MARK: - Discovery

    /// Lists the project folders directly inside `root`, keyed by normalized name.
    public func listProjects(in root: URL, excluding excludedKeys: Set<String> = []) -> [String: URL] {
        var projects: [String: URL] = [:]
        for url in subdirectories(of: root) where isProjectFolder(url) {
            let key = PhotoSyncNaming.projectKey(url.lastPathComponent)
            guard !excludedKeys.contains(key) else { continue }
            projects[key] = url
        }
        return projects
    }

    /// Indexes NAS folders down to `nasIndexDepth`, keeping the shallowest match per name
    /// so a project folder wins over an identically named sub-folder inside another project.
    public func indexNAS(root: URL, maxDepth: Int = PhotoSyncScanner.nasIndexDepth) -> [String: URL] {
        var index: [String: URL] = [:]
        var level = subdirectories(of: root).filter { !isExcludedNASFolder($0) }
        var depth = 1
        while !level.isEmpty && depth <= maxDepth {
            var next: [URL] = []
            for url in level {
                let key = PhotoSyncNaming.projectKey(url.lastPathComponent)
                if index[key] == nil {
                    index[key] = url
                }
                if depth < maxDepth {
                    next.append(contentsOf: subdirectories(of: url))
                }
            }
            level = next
            depth += 1
        }
        return index
    }

    /// Category → sub-category tree offered as archive destinations for new projects.
    public func nasDestinations(root: URL) -> [PhotoSyncDestination] {
        subdirectories(of: root)
            .filter { !isExcludedNASFolder($0) }
            .map { category in
                PhotoSyncDestination(
                    name: category.lastPathComponent,
                    path: category.path,
                    children: subdirectories(of: category).map {
                        PhotoSyncDestination(name: $0.lastPathComponent, path: $0.path)
                    }
                )
            }
    }

    public func isVolumeAvailable(_ root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Verification

    /// Relative path → size for every regular file below `folder`, hidden metadata excluded.
    /// The URL enumerator prefetches attributes in bulk, which on the SMB share is two
    /// orders of magnitude faster than the path-based enumerator's per-file `lstat`.
    /// Any read error, or the folder vanishing during the walk, marks the fingerprint
    /// incomplete: a partial listing must never pass for a complete one.
    public func fingerprint(of folder: URL) -> FolderFingerprint? {
        guard isVolumeAvailable(folder) else { return nil }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let readErrors = ReadErrorCounter()
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                readErrors.record()
                TelemetryLogger.lifecycle.warning("Photo sync could not read \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            }
        ) else { return .unreadable }

        // Enumerated URLs extend the base URL's path, so a prefix drop is enough
        // (resolving `standardizedFileURL` per file costs a round trip on the NAS).
        // The enumerator may hand back symlink-resolved paths (/var → /private/var),
        // so both spellings of the base are accepted; they are resolved once, not per file.
        let basePaths = Set([folder.path, Self.realPath(folder.path)].map { $0.hasSuffix("/") ? $0 : $0 + "/" })
        var files: [String: Int64] = [:]
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys) else {
                readErrors.record()
                continue
            }
            if values.isDirectory == true {
                if Self.isRegenerableCache(fileURL) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                  !Self.ignoredFileNames.contains(fileURL.lastPathComponent.lowercased()) else { continue }
            let path = fileURL.path
            guard let base = basePaths.first(where: { path.hasPrefix($0) }) else { continue }
            let relative = String(path.dropFirst(base.count))
            files[PhotoSyncNaming.relativePathKey(relative)] = Int64(values.fileSize ?? 0)
        }
        // An unmount mid-walk can end the enumeration early without reporting an error.
        let isComplete = readErrors.count == 0 && isVolumeAvailable(folder)
        return FolderFingerprint(files: files, isComplete: isComplete)
    }

    /// Compares a destination copy with its reference. Extra files at the destination
    /// are tolerated: the workflow only ever adds, it never mirrors deletions.
    /// A partially read copy on either side can prove neither synced nor missing.
    public func compare(reference: FolderFingerprint?, destination: FolderFingerprint?) -> CopyStatus {
        guard let reference else { return .noSource }
        guard let destination else { return .missing }
        guard reference.isComplete && destination.isComplete else { return .unverifiable }

        var missingFiles = 0
        var missingBytes: Int64 = 0
        for (path, size) in reference.files where destination.files[path] != size {
            missingFiles += 1
            missingBytes += size
        }
        return missingFiles == 0 ? .synced : .incomplete(missingFiles: missingFiles, missingBytes: missingBytes)
    }

    /// Builds the status of one project from the copies found on each volume.
    public func status(
        name: String,
        mac: URL?,
        ssd: URL?,
        nas: URL?,
        isSSDOnline: Bool,
        isNASOnline: Bool,
        now: Date = Date()
    ) -> PhotoProjectStatus {
        // A copy discovered on a volume that can no longer be read (unplugged since the
        // listing) must not silently drop out of the comparison: it is unreadable, not absent.
        let macPrint = mac.map { fingerprint(of: $0) ?? .unreadable }
        let ssdPrint = ssd.map { fingerprint(of: $0) ?? .unreadable }
        let nasPrint = nas.map { fingerprint(of: $0) ?? .unreadable }

        let macToSSD: CopyStatus
        if mac == nil {
            macToSSD = .noSource
        } else if !isSSDOnline {
            macToSSD = .volumeOffline
        } else {
            macToSSD = compare(reference: macPrint, destination: ssdPrint)
        }

        // The NAS must hold everything known locally: files still being edited on the Mac
        // count as much as the SSD copy, so the reference is their union (Mac wins on size).
        let nasReference = Self.union(ssdPrint, macPrint)
        let ssdToNAS: CopyStatus = isNASOnline
            ? compare(reference: nasReference, destination: nasPrint)
            : .volumeOffline

        let reference = macPrint ?? ssdPrint ?? nasPrint
        return PhotoProjectStatus(
            key: PhotoSyncNaming.projectKey(name),
            name: name.trimmingCharacters(in: .whitespaces),
            macPath: mac?.path,
            ssdPath: ssd?.path,
            nasPath: nas?.path,
            referenceBytes: reference?.totalBytes ?? 0,
            referenceFileCount: reference?.fileCount ?? 0,
            macToSSD: macToSSD,
            ssdToNAS: ssdToNAS,
            ssdCopyDate: ssd.flatMap { creationDate(of: $0) },
            lastModified: (mac ?? ssd).flatMap { modificationDate(of: $0) },
            checkedAt: now
        )
    }

    // MARK: - Helpers

    static func union(_ base: FolderFingerprint?, _ overlay: FolderFingerprint?) -> FolderFingerprint? {
        guard let base else { return overlay }
        guard let overlay else { return base }
        return FolderFingerprint(
            files: base.files.merging(overlay.files) { _, newer in newer },
            isComplete: base.isComplete && overlay.isComplete
        )
    }

    /// Counts the read errors the directory enumerator reports through its callback.
    private final class ReadErrorCounter {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private func subdirectories(of root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func isProjectFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if Self.libraryExtensions.contains(url.pathExtension.lowercased()) { return false }
        if (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true { return false }
        return !Self.defaultExcludedMacFolders.contains(PhotoSyncNaming.projectKey(name))
    }

    private func isExcludedNASFolder(_ url: URL) -> Bool {
        Self.excludedNASFolders.contains(PhotoSyncNaming.projectKey(url.lastPathComponent))
    }

    static func isRegenerableCache(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return regenerableCacheFolders.contains { $0.parent == parent && $0.name == url.lastPathComponent }
    }

    /// `realpath(3)`: unlike `resolvingSymlinksInPath`, it keeps the `/private` prefix
    /// that the directory enumerator reports.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func creationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
