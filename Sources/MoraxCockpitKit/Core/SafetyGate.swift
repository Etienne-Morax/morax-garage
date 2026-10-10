import Foundation

public enum SafetyGateError: Error, LocalizedError, Equatable {
    case pathIsDenylisted(String, reason: String)
    case userDataProtected(String, reason: String)
    case pathEscapesScanRoot(itemPath: String, resolvedPath: String, scanRoot: String)
    case homeRootProtected
    case rootFilesystemProtected
    case nullByteInPath
    case resolveProjectDataProtected(String)
    case photoAppMasterDataProtected(String)
    case cloudSyncedContainerProtected(String)
    case itemCapExceeded(count: Int, cap: Int)
    case batchSizeCapExceeded(sizeBytes: Int64, capBytes: Int64)
    case invalidPath(String)
    
    public var errorDescription: String? {
        switch self {
        case .pathIsDenylisted(let path, let reason):
            return "Protected path violation (\(reason)): \(path)"
        case .userDataProtected(let path, let reason):
            return "Protected user data violation (\(reason)): \(path)"
        case .pathEscapesScanRoot(let item, let resolved, let root):
            return "Symlink escape detected: '\(item)' resolves to '\(resolved)' outside root '\(root)'"
        case .homeRootProtected:
            return "Cannot delete the user home directory root."
        case .rootFilesystemProtected:
            return "Cannot delete the root filesystem."
        case .nullByteInPath:
            return "Path contains illegal null bytes."
        case .resolveProjectDataProtected(let path):
            return "DaVinci Resolve project database/backup protection triggered: \(path)"
        case .photoAppMasterDataProtected(let path):
            return "Photo application master catalog/adjustments protection triggered: \(path)"
        case .cloudSyncedContainerProtected(let path):
            return "iCloud Drive container protection triggered (deletion would propagate to every device): \(path)"
        case .itemCapExceeded(let count, let cap):
            return "Operation contains \(count) items, which exceeds the hard safety cap of \(cap) items."
        case .batchSizeCapExceeded(let size, let cap):
            let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            let formattedCap = ByteCountFormatter.string(fromByteCount: cap, countStyle: .file)
            return "Batch size \(formattedSize) exceeds the safety cap of \(formattedCap)."
        case .invalidPath(let path):
            return "Invalid filesystem path: \(path)"
        }
    }
}

public struct SafetyGate: Sendable {
    public static let maxItemCap = 10_000
    public static let maxBatchSizeBytes: Int64 = 20 * 1024 * 1024 * 1024 // 20 GB
    
    public static let systemDenylistPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/private/var/db",
        "/var/db",
        "/Library/Apple",
        "/Library/SystemExtensions",
        "/Library/Preferences/SystemConfiguration"
    ]
    
    public static let userDataDenylistSubpaths: [(subpath: String, reason: String)] = [
        (".claude/backups", "Claude recovery backups"),
        (".claude/plans", "Claude agent plans"),
        (".claude/scheduled-tasks", "Claude scheduled tasks"),
        (".claude/mcp-configs", "Claude MCP configuration"),
        (".claude/settings.json", "Claude settings configuration"),
        (".claude/settings.local.json", "Claude local settings configuration"),
        (".claude/history.jsonl", "Claude CLI history"),
        ("Library/pnpm", "pnpm content-addressable store"),
        ("Library/Caches/pnpm", "pnpm content-addressable cache")
    ]

    /// Directories that are containers for user data rather than data themselves.
    ///
    /// Only the directory itself is refused: the cleanup scanners legitimately offer
    /// artefacts *inside* them (a `node_modules` under `~/Documents`, a stale `.dmg`
    /// in `~/Downloads`), so a prefix rule would disable the product. What must never
    /// happen is the container going to the Trash as a single item.
    public static let protectedContainerSubpaths: [String] = [
        "Documents",
        "Desktop",
        "Downloads",
        "Pictures",
        "Music",
        "Movies",
        "Public",
        "Applications",
        "Library",
        "Library/Application Support",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Caches",
        "Library/Preferences",
        "Library/Logs",
        "Library/Developer",
        ".claude",
        ".claude/projects",
        ".claude/plugins",
        ".config",
        ".ssh",
        ".gnupg"
    ]

    /// Absolute container paths refused as a whole, outside the user home.
    public static let protectedAbsoluteContainers: [String] = [
        "/Applications",
        "/Library",
        "/Users",
        "/Volumes",
        "/opt",
        "/opt/homebrew"
    ]
    
    /// Canonicalizes a path by resolving firmlinks (/var -> /private/var, etc.) and symlinks
    public static func canonicalize(url: URL) -> URL {
        let path = url.path
        var canonicalPath = path
        
        // Firmlink normalization
        if canonicalPath == "/var" || canonicalPath.hasPrefix("/var/") {
            canonicalPath = "/private" + canonicalPath
        } else if canonicalPath == "/tmp" || canonicalPath.hasPrefix("/tmp/") {
            canonicalPath = "/private" + canonicalPath
        } else if canonicalPath == "/etc" || canonicalPath.hasPrefix("/etc/") {
            canonicalPath = "/private" + canonicalPath
        }
        
        let normalizedURL = URL(fileURLWithPath: canonicalPath).resolvingSymlinksInPath().standardized
        return normalizedURL
    }
    
    /// Validates a list of candidate URLs before performing an operation.
    /// Checks item cap, batch size cap, denylist, home root, Resolve protection, and symlink containment.
    public static func validateBatch(urls: [URL], scanRoot: URL?, allowLargeBatch: Bool = false) throws {
        try validateBatchLimits(urls: urls, allowLargeBatch: allowLargeBatch)
        for url in urls {
            try validateForTrash(url: url, scanRoot: scanRoot)
        }
    }

    /// Checks only the batch-wide item and size caps; per-item validation is left to the caller.
    public static func validateBatchLimits(urls: [URL], allowLargeBatch: Bool = false) throws {
        guard urls.count <= maxItemCap else {
            throw SafetyGateError.itemCapExceeded(count: urls.count, cap: maxItemCap)
        }
        
        if !allowLargeBatch {
            var totalSize: Int64 = 0
            for url in urls {
                totalSize += TrashService.shared.calculateSize(url: url)
                if totalSize > maxBatchSizeBytes {
                    throw SafetyGateError.batchSizeCapExceeded(sizeBytes: totalSize, capBytes: maxBatchSizeBytes)
                }
            }
        }
    }

    /// Directory a scanned item must still resolve inside when it is trashed.
    ///
    /// Scanners report each item as found inside this directory. Symlinks among the
    /// ancestors resolve identically for the item and for this root, so only an item
    /// that is itself a link pointing somewhere else escapes it: exactly what the cleanup
    /// flow must refuse, because the scan never measured or classified the link target.
    public static func containmentRoot(for url: URL) -> URL {
        url.standardizedFileURL.deletingLastPathComponent()
    }
    
    /// Validates a raw path string before trashing
    public static func validateForTrash(path: String, scanRoot: URL? = nil) throws {
        if path.contains("\0") || path.contains("%00") {
            throw SafetyGateError.nullByteInPath
        }
        let url = URL(fileURLWithPath: path)
        try validateForTrash(url: url, scanRoot: scanRoot)
    }
    
    /// Validates an individual URL immediately before trashing (TOCTOU guard).
    public static func validateForTrash(url: URL, scanRoot: URL? = nil) throws {
        let rawPath = url.path
        
        // Check for null bytes in URL representations
        if rawPath.contains("\0") || url.absoluteString.contains("%00") {
            throw SafetyGateError.nullByteInPath
        }
        
        // Canonicalize
        let canonicalURL = canonicalize(url: url)
        let canonicalPath = canonicalURL.path
        
        // Root filesystem check
        if canonicalPath == "/" {
            throw SafetyGateError.rootFilesystemProtected
        }
        
        // Home directory root check
        let homePath = canonicalize(url: FileManager.default.homeDirectoryForCurrentUser).path
        if canonicalPath == homePath {
            throw SafetyGateError.homeRootProtected
        }
        
        // System denylist check
        for prefix in systemDenylistPrefixes {
            let canonPrefix = canonicalize(url: URL(fileURLWithPath: prefix)).path
            if canonicalPath == canonPrefix || canonicalPath.hasPrefix(canonPrefix + "/") {
                throw SafetyGateError.pathIsDenylisted(canonicalPath, reason: "System protected directory")
            }
        }
        
        // User critical library denylist
        let keychainsPath = canonicalize(url: URL(fileURLWithPath: "\(homePath)/Library/Keychains")).path
        if canonicalPath == keychainsPath || canonicalPath.hasPrefix(keychainsPath + "/") {
            throw SafetyGateError.pathIsDenylisted(canonicalPath, reason: "User Keychains directory")
        }
        
        let mobileSyncPath = canonicalize(url: URL(fileURLWithPath: "\(homePath)/Library/Application Support/MobileSync")).path
        if canonicalPath == mobileSyncPath || canonicalPath.hasPrefix(mobileSyncPath + "/") {
            throw SafetyGateError.pathIsDenylisted(canonicalPath, reason: "MobileSync backups")
        }
        
        // User Data Denylist (Claude settings/plans/backups, pnpm CAS)
        for (subpath, reason) in userDataDenylistSubpaths {
            let userProtectedURL = canonicalize(url: URL(fileURLWithPath: "\(homePath)/\(subpath)"))
            let userProtectedPath = userProtectedURL.path
            if canonicalPath == userProtectedPath || canonicalPath.hasPrefix(userProtectedPath + "/") {
                throw SafetyGateError.userDataProtected(canonicalPath, reason: reason)
            }
        }
        
        // Container directories: refuse the container itself, allow items inside it
        for subpath in protectedContainerSubpaths {
            let containerPath = canonicalize(url: URL(fileURLWithPath: "\(homePath)/\(subpath)")).path
            if canonicalPath == containerPath {
                throw SafetyGateError.userDataProtected(canonicalPath, reason: "User data container directory")
            }
        }
        for absolute in protectedAbsoluteContainers {
            let containerPath = canonicalize(url: URL(fileURLWithPath: absolute)).path
            if canonicalPath == containerPath {
                throw SafetyGateError.userDataProtected(canonicalPath, reason: "System container directory")
            }
        }

        // iCloud Drive: the container roots and each service folder are refused outright.
        try checkCloudContainerSafety(canonicalPath: canonicalPath, homePath: homePath)

        // Claude Code persistent memory is not a transcript and never regenerates.
        try checkClaudeMemorySafety(canonicalPath: canonicalPath)

        // DaVinci Resolve Critical Safety Protections
        try checkDaVinciResolveSafety(canonicalPath: canonicalPath)
        
        // Photo Apps (Lightroom, Capture One, Photoshop) Safety Protections
        try checkPhotoAppSafety(canonicalPath: canonicalPath)

        // Messaging apps: chat databases and whole app containers
        try checkMessagingAppSafety(canonicalPath: canonicalPath)
        
        // Symlink containment check against scanRoot if supplied
        if let scanRoot = scanRoot {
            let canonicalRoot = canonicalize(url: scanRoot).path
            if canonicalPath != canonicalRoot && !canonicalPath.hasPrefix(canonicalRoot + "/") {
                throw SafetyGateError.pathEscapesScanRoot(
                    itemPath: rawPath,
                    resolvedPath: canonicalPath,
                    scanRoot: canonicalRoot
                )
            }
        }
    }
    
    /// Returns `true` when the path lives inside the iCloud Drive synchronisation tree.
    ///
    /// Trashing such an item removes it from every device signed into the account, so
    /// callers surface it as data loss rather than as reclaimed disk space.
    public static func isCloudSynced(url: URL) -> Bool {
        let canonicalPath = canonicalize(url: url).path
        let homePath = canonicalize(url: FileManager.default.homeDirectoryForCurrentUser).path
        let mobileDocuments = canonicalize(url: URL(fileURLWithPath: "\(homePath)/Library/Mobile Documents")).path
        return canonicalPath == mobileDocuments || canonicalPath.hasPrefix(mobileDocuments + "/")
    }

    /// Refuses the iCloud Drive root and the per-service containers directly beneath it.
    ///
    /// Individual files stay deletable — the user may genuinely want to drop a 6 GB
    /// installer that happens to sit on an iCloud-synced Desktop — but the containers
    /// themselves (`com~apple~CloudDocs`, `Desktop`, `Documents`) are never offered.
    public static func checkCloudContainerSafety(canonicalPath: String, homePath: String) throws {
        let mobileDocuments = canonicalize(url: URL(fileURLWithPath: "\(homePath)/Library/Mobile Documents")).path
        guard canonicalPath == mobileDocuments || canonicalPath.hasPrefix(mobileDocuments + "/") else { return }

        let relative = canonicalPath.dropFirst(mobileDocuments.count).split(separator: "/").map(String.init)
        if relative.count <= 2 {
            throw SafetyGateError.cloudSyncedContainerProtected(canonicalPath)
        }
    }

    /// Refuses any Claude Code persistent-memory directory.
    ///
    /// Memory files sit inside the per-project transcript folders, which the cleanup
    /// scanner does offer. Transcripts are replaceable; memory is not.
    public static func checkClaudeMemorySafety(canonicalPath: String) throws {
        let components = canonicalPath.split(separator: "/").map(String.init)
        guard components.contains(".claude") else { return }
        if components.contains("memory") {
            throw SafetyGateError.userDataProtected(canonicalPath, reason: "Claude persistent memory")
        }
    }

    /// Strict negative check for any DaVinci Resolve project database, library, backup, or .drp export.
    public static func checkDaVinciResolveSafety(canonicalPath: String) throws {
        let lower = canonicalPath.lowercased()
        
        if lower.hasSuffix(".drp") {
            throw SafetyGateError.resolveProjectDataProtected("DaVinci Resolve project export (.drp)")
        }
        
        if lower.hasSuffix("/project.db") || lower.contains("/project.db/") {
            throw SafetyGateError.resolveProjectDataProtected("Resolve project database file")
        }
        
        if lower.contains("resolve project library") {
            throw SafetyGateError.resolveProjectDataProtected("Resolve Project Library folder")
        }
        
        if lower.contains("project backups") || lower.contains("projectbackup") {
            throw SafetyGateError.resolveProjectDataProtected("Resolve Project Backups folder")
        }
    }
    
    /// Strict negative check for any Lightroom, Capture One, or Photoshop master catalogs, adjustments, or media files.
    /// Refuses chat databases and whole messaging-app containers.
    ///
    /// Their caches sit right next to the message history, so a mis-targeted path one
    /// level up would take every conversation with it.
    public static func checkMessagingAppSafety(canonicalPath: String) throws {
        let components = canonicalPath.split(separator: "/").map(String.init)
        guard let last = components.last else { return }

        let wholeContainers: Set<String> = [
            "net.whatsapp.WhatsApp", "group.net.whatsapp.WhatsApp.shared",
            "group.net.whatsapp.WhatsApp.private", "6N38VWS5BX.ru.keepcoder.Telegram"
        ]
        if wholeContainers.contains(last) {
            throw SafetyGateError.userDataProtected(canonicalPath, reason: "Messaging application container")
        }
        if last.hasPrefix("ChatStorage.sqlite") {
            throw SafetyGateError.userDataProtected(canonicalPath, reason: "WhatsApp chat database")
        }
        if components.contains("postbox") && (last == "postbox" || components.contains("db")) {
            throw SafetyGateError.userDataProtected(canonicalPath, reason: "Telegram message database")
        }
        if components.contains("Signal") && (last == "sql" || last == "attachments.noindex") {
            throw SafetyGateError.userDataProtected(canonicalPath, reason: "Signal message database")
        }
    }

    public static func checkPhotoAppSafety(canonicalPath: String) throws {
        let lower = canonicalPath.lowercased()
        
        // Lightroom master catalog protection
        if lower.hasSuffix(".lrcat") {
            throw SafetyGateError.photoAppMasterDataProtected("Lightroom catalog database (.lrcat)")
        }
        if lower.hasSuffix(".lrcat-data") {
            throw SafetyGateError.photoAppMasterDataProtected("Lightroom catalog data (.lrcat-data)")
        }
        if lower.contains("/lightroom/backups") || lower.contains("/old lightroom catalogs") {
            throw SafetyGateError.photoAppMasterDataProtected("Lightroom catalog backup directory")
        }
        if lower.hasSuffix(".lrtemplate") {
            throw SafetyGateError.photoAppMasterDataProtected("Lightroom template/preset (.lrtemplate)")
        }
        
        // Capture One database & adjustment protection
        if lower.hasSuffix(".cocatalogdb") {
            throw SafetyGateError.photoAppMasterDataProtected("Capture One catalog database (.cocatalogdb)")
        }
        if lower.hasSuffix(".cosessiondb") {
            throw SafetyGateError.photoAppMasterDataProtected("Capture One session database (.cosessiondb)")
        }
        if lower.contains("/captureone/settings") || lower.hasSuffix(".cos") || lower.hasSuffix(".comask") {
            throw SafetyGateError.photoAppMasterDataProtected("Capture One adjustments or masks (.cos/.comask)")
        }
        
        // Original RAW / Master Media & Creative Project Protection
        let protectedExtensions = [".cr2", ".cr3", ".nef", ".arw", ".dng", ".raf", ".psd", ".psb", ".atn", ".abr"]
        for ext in protectedExtensions {
            if lower.hasSuffix(ext) {
                throw SafetyGateError.photoAppMasterDataProtected("Master media or creative file (\(ext))")
            }
        }
    }
}
