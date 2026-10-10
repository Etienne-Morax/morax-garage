import Foundation

public enum RiskTier: Int, Comparable, Sendable, Codable, CaseIterable {
    case safe = 0        // regenerated automatically, no user cost
    case rebuildCost = 1 // recoverable, but expensive re-download or rebuild
    case destructive = 2 // data loss, broken installs, or corrupts live state
    case blocked = 3     // never offered; SafetyGate refuses it

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    
    public var title: String {
        switch self {
        case .safe: return "Safe to Delete"
        case .rebuildCost: return "Rebuild / Re-download Cost"
        case .destructive: return "Destructive / Data Loss"
        case .blocked: return "Protected & Blocked"
        }
    }
}

public enum CleanupCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case resolveRenderCache = "Resolve Render Cache"
    case resolveOptimizedMedia = "Resolve Optimised Media"
    case resolveProxies = "Resolve Proxies"
    case resolveGalleryStills = "Resolve Gallery Stills"
    case resolveLogs = "Resolve Crash & Logs"
    
    case devNodeModules = "Node Modules (JS/TS)"
    case devBuildArtifacts = "Build Artefacts (.next, dist, build)"
    case devRustTarget = "Rust Target Directories"
    case devPythonVenv = "Python Virtual Environments & Cache"
    case devXcodeDerivedData = "Xcode DerivedData"
    
    case installerDMG = "Disk Images (.dmg)"
    case installerPKG = "Installer Packages (.pkg)"
    case installerArchive = "Large Archives (.zip > 50MB)"
    case brewCache = "Homebrew Download Cache"
    
    case claudeWorktrees = "Claude Code Git Worktrees"
    case claudePreadoptBackups = "Claude Project Preadopt Backups"
    case claudeSessionTranscripts = "Claude Session Transcripts & Logs"
    case claudePluginCache = "Claude Plugin Download Cache"
    case claudeTelemetry = "Claude Telemetry & Diagnostics"
    case claudeSnapshotsAndTasks = "Claude Shell Snapshots & Tasks"
    
    case lightroomPreviews = "Lightroom Catalog Previews (.lrdata)"
    case lightroomSmartPreviews = "Lightroom Smart Previews"
    case lightroomAppCache = "Lightroom App Cache & Logs"
    case photoshopCache = "Photoshop & Camera Raw Cache"
    case captureOneSessionCache = "Capture One Session Previews & Thumbs"
    case captureOneCatalogCache = "Capture One Catalog Cache"
    case captureOneAppCache = "Capture One App & OpenCL Cache"
    
    case browserSafariCache = "Safari Browser Cache"
    case browserChromeCache = "Google Chrome Cache"
    case browserArcCache = "Arc Browser Cache"
    case browserBraveCache = "Brave Browser Cache"
    case browserFirefoxCache = "Firefox Browser Cache"
    case browserEdgeCache = "Microsoft Edge Cache"
    case browserOtherCache = "Other Browsers Cache"
    
    case systemUserCaches = "macOS User App Caches"
    case systemLogs = "System & User Diagnostic Logs"
    case systemQuickLook = "QuickLook Thumbnail Cache"
    case systemPendingSync = "Pending Cloud Sync State"

    case appWhatsAppCache = "WhatsApp Cache"
    case appWhatsAppMedia = "WhatsApp Received Media"
    case appSpotifyCache = "Spotify Cache"
    case appMessagingCache = "Messaging Apps Cache (Telegram, Slack, Discord…)"
    case appDesktopCache = "Desktop Apps Cache (Notion, VS Code, Claude…)"

    case stagedUserData = "User Data Staged from Storage Map"
    
    public var id: String { rawValue }
    
    public var defaultTier: RiskTier {
        switch self {
        case .devXcodeDerivedData, .devBuildArtifacts, .brewCache,
             .browserSafariCache, .browserChromeCache, .browserArcCache,
             .browserBraveCache, .browserFirefoxCache, .browserEdgeCache,
             .browserOtherCache, .systemUserCaches, .systemLogs,
             .systemQuickLook, .claudeTelemetry,
             .resolveRenderCache, .resolveProxies, .resolveLogs,
             .lightroomAppCache, .photoshopCache, .captureOneAppCache,
             .appWhatsAppCache, .appSpotifyCache, .appDesktopCache:
            return .safe
            
        case .devNodeModules, .devRustTarget, .devPythonVenv,
             .installerDMG, .installerPKG, .installerArchive,
             .resolveOptimizedMedia, .lightroomPreviews,
             .lightroomSmartPreviews, .captureOneSessionCache,
             .captureOneCatalogCache, .claudePluginCache, .appMessagingCache:
            return .rebuildCost
            
        case .claudeSessionTranscripts, .claudePreadoptBackups,
             .claudeWorktrees, .resolveGalleryStills,
             .claudeSnapshotsAndTasks, .systemPendingSync,
             .stagedUserData, .appWhatsAppMedia:
            return .destructive
        }
    }
    
    public var defaultRiskReason: String {
        switch self {
        case .devXcodeDerivedData, .devBuildArtifacts:
            return "Regenerated automatically upon next project build."
        case .brewCache:
            return "Homebrew package download cache — bottles will re-download if needed."
        case .browserSafariCache, .browserChromeCache, .browserArcCache,
             .browserBraveCache, .browserFirefoxCache, .browserEdgeCache, .browserOtherCache:
            return "Web browser page and resource cache — regenerated automatically."
        case .systemUserCaches:
            return "macOS user app cache — regenerated by applications as needed."
        case .systemLogs:
            return "System and application diagnostic logs."
        case .systemQuickLook:
            return "QuickLook thumbnail cache — regenerated on file preview."
        case .claudeTelemetry:
            return "Claude telemetry event logs and diagnostic traces."
        case .resolveRenderCache:
            return "DaVinci Resolve timeline render cache — regenerated on playback."
        case .resolveProxies:
            return "DaVinci Resolve proxy media — can be regenerated from source media."
        case .resolveLogs:
            return "DaVinci Resolve application diagnostic logs."
        case .lightroomAppCache, .photoshopCache, .captureOneAppCache:
            return "Application runtime and GPU cache — regenerated automatically."
            
        case .devNodeModules:
            return "Node.js dependencies — requires 'npm/pnpm/yarn install' to rebuild."
        case .devRustTarget:
            return "Rust target build directory — cargo build will recompile from scratch."
        case .devPythonVenv:
            return "Python virtual environment or cache — packages must be re-installed."
        case .installerDMG, .installerPKG, .installerArchive:
            return "Installer file or archive — will need to be re-downloaded if needed."
        case .claudePluginCache:
            return "Installed Claude plugins run from this cache — clearing it disables hooks and status lines until they are re-downloaded."
        case .resolveOptimizedMedia:
            return "DaVinci Resolve optimised media — takes time to re-generate from source."
        case .lightroomPreviews, .lightroomSmartPreviews:
            return "Lightroom catalog previews — will need time to regenerate in Lightroom."
        case .captureOneSessionCache, .captureOneCatalogCache:
            return "Capture One proxies and thumbnails — regenerated on demand in Capture One."
            
        case .claudeSessionTranscripts:
            return "Conversation history — breaks --resume and episodic memory search."
        case .claudePreadoptBackups:
            return "Project backup snapshot created before preadopt or move."
        case .claudeWorktrees:
            return "Claude subagent git worktree with unmerged branch state."
        case .resolveGalleryStills:
            return "DaVinci Resolve color grading stills and grade references."
        case .claudeSnapshotsAndTasks:
            return "Claude Code session execution state."
        case .systemPendingSync:
            return "Queued cloud synchronisation state — deleting it can drop changes that have not reached the server yet."
        case .stagedUserData:
            return "User data staged from the Storage Map — this is not a cache and nothing regenerates it."
        case .appWhatsAppCache, .appSpotifyCache, .appDesktopCache:
            return "Application cache — rebuilt automatically, accounts and settings are kept."
        case .appMessagingCache:
            return "Messaging app cache — media stays online and downloads again when opened."
        case .appWhatsAppMedia:
            return "Media received in WhatsApp chats — older media can no longer be downloaded again."
        }
    }
    
    public var iconName: String {
        switch self {
        case .resolveRenderCache, .resolveOptimizedMedia, .resolveProxies, .resolveGalleryStills, .resolveLogs:
            return "film"
        case .devNodeModules, .devBuildArtifacts, .devRustTarget, .devPythonVenv, .devXcodeDerivedData:
            return "hammer"
        case .installerDMG, .installerPKG, .installerArchive, .brewCache:
            return "archivebox"
        case .claudeWorktrees:
            return "arrow.triangle.branch"
        case .claudePreadoptBackups:
            return "clock.arrow.circlepath"
        case .claudeSessionTranscripts:
            return "bubble.left.and.bubble.right"
        case .claudePluginCache:
            return "puzzlepiece.extension"
        case .claudeTelemetry:
            return "waveform.path.ecg"
        case .claudeSnapshotsAndTasks:
            return "terminal"
        case .lightroomPreviews, .lightroomSmartPreviews:
            return "photo.stack"
        case .lightroomAppCache:
            return "photo.badge.checkmark"
        case .photoshopCache:
            return "wand.and.stars"
        case .captureOneSessionCache, .captureOneCatalogCache:
            return "camera.aperture"
        case .captureOneAppCache:
            return "camera.badge.ellipsis"
        case .browserSafariCache:
            return "safari"
        case .browserChromeCache, .browserArcCache, .browserBraveCache, .browserFirefoxCache, .browserEdgeCache, .browserOtherCache:
            return "globe"
        case .systemUserCaches:
            return "internaldrive"
        case .systemLogs:
            return "doc.text.magnifyingglass"
        case .systemQuickLook:
            return "eye"
        case .systemPendingSync:
            return "icloud.and.arrow.up"
        case .stagedUserData:
            return "exclamationmark.shield"
        case .appWhatsAppCache, .appMessagingCache:
            return "message"
        case .appWhatsAppMedia:
            return "photo.on.rectangle"
        case .appSpotifyCache:
            return "music.note"
        case .appDesktopCache:
            return "macwindow"
        }
    }
}

public struct FileItem: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let url: URL
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let modifiedDate: Date
    public let category: CleanupCategory
    public let riskTier: RiskTier
    public let riskReason: String
    public let isRecent: Bool
    private var _isSelected: Bool = false
    public var isSelected: Bool {
        get {
            riskTier == .blocked ? false : _isSelected
        }
        set {
            if riskTier != .blocked {
                _isSelected = newValue
            }
        }
    }
    public let details: String
    
    public init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        sizeBytes: Int64,
        modifiedDate: Date,
        category: CleanupCategory,
        riskTier: RiskTier,
        riskReason: String = "",
        isRecent: Bool = false,
        isSelected: Bool = false, // MUST BE FALSE BY DEFAULT
        details: String = ""
    ) {
        self.id = id
        self.url = url
        self.path = url.path
        self.name = name ?? url.lastPathComponent
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
        self.category = category
        self.riskTier = riskTier
        self.riskReason = riskReason.isEmpty ? category.defaultRiskReason : riskReason
        self.isRecent = isRecent
        self._isSelected = isSelected && (riskTier != .blocked)
        self.details = details
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case path
        case name
        case sizeBytes
        case modifiedDate
        case category
        case riskTier
        case riskReason
        case isRecent
        case isSelected
        case details
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(URL.self, forKey: .url)
        self.path = try container.decodeIfPresent(String.self, forKey: .path) ?? url.path
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? url.lastPathComponent
        self.sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        self.modifiedDate = try container.decodeIfPresent(Date.self, forKey: .modifiedDate) ?? Date()
        self.category = try container.decode(CleanupCategory.self, forKey: .category)
        self.riskTier = try container.decode(RiskTier.self, forKey: .riskTier)
        self.riskReason = try container.decodeIfPresent(String.self, forKey: .riskReason) ?? ""
        self.isRecent = try container.decodeIfPresent(Bool.self, forKey: .isRecent) ?? false
        let sel = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        self._isSelected = sel && (self.riskTier != .blocked)
        self.details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(modifiedDate, forKey: .modifiedDate)
        try container.encode(category, forKey: .category)
        try container.encode(riskTier, forKey: .riskTier)
        try container.encode(riskReason, forKey: .riskReason)
        try container.encode(isRecent, forKey: .isRecent)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(details, forKey: .details)
    }
}

/// Represents a persistent snapshot of the Cleanup / Cache scanner results on disk
public struct CleanupSnapshot: Codable, Sendable {
    public let scannerRawValue: String
    public let lastScanDate: Date
    public let items: [FileItem]
    
    public init(
        scannerRawValue: String,
        lastScanDate: Date,
        items: [FileItem]
    ) {
        self.scannerRawValue = scannerRawValue
        self.lastScanDate = lastScanDate
        self.items = items
    }
}
