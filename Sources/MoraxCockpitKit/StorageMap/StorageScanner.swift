import Foundation

public struct StorageScanProgress: Sendable, Equatable {
    public let scannedCount: Int
    public let scannedAllocatedBytes: Int64
    public let scannedLogicalBytes: Int64
    public let currentPath: String
    public let errorsCount: Int
    public let isCompleted: Bool
    
    public init(
        scannedCount: Int,
        scannedAllocatedBytes: Int64,
        scannedLogicalBytes: Int64,
        currentPath: String,
        errorsCount: Int,
        isCompleted: Bool
    ) {
        self.scannedCount = scannedCount
        self.scannedAllocatedBytes = scannedAllocatedBytes
        self.scannedLogicalBytes = scannedLogicalBytes
        self.currentPath = currentPath
        self.errorsCount = errorsCount
        self.isCompleted = isCompleted
    }
}

/// Tuning for a walk. The defaults are what the app uses; tests that assert on tiny
/// fixtures opt out of pruning.
public struct StorageScanOptions: Sendable {
    /// Entries smaller than this are folded into a single aggregate node per directory.
    /// Their bytes still count in every total: only their individual nodes are dropped.
    /// A whole-disk walk sees millions of entries and keeping a node for each one costs
    /// gigabytes of memory for tiles the treemap could never draw.
    public var minRetainedBytes: Int64
    
    public init(minRetainedBytes: Int64) {
        self.minRetainedBytes = minRetainedBytes
    }
    
    public static let `default` = StorageScanOptions(minRetainedBytes: 1 * 1024 * 1024)
    public static let retainEverything = StorageScanOptions(minRetainedBytes: 0)
}

public final class StorageScanner: @unchecked Sendable {
    public static let shared = StorageScanner()

    public init() {}

    /// `SF_DATALESS`: the file has no data on disk, only a stub the provider materialises
    /// on first read. Set by iCloud and by File Provider extensions (Google Drive, Dropbox...).
    /// Not exported to Swift by Darwin, hence the literal.
    private static let sfDataless: UInt32 = 0x4000_0000

    /// Directories whose contents are only meaningful for the mount points they expose.
    private static let mountRootPaths: Set<String> = ["/Volumes", "/net", "/home"]

    /// Mount points whose contents are already reachable elsewhere in the same walk.
    ///
    /// macOS firmlinks the Data volume into the system volume: `/Users`, `/Applications`
    /// and `/Library` are the Data volume seen from `/`. The volume is also mounted at
    /// `/System/Volumes/Data`, where the very same bytes appear a second time — walking
    /// both would double the reported size of the disk. Firmlinks are not symlinks and
    /// `realpath` does not collapse them, so the duplicate has to be named.
    static let firmlinkDuplicateMountPoints: Set<String> = [
        "/System/Volumes/Data",
        "/System/Volumes/Data/home"
    ]

    /// True when `path` is the duplicate view of content the walk already covers from the
    /// root it was given.
    static func isFirmlinkDuplicate(path: String, scanRootPath: String) -> Bool {
        guard firmlinkDuplicateMountPoints.contains(path) else { return false }
        // Scanning the Data volume directly is a deliberate choice and must still work.
        return !scanRootPath.hasPrefix(path)
    }

    /// The only resource value the walk needs, and it is asked for directories alone.
    ///
    /// The cloud keys (`isUbiquitousItem`, `ubiquitousItemDownloadingStatus`) were measured
    /// to route every single file through the FileProvider machinery — millions of
    /// `NSInvocation` round trips and gigabytes of autoreleased objects on a home scan.
    /// `SF_DATALESS` from `lstat` answers the same question for free.
    private static let directoryResourceKeys: Set<URLResourceKey> = [.isPackageKey]

    // MARK: - Public API

    /// Scans a root URL and builds a StorageNode tree with progressive updates.
    ///
    /// Convenience overload kept for callers that only need the tree.
    public func scan(
        rootURL: URL,
        options: StorageScanOptions = .default,
        onProgress: (@Sendable (StorageScanProgress) -> Void)? = nil
    ) async throws -> StorageNode {
        try await scanWithReport(rootURL: rootURL, options: options, onProgress: onProgress).rootNode
    }

    /// Scans a root URL and returns both the tree and a completeness report.
    ///
    /// The walk includes hidden entries (dotfolders such as `~/.ollama` routinely hold more
    /// than the visible home) and descends into packages so bundles are sized, not counted
    /// as zero-byte leaves. It never opens a file, so dataless cloud placeholders are
    /// measured from their metadata and are never materialised.
    public func scanWithReport(
        rootURL: URL,
        options: StorageScanOptions = .default,
        onProgress: (@Sendable (StorageScanProgress) -> Void)? = nil
    ) async throws -> StorageScanResult {
        // Child paths are built by appending to the root's path, so the root must be the
        // real path the kernel reports (`/var` is a symlink to `/private/var`). Without
        // this, nodes would carry a path that does not match the one Foundation reports
        // for the same file.
        let canonicalRootURL = Self.realPathURL(SafetyGate.canonicalize(url: rootURL))
        let rootCanonicalPath = canonicalRootURL.path
        
        var visitedCanonicalPaths = Set<String>()
        visitedCanonicalPaths.insert(rootCanonicalPath)
        
        var scannedCount = 0
        var scannedAllocatedBytes: Int64 = 0
        var scannedLogicalBytes: Int64 = 0
        var datalessLogicalBytes: Int64 = 0
        var issueLog = StorageScanIssueLog()
        // A hardlinked file is one set of blocks reachable from several names, and a pure
        // APFS clone (Finder duplicate, `cp -c`) shares every block with its source. Summing
        // `st_blocks` per name counted those bytes once per name.
        var sharedDataTracker = SharedDataTracker()
        var lastProgressUpdateTime = Date.distantPast
        let hasFullDiskAccess = PermissionsService.probeFullDiskAccess()

        guard let rootStat = Self.lstat(path: rootCanonicalPath) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: rootCanonicalPath])
        }
        let rootDeviceID = rootStat.st_dev

        func record(_ kind: StorageScanIssueKind, path: String, message: String) {
            issueLog.record(kind, path: path, message: message)
        }

        func reportProgress(currentPath: String, force: Bool = false) {
            let now = Date()
            if force || now.timeIntervalSince(lastProgressUpdateTime) >= 0.25 { // ~4 updates per sec: smooth enough without thrashing the UI
                lastProgressUpdateTime = now
                let progress = StorageScanProgress(
                    scannedCount: scannedCount,
                    scannedAllocatedBytes: scannedAllocatedBytes,
                    scannedLogicalBytes: scannedLogicalBytes,
                    currentPath: currentPath,
                    errorsCount: issueLog.totalCount,
                    isCompleted: false
                )
                onProgress?(progress)
            }
        }
        
        // Immediate initial notification
        reportProgress(currentPath: canonicalRootURL.path, force: true)

        /// Decides whether a mount boundary may be crossed.
        ///
        /// The scan must not silently wander onto another volume: an external disk or a
        /// network share would inflate the total for a disk the user did not ask about.
        /// The boot volume group is the documented exception — `/` and
        /// `/System/Volumes/Data` are firmlinked and share a device id, so the home
        /// directory stays reachable from a `/` scan without any special case.
        func boundaryIssue(forPath path: String, deviceID: dev_t) -> StorageScanIssueKind? {
            guard deviceID != rootDeviceID else { return nil }
            return Self.isPseudoFilesystem(path: path) ? .pseudoFilesystem : .volumeBoundary
        }

        // Each directory drains its own autorelease pool. Foundation's directory and
        // resource-value APIs autorelease heavily, and without a pool per level a home scan
        // accumulated gigabytes of temporaries that only the top-level pool would free.
        func scanDirectory(dirURL: URL, depth: Int) throws -> StorageNode {
            try autoreleasepool { try scanDirectoryBody(dirURL: dirURL, depth: depth) }
        }
        
        func scanDirectoryBody(dirURL: URL, depth: Int) throws -> StorageNode {
            try Task.checkCancellation()
            reportProgress(currentPath: dirURL.path)
            
            let dirPath = dirURL.path
            let dirValues = try? dirURL.resourceValues(forKeys: Self.directoryResourceKeys)
            let isPkg = dirValues?.isPackage ?? false
            let dirStat = Self.lstat(path: dirPath)
            let modDate = dirStat.map { Date(timeIntervalSince1970: TimeInterval($0.st_mtimespec.tv_sec)) } ?? Date()
            
            let dirNode = StorageNode(
                url: dirURL,
                name: dirURL.lastPathComponent.isEmpty ? dirURL.path : dirURL.lastPathComponent,
                isDirectory: true,
                isPackage: isPkg,
                modifiedDate: modDate
            )
            
            // Enumerated with `readdir`, not through Foundation: a whole-disk walk sees
            // millions of entries, and one bridged `NSString` plus one `NSURL` each is
            // memory and time spent before the entry is even known to matter.
            let entryNames: [String]
            switch Self.readDirectoryEntries(atPath: dirPath) {
            case .success(let names):
                entryNames = names
            case .failure(let errorCode):
                let message = String(cString: strerror(errorCode))
                let kind = Self.issueKind(forErrno: errorCode, path: dirPath, ownerUID: dirStat?.st_uid, hasFullDiskAccess: hasFullDiskAccess)
                record(kind, path: dirPath, message: message)
                dirNode.accessError = message
                return dirNode
            }
            
            var childrenNodes: [StorageNode] = []
            // Small files are folded on the spot: allocating a node for each one is what a
            // whole-disk walk cannot afford, and the aggregate keeps their bytes.
            var fold = FoldedEntries()
            let isMountRoot = Self.mountRootPaths.contains(dirPath)
            
            for entryName in entryNames {
                try Task.checkCancellation()
                
                // The root directory already ends with its separator: joining naively there
                // produces `//Users`, which no longer matches any of the paths this walk
                // compares against (mount points, firmlink duplicates, denylists).
                let rawPath = dirPath == "/" ? "/" + entryName : dirPath + "/" + entryName
                scannedCount += 1
                reportProgress(currentPath: rawPath)
                
                guard let info = Self.lstat(path: rawPath) else {
                    // `lstat` on an entry fails when its parent is listable but not
                    // searchable (`r` without `x`), so the parent's owner decides who
                    // could fix it.
                    let errorCode = errno
                    let message = String(cString: strerror(errorCode))
                    let kind = Self.issueKind(forErrno: errorCode, path: rawPath, ownerUID: dirStat?.st_uid, hasFullDiskAccess: hasFullDiskAccess)
                    record(kind, path: rawPath, message: message)
                    let errNode = StorageNode(
                        url: URL(fileURLWithPath: rawPath),
                        accessError: message,
                        modifiedDate: Date()
                    )
                    childrenNodes.append(errNode)
                    continue
                }

                let mode = info.st_mode & S_IFMT
                let isSymlink = mode == S_IFLNK
                let isDir = mode == S_IFDIR
                let itemModDate = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                let itemURL = URL(fileURLWithPath: rawPath, isDirectory: isDir)

                // Volume boundary: a different device is either a pseudo filesystem or another
                // volume. Either way the walk stops here and the skip is reported.
                if !isSymlink, let boundary = boundaryIssue(forPath: rawPath, deviceID: info.st_dev) {
                    let message = boundary == .pseudoFilesystem
                        ? "Pseudo filesystem skipped (no reclaimable bytes)"
                        : "Other volume skipped (scan stays on the volume you selected)"
                    record(boundary, path: rawPath, message: message)
                    let boundaryNode = StorageNode(
                        url: itemURL,
                        isDirectory: isDir,
                        accessError: message,
                        modifiedDate: itemModDate
                    )
                    childrenNodes.append(boundaryNode)
                    continue
                }

                // The Data volume, already walked through its firmlinks.
                if isDir && Self.isFirmlinkDuplicate(path: rawPath, scanRootPath: rootCanonicalPath) {
                    let message = "Déjà parcouru via les firmlinks (/Users, /Applications, /Library)"
                    record(.volumeBoundary, path: rawPath, message: message)
                    childrenNodes.append(StorageNode(
                        url: itemURL,
                        isDirectory: true,
                        accessError: message,
                        modifiedDate: itemModDate
                    ))
                    continue
                }

                // `/Volumes` and friends only contain mount points of other volumes.
                if isMountRoot && isDir {
                    let message = "Other volume skipped (scan stays on the volume you selected)"
                    record(.volumeBoundary, path: rawPath, message: message)
                    childrenNodes.append(StorageNode(
                        url: itemURL,
                        isDirectory: true,
                        accessError: message,
                        modifiedDate: itemModDate
                    ))
                    continue
                }

                // Only directories can be packages, and the lookup is not free.
                let isPackage = isDir
                    ? ((try? itemURL.resourceValues(forKeys: Self.directoryResourceKeys))?.isPackage ?? false)
                    : false

                // Dataless detection, metadata only. Opening one of these would ask the
                // provider to download gigabytes, so the file is never read.
                let hasDatalessFlag = (info.st_flags & Self.sfDataless) != 0

                let logicalSize = Int64(info.st_size)
                // st_blocks is the truth about occupied space: a dataless placeholder or a
                // sparse file reports 0 here while advertising a multi-gigabyte st_size.
                let allocatedSize = Int64(info.st_blocks) * 512
                let isDatalessPlaceholder = !isDir && (
                    hasDatalessFlag
                    // Providers that expose no flag still leave the tell: a file advertising a
                    // size while occupying no block. Restricted to provider roots so that
                    // sparse or APFS-compressed files elsewhere stay ordinary files.
                    || (allocatedSize == 0 && logicalSize > 0 && Self.isUnderCloudProviderRoot(path: rawPath))
                )

                if isSymlink {
                    let canonicalItem = SafetyGate.canonicalize(url: itemURL)
                    let canonicalPath = canonicalItem.path
                    let targetIsDir = Self.lstat(path: canonicalPath).map { ($0.st_mode & S_IFMT) == S_IFDIR } ?? false
                    
                    let escapes = !canonicalPath.hasPrefix(rootCanonicalPath)
                    let isCycle = visitedCanonicalPaths.contains(canonicalPath)
                    
                    if escapes || isCycle || !targetIsDir {
                        // Do not recursively traverse escaping or cyclic symlinks
                        let accessError = isCycle
                            ? "Symlink cycle detected"
                            : (escapes ? "Symlink targets outside scan root" : nil)
                        if let accessError {
                            record(isCycle ? .recursionLoop : .symlinkEscape, path: rawPath, message: accessError)
                        }
                        let symNode = StorageNode(
                            url: itemURL,
                            logicalSizeBytes: logicalSize,
                            allocatedSizeBytes: allocatedSize,
                            itemCount: 1,
                            isDirectory: false,
                            isPackage: isPackage,
                            isCloudPlaceholder: false,
                            isSymlink: true,
                            accessError: accessError,
                            modifiedDate: itemModDate
                        )
                        childrenNodes.append(symNode)
                        scannedAllocatedBytes += allocatedSize
                        scannedLogicalBytes += logicalSize
                    } else {
                        // Safe directory symlink within scan root
                        visitedCanonicalPaths.insert(canonicalPath)
                        let subNode = try scanDirectory(dirURL: canonicalItem, depth: depth + 1)
                        subNode.parent = dirNode
                        childrenNodes.append(subNode)
                    }
                } else if isDir {
                    // Packages are walked too: a .photoslibrary or .app reports no size of its
                    // own, so treating it as a leaf silently dropped its whole content.
                    let canonicalPath = SafetyGate.canonicalize(url: itemURL).path
                    if visitedCanonicalPaths.contains(canonicalPath) {
                        record(.recursionLoop, path: rawPath, message: "Directory recursion loop detected")
                        let loopNode = StorageNode(
                            url: itemURL,
                            isDirectory: true,
                            accessError: "Directory recursion loop detected",
                            modifiedDate: itemModDate
                        )
                        childrenNodes.append(loopNode)
                    } else {
                        visitedCanonicalPaths.insert(canonicalPath)
                        let subNode = try scanDirectory(dirURL: itemURL, depth: depth + 1)
                        subNode.parent = dirNode
                        childrenNodes.append(subNode)
                    }
                } else {
                    let isSharedDuplicate = !isDatalessPlaceholder && sharedDataTracker.isDuplicate(
                        inode: UInt64(info.st_ino),
                        linkCount: Int(info.st_nlink),
                        allocatedBytes: allocatedSize,
                        cloneID: { Self.cloneID(path: rawPath) }
                    )
                    let nodeAllocated = (isDatalessPlaceholder || isSharedDuplicate) ? 0 : allocatedSize
                    let nodeLogical = isSharedDuplicate ? 0 : logicalSize
                    
                    if nodeAllocated < options.minRetainedBytes {
                        fold.add(
                            category: StorageCategory.categorize(
                                path: rawPath,
                                isDirectory: false,
                                isPackage: isPackage,
                                isCloudPlaceholder: isDatalessPlaceholder
                            ),
                            allocated: nodeAllocated,
                            logical: nodeLogical,
                            dataless: isDatalessPlaceholder ? logicalSize : 0,
                            count: 1
                        )
                    } else {
                        let fileNode = StorageNode(
                            url: itemURL,
                            logicalSizeBytes: nodeLogical,
                            allocatedSizeBytes: nodeAllocated,
                            itemCount: 1,
                            isDirectory: false,
                            isPackage: isPackage,
                            isCloudPlaceholder: isDatalessPlaceholder,
                            isSymlink: false,
                            modifiedDate: itemModDate
                        )
                        fileNode.parent = dirNode
                        childrenNodes.append(fileNode)
                    }
                    
                    if isDatalessPlaceholder {
                        datalessLogicalBytes += logicalSize
                    } else {
                        scannedAllocatedBytes += nodeAllocated
                    }
                    scannedLogicalBytes += nodeLogical
                }
            }
            
            dirNode.children = Self.prunedChildren(
                of: dirNode,
                children: childrenNodes,
                folded: fold,
                options: options
            )
            dirNode.recalculateAggregates()
            
            // A package is sized by walking it, then collapsed: its internals are never
            // browsed on the map, and a Photos library alone would otherwise add hundreds
            // of thousands of nodes to the tree held in memory.
            if isPkg {
                dirNode.children = []
            }
            return dirNode
        }
        
        let rootNode = try scanDirectory(dirURL: canonicalRootURL, depth: 0)

        let reconciliation = Self.reconcile(
            rootURL: canonicalRootURL,
            scannedAllocatedBytes: rootNode.allocatedSizeBytes,
            datalessLogicalBytes: datalessLogicalBytes
        )

        let report = StorageScanReport(
            issueLog: issueLog,
            sharedData: sharedDataTracker.summary,
            scannedItemCount: scannedCount,
            allocatedBytes: rootNode.allocatedSizeBytes,
            logicalBytes: rootNode.logicalSizeBytes,
            datalessLogicalBytes: datalessLogicalBytes,
            reconciliation: reconciliation
        )
        
        onProgress?(StorageScanProgress(
            scannedCount: scannedCount,
            scannedAllocatedBytes: rootNode.allocatedSizeBytes,
            scannedLogicalBytes: rootNode.logicalSizeBytes,
            currentPath: rootNode.path,
            errorsCount: issueLog.totalCount,
            isCompleted: true
        ))
        
        return StorageScanResult(rootNode: rootNode, report: report)
    }

    /// Running totals for the entries a directory folded instead of keeping as nodes.
    struct FoldedEntries {
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var dataless: Int64 = 0
        var count: Int = 0
        var breakdown: [StorageCategory: Int64] = [:]
        
        mutating func add(category: StorageCategory, allocated: Int64, logical: Int64, dataless: Int64, count: Int) {
            self.allocated += allocated
            self.logical += logical
            self.dataless += dataless
            self.count += count
            if allocated > 0 {
                breakdown[category, default: 0] += allocated
            }
        }
        
        mutating func merge(_ node: StorageNode) {
            allocated += node.allocatedSizeBytes
            logical += node.logicalSizeBytes
            dataless += node.datalessLogicalBytes
            count += node.isAggregate ? node.itemCount : (node.isDirectory ? node.itemCount + 1 : 1)
            if node.categoryBreakdown.isEmpty {
                if node.allocatedSizeBytes > 0 {
                    breakdown[node.category, default: 0] += node.allocatedSizeBytes
                }
            } else {
                for (category, size) in node.categoryBreakdown {
                    breakdown[category, default: 0] += size
                }
            }
        }
    }
    
    /// Folds a directory's long tail of small entries into one synthetic node.
    ///
    /// Totals are unaffected: the aggregate carries the summed sizes, item count and
    /// category breakdown of everything it replaces. What is lost is the ability to
    /// inspect entries too small to ever be drawn, which is the price of keeping a
    /// whole-disk tree in a few hundred megabytes instead of a dozen gigabytes.
    private static func prunedChildren(
        of dirNode: StorageNode,
        children: [StorageNode],
        folded: FoldedEntries,
        options: StorageScanOptions
    ) -> [StorageNode] {
        guard options.minRetainedBytes > 0 else { return children }
        
        var retained: [StorageNode] = []
        var fold = folded
        
        for child in children {
            // Retention is decided on occupied bytes only. A cloud placeholder advertises
            // gigabytes while holding none, and a node per placeholder is memory spent on
            // something the map cannot draw; its size still reaches the totals through the
            // aggregate. Anything that reported an error is always kept: a scan must be
            // able to point at what it could not read.
            let mustKeep = child.allocatedSizeBytes >= options.minRetainedBytes
                || child.accessError != nil
            if mustKeep {
                retained.append(child)
            } else {
                fold.merge(child)
            }
        }
        
        guard fold.count > 0 else { return retained }
        
        retained.append(StorageNode.makeAggregate(in: dirNode, folded: fold))
        return retained
    }

    // MARK: - Filesystem primitives

    /// Roots managed by a cloud provider, where a zero-block file is a placeholder rather
    /// than a sparse file.
    private static let cloudProviderMarkers = [
        "/Library/CloudStorage/",
        "/Library/Application Support/FileProvider/",
        "/Library/Mobile Documents/",
        "/Library/Group Containers/com.apple.CloudDocs"
    ]

    static func isUnderCloudProviderRoot(path: String) -> Bool {
        cloudProviderMarkers.contains { path.contains($0) }
    }

    enum DirectoryListing {
        case success([String])
        case failure(Int32)
    }
    
    /// Lists a directory's entries with `readdir`, skipping `.` and `..`.
    private static func readDirectoryEntries(atPath path: String) -> DirectoryListing {
        guard let handle = path.withCString({ opendir($0) }) else {
            return .failure(errno)
        }
        defer { closedir(handle) }
        
        var names: [String] = []
        while let entry = readdir(handle) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            names.append(name)
        }
        return .success(names)
    }

    private static func realPathURL(_ url: URL) -> URL {
        guard let resolved = url.path.withCString({ realpath($0, nil) }) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private static let systemDataVaultPrefixes: [String] = [
        "/System/",
        "/Library/Caches/com.apple.",
        "/private/var/db/",
        "/private/var/folders/",
        "/private/var/containers/",
        "/private/var/protected/",
        "/private/var/networkd/",
        "/private/var/OOPJit",
        "/var/db/",
        "/var/folders/",
        "/var/containers/",
        "/var/protected/",
        "/var/networkd/",
        "/var/OOPJit"
    ]

    /// True when `path` is an OS-managed Data Vault, sandbox, or SIP protected system directory
    /// that returns EPERM to unprivileged processes regardless of Full Disk Access.
    public static func isSystemProtectedDataVault(path: String) -> Bool {
        if systemDataVaultPrefixes.contains(where: { path.hasPrefix($0) }) {
            return true
        }
        if path.hasSuffix(".dv") || path.hasSuffix(".classicdatavault") || path.contains(".Sandbox") {
            return true
        }
        return false
    }

    /// Maps a read failure to who can lift it: `EPERM` can be TCC (Full Disk Access) or SIP/Data Vaults,
    /// while `EACCES` is POSIX — fixable by the user on their own items, by nobody unprivileged otherwise.
    public static func issueKind(
        forErrno errorCode: Int32,
        path: String? = nil,
        ownerUID: uid_t?,
        hasFullDiskAccess: Bool? = nil,
        currentUID: uid_t = getuid()
    ) -> StorageScanIssueKind {
        switch errorCode {
        case EPERM:
            let fda = hasFullDiskAccess ?? (path != nil ? PermissionsService.probeFullDiskAccess() : false)
            if fda {
                return .systemProtected
            }
            if let path, isSystemProtectedDataVault(path: path) {
                return .systemProtected
            }
            if let path, let ownerUID, ownerUID != currentUID, !path.hasPrefix("/Users/") {
                return .systemProtected
            }
            return .permissionDenied
        case EACCES:
            guard let ownerUID, ownerUID != currentUID else { return .posixDenied }
            return .systemProtected
        default:
            return .unreadable
        }
    }

    /// APFS clone identifier of a file's data stream: pure clones share it. `nil` when the
    /// volume does not track clones or the attribute cannot be read.
    static func cloneID(path: String) -> UInt64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID)

        // u_int32_t length, attribute_set_t (5 × u_int32_t), then the u_int64_t clone id.
        let returnedForkAttrOffset = 4 + 4 * 4
        let cloneIDOffset = 4 + MemoryLayout<attribute_set_t>.size
        var buffer = [UInt8](repeating: 0, count: cloneIDOffset + MemoryLayout<UInt64>.size)
        let options = UInt32(FSOPT_NOFOLLOW) | UInt32(FSOPT_ATTR_CMN_EXTENDED)
        let status = path.withCString { cPath in
            buffer.withUnsafeMutableBytes { raw in
                getattrlist(cPath, &request, raw.baseAddress, raw.count, options)
            }
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            let returnedForkAttrs = raw.loadUnaligned(fromByteOffset: returnedForkAttrOffset, as: UInt32.self)
            guard returnedForkAttrs & UInt32(ATTR_CMNEXT_CLONEID) != 0 else { return nil }
            return raw.loadUnaligned(fromByteOffset: cloneIDOffset, as: UInt64.self)
        }
    }

    private static func lstat(path: String) -> stat? {
        var info = stat()
        guard path.withCString({ Darwin.lstat($0, &info) }) == 0 else { return nil }
        return info
    }

    /// Mount points that never carry reclaimable user bytes. Matched by path because the
    /// filesystem type is not reachable from Swift without `statfs`.
    private static let pseudoFilesystemMountPoints: Set<String> = [
        "/dev", "/net", "/home", "/Network", "/System/Volumes/Data/home"
    ]

    private static func isPseudoFilesystem(path: String) -> Bool {
        if pseudoFilesystemMountPoints.contains(path) { return true }
        return pseudoFilesystemMountPoints.contains { path.hasPrefix($0 + "/") }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EPERM) || nsError.code == Int(EACCES)
        }
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileReadNoPermissionError
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlying)
        }
        return false
    }

    /// Compares the walked total against what `statfs` reports for the containing volume.
    static func reconcile(
        rootURL: URL,
        scannedAllocatedBytes: Int64,
        datalessLogicalBytes: Int64
    ) -> StorageScanReconciliation? {
        // A `/` scan also covers the Data volume: the two are firmlinked, so walking `/`
        // walks `/Users` and everything else that actually holds the bytes. Both count as
        // reached, and the comparison is made against the volume that stores them.
        let dataVolumePath = "/System/Volumes/Data"
        let isWholeSystemScan = rootURL.path == "/"
        let reachableMountPoints: Set<String> = isWholeSystemScan
            ? ["/", dataVolumePath]
            : [VolumeSpaceAudit.mountPoint(forPath: rootURL.path)]
        
        let auditPath = isWholeSystemScan ? dataVolumePath : rootURL.path
        guard let audit = VolumeSpaceAudit.audit(
            pathOnVolume: auditPath,
            reachableMountPoints: reachableMountPoints
        ) else {
            return nil
        }
        
        let coversWholeVolume = isWholeSystemScan || rootURL.path == audit.mountPoint
        return StorageScanReconciliation(
            volumePath: audit.mountPoint,
            volumeTotalBytes: audit.totalBytes,
            volumeUsedBytes: audit.usedBytes,
            scannedAllocatedBytes: scannedAllocatedBytes,
            coversWholeVolume: coversWholeVolume,
            // Sibling volumes and purgeable space only add up against a whole-volume scan.
            // Next to a subfolder total they would suggest an accounting that does not hold.
            siblingVolumes: coversWholeVolume ? audit.siblingVolumes : [],
            purgeableBytes: coversWholeVolume ? audit.purgeableBytes : 0,
            datalessLogicalBytes: datalessLogicalBytes
        )
    }
}
