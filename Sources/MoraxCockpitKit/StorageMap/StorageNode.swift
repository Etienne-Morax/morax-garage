import Foundation
import SwiftUI
import AppKit

public enum StorageCategory: String, CaseIterable, Identifiable, Sendable, Codable, CodingKeyRepresentable {
    case videoAndRender = "Video & Render"
    case photoAndRaw = "Photos & RAW"
    case devAndBuild = "Dev & Build"
    case aiAndModels = "AI Models"
    case installersAndArchives = "Archives & DMG"
    case applications = "Apps"
    case audio = "Audio"
    case documents = "Documents"
    case systemAndCache = "Caches"
    case cloudNotDownloaded = "Cloud (non téléchargé)"
    case other = "Other"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .videoAndRender: return "film"
        case .photoAndRaw: return "photo.on.rectangle.angled"
        case .devAndBuild: return "hammer"
        case .aiAndModels: return "brain"
        case .installersAndArchives: return "archivebox"
        case .applications: return "app.badge"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .systemAndCache: return "internaldrive"
        case .cloudNotDownloaded: return "icloud.and.arrow.down"
        case .other: return "questionmark.folder"
        }
    }
    
    public var colorHex: String {
        switch self {
        case .videoAndRender: return "#8B5CF6"      // Vibrant Purple (DaVinci / Video / Footage / Renders)
        case .photoAndRaw: return "#EC4899"         // Rose / Magenta (Photo & Master RAW)
        case .devAndBuild: return "#3B82F6"         // Royal Blue (Dev / Code / Node / Build)
        case .aiAndModels: return "#14B8A6"         // Teal / Mint (AI Models / Checkpoints / SafeTensors)
        case .installersAndArchives: return "#F59E0B" // Amber / Gold (Installers / ZIP / DMG)
        case .applications: return "#10B981"        // Emerald Green (Apps & Bundles)
        case .audio: return "#F97316"               // Bright Orange (Audio / Music / SFX)
        case .documents: return "#06B6D4"           // Cyan (Documents / Spreadsheets / Presentations)
        case .systemAndCache: return "#64748B"      // Slate Gray (System & App Caches)
        case .cloudNotDownloaded: return "#38BDF8"  // Sky Blue (cloud placeholders, no local bytes)
        case .other: return "#94A3B8"               // Neutral Gray
        }
    }
    
    public var color: Color {
        Color(hex: colorHex)
    }
    
    public static func categorize(
        url: URL,
        isDirectory: Bool,
        isPackage: Bool,
        isCloudPlaceholder: Bool = false
    ) -> StorageCategory {
        categorize(
            path: url.path,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isCloudPlaceholder: isCloudPlaceholder
        )
    }
    
    /// Path based variant used by the walker.
    ///
    /// A whole-disk walk classifies millions of entries and only keeps a node for a few
    /// thousand of them; building a `URL` for each one just to read its extension is
    /// allocation spent on entries that are immediately folded away.
    public static func categorize(
        path rawPath: String,
        isDirectory: Bool,
        isPackage: Bool,
        isCloudPlaceholder: Bool = false
    ) -> StorageCategory {
        // Placeholders occupy no local block: they belong in their own bucket so their
        // logical size never reads as reclaimable space.
        if isCloudPlaceholder {
            return .cloudNotDownloaded
        }

        // Matched on bytes, not `Character`s: every needle is ASCII, and the Unicode aware
        // `String.contains` cost tens of microseconds per entry, which made a whole-disk
        // walk spend minutes classifying files it then folds away.
        let path = Array(rawPath.lowercased().utf8)
        let nameStart = (path.lastIndex(of: CategoryRules.slash).map { $0 + 1 }) ?? 0
        let name = path[nameStart...]
        let ext: String = {
            guard let dot = name.lastIndex(of: CategoryRules.dot), dot != name.startIndex else { return "" }
            return String(decoding: path[(dot + 1)...], as: UTF8.self)
        }()
        let nameString = String(decoding: name, as: UTF8.self)
        
        // 1. Applications & Packages
        if isPackage || CategoryRules.applicationExtensions.contains(ext) {
            return .applications
        }
        
        // 2. AI / ML Models & Datasets
        if CategoryRules.aiExtensions.contains(ext) ||
            CategoryRules.containsAny(name, CategoryRules.aiNameNeedles) ||
            CategoryRules.containsAny(path[...], CategoryRules.aiPathNeedles) {
            return .aiAndModels
        }
        
        // 3. DaVinci Resolve, Video, Footage & Render Caches
        if CategoryRules.containsAny(path[...], CategoryRules.videoPathNeedles) ||
            CategoryRules.videoExtensions.contains(ext) {
            return .videoAndRender
        }
        
        // 4. Photos, Master RAW & Creative Visuals
        if CategoryRules.photoExtensions.contains(ext) ||
            CategoryRules.containsAny(path[...], CategoryRules.photoPathNeedles) {
            return .photoAndRaw
        }
        
        // 5. Audio, Music & Sound FX
        if CategoryRules.audioExtensions.contains(ext) ||
            CategoryRules.containsAny(path[...], CategoryRules.audioPathNeedles) {
            return .audio
        }
        
        // 6. Developer Build, Code & Repositories
        if CategoryRules.devNames.contains(nameString) || CategoryRules.devExtensions.contains(ext) {
            return .devAndBuild
        }
        
        // 7. Installers & Large Archives
        if CategoryRules.archiveExtensions.contains(ext) {
            return .installersAndArchives
        }
        
        // 8. System & App Caches
        if CategoryRules.containsAny(path[...], CategoryRules.cachePathNeedles) ||
            CategoryRules.cacheExtensions.contains(ext) {
            return .systemAndCache
        }
        
        // 9. Documents, Text & Spreadsheets
        if CategoryRules.documentExtensions.contains(ext) {
            return .documents
        }
        
        return .other
    }
}

/// Classification tables, built once. Needles are lowercase ASCII byte strings matched
/// against the lowercased UTF-8 path.
private enum CategoryRules {
    static let slash = UInt8(ascii: "/")
    static let dot = UInt8(ascii: ".")
    
    static let applicationExtensions: Set<String> = [
        "app", "prefpane", "framework", "plugin", "qlgenerator", "component", "kext"
    ]
    static let aiExtensions: Set<String> = [
        "safetensors", "ckpt", "onnx", "bin", "pt", "pth", "gguf", "tflite", "model", "weights",
        "parquet", "h5", "hdf5", "pkl", "pickle", "npy", "npz", "arrow", "feather", "joblib"
    ]
    static let aiNameNeedles = needles(["safetensors", "checkpoint", "gguf"])
    static let aiPathNeedles = needles([
        "/models", "/checkpoints", "/lora", "/embeddings", "/comfyui", "/stable-diffusion",
        "/ollama", "/huggingface", "/transformers"
    ])
    static let videoPathNeedles = needles([
        "cacheclip", ".gallery", ".dtl", "capture scratch", "final cut documents", "proxymedia",
        "generation de videos", "/outputs", "/footage", "/renders", "/exports", "capcut"
    ])
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mxf", "braw", "r3d", "ari", "dng_raw", "avi", "mkv", "webm", "prores",
        "flv", "ts", "mts", "m2ts", "vob", "3gp", "f4v", "yuv", "cine", "dpx", "exr", "cineform",
        "dnxhr", "hevc", "264", "265", "wmv"
    ]
    static let photoExtensions: Set<String> = [
        "cr2", "cr3", "nef", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "srf", "raw", "psd",
        "psb", "tif", "tiff", "jpg", "jpeg", "png", "heic", "heif", "webp", "avif", "ai", "eps",
        "svg", "ico", "bmp", "xcf", "indd", "idml", "sketch", "fig", "xd", "hdr", "cbr", "cbz",
        "lrdata", "lrcat", "cocatalog", "cosession", "cos", "comask"
    ]
    static let photoPathNeedles = needles([
        "/photos", "/pictures", "/headshot", "/shoot", "/dcim", "/stills"
    ])
    static let audioExtensions: Set<String> = [
        "wav", "aif", "aiff", "flac", "mp3", "m4a", "aac", "ogg", "wma", "caf", "midi", "mid",
        "alac", "opus", "m4p", "pcm", "sd2", "logicx", "als", "flp", "cpr", "band", "ptx"
    ]
    static let audioPathNeedles = needles([
        "/sonniss", "/music", "/audio", "/sound", "/sfx", "/samples", "/stems"
    ])
    static let devNames: Set<String> = [
        "node_modules", ".next", "dist", "build", "target", ".venv", "venv", "__pycache__",
        ".turbo", ".gradle", "deriveddata", ".git", ".cargo", ".rustup", "haskell_cache", "claude",
        ".cache", ".npm", ".yarn", ".pnpm"
    ]
    static let devExtensions: Set<String> = [
        "o", "a", "dylib", "so", "class", "pyc", "tsbuildinfo", "bundle", "lock", "swiftmodule",
        "swiftdoc", "h", "hpp", "c", "cpp", "m", "mm", "swift", "js", "mjs", "cjs", "ts", "mts",
        "cts", "jsx", "tsx", "py", "rs", "go", "java", "kt", "rb", "php", "cs", "sh", "zsh", "bash",
        "wasm", "cmake", "gradle", "sql", "prisma", "lua", "r", "dart"
    ]
    static let archiveExtensions: Set<String> = [
        "dmg", "pkg", "iso", "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "lz4",
        "cab", "toast", "vmdk", "qcow2", "sparseimage", "sparsebundle", "appzip", "ipa", "apk",
        "img", "bin"
    ]
    static let cachePathNeedles = needles([
        "/library/caches", "/caches/", ".savedstate", "/library/logs", "quicklook"
    ])
    static let cacheExtensions: Set<String> = ["log", "asl", "crash", "diag"]
    static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "keynote", "key",
        "txt", "rtf", "md", "markdown", "json", "yaml", "yml", "xml", "csv", "tsv", "epub", "mobi",
        "html", "htm", "css", "scss", "sass", "less", "ini", "conf", "plist", "env", "toml", "ttf",
        "otf", "woff", "woff2", "srt", "vtt"
    ]
    
    private static func needles(_ strings: [String]) -> [[UInt8]] {
        strings.map { Array($0.utf8) }
    }
    
    static func containsAny(_ haystack: ArraySlice<UInt8>, _ needles: [[UInt8]]) -> Bool {
        needles.contains { contains(haystack, $0) }
    }
    
    private static func contains(_ haystack: ArraySlice<UInt8>, _ needle: [UInt8]) -> Bool {
        guard let first = needle.first, needle.count <= haystack.count else { return false }
        var index = haystack.startIndex
        let lastStart = haystack.endIndex - needle.count
        while index <= lastStart {
            if haystack[index] == first && haystack[index..<(index + needle.count)].elementsEqual(needle) {
                return true
            }
            index += 1
        }
        return false
    }
}

public final class StorageNode: Identifiable, @unchecked Sendable, Hashable, Codable {
    public let id: UUID
    public let url: URL
    public let path: String
    public let name: String
    public var logicalSizeBytes: Int64
    public var allocatedSizeBytes: Int64
    public var itemCount: Int
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isCloudPlaceholder: Bool
    public let isSymlink: Bool
    /// True for the synthetic node that stands in for a directory's long tail of small
    /// entries. It maps to no single file, so it is never a target for any action.
    public let isAggregate: Bool
    public var accessError: String?
    public let modifiedDate: Date
    public let fileExtension: String
    public var category: StorageCategory
    public var categoryBreakdown: [StorageCategory: Int64] = [:]
    /// Logical bytes held by dataless cloud placeholders under this node. Kept apart from
    /// `allocatedSizeBytes`, which only counts blocks that exist on this disk.
    public var datalessLogicalBytes: Int64 = 0
    public var children: [StorageNode]
    public weak var parent: StorageNode?
    
    public init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        logicalSizeBytes: Int64 = 0,
        allocatedSizeBytes: Int64 = 0,
        itemCount: Int = 0,
        isDirectory: Bool = false,
        isPackage: Bool = false,
        isCloudPlaceholder: Bool = false,
        isSymlink: Bool = false,
        isAggregate: Bool = false,
        accessError: String? = nil,
        modifiedDate: Date = Date(),
        fileExtension: String? = nil,
        category: StorageCategory? = nil,
        children: [StorageNode] = [],
        parent: StorageNode? = nil
    ) {
        self.id = id
        self.url = url
        self.path = url.path
        self.name = name ?? url.lastPathComponent
        self.logicalSizeBytes = logicalSizeBytes
        self.allocatedSizeBytes = allocatedSizeBytes
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isCloudPlaceholder = isCloudPlaceholder
        self.isSymlink = isSymlink
        self.isAggregate = isAggregate
        self.accessError = accessError
        self.modifiedDate = modifiedDate
        let ext = fileExtension ?? url.pathExtension
        self.fileExtension = ext
        let initialCat = category ?? StorageCategory.categorize(
            url: url,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isCloudPlaceholder: isCloudPlaceholder
        )
        self.category = initialCat
        self.children = children
        self.parent = parent
        self.datalessLogicalBytes = isCloudPlaceholder ? logicalSizeBytes : 0
        
        // Leaves deliberately keep an empty breakdown: a home scan builds over a million
        // nodes, and one dictionary each is memory spent to store what the parent can
        // derive from `category` while aggregating.
        
        for child in children {
            child.parent = self
        }
    }
    
    public static func == (lhs: StorageNode, rhs: StorageNode) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public var formattedAllocatedSize: String {
        ByteCountFormatter.string(fromByteCount: allocatedSizeBytes, countStyle: .file)
    }
    
    public var formattedLogicalSize: String {
        ByteCountFormatter.string(fromByteCount: logicalSizeBytes, countStyle: .file)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
    
    public var breakdownList: [(category: StorageCategory, size: Int64, percentage: Double)] {
        let total = max(1, allocatedSizeBytes)
        return categoryBreakdown
            .map { ($0.key, $0.value, Double($0.value) / Double(total) * 100.0) }
            .sorted { $0.size > $1.size }
    }
    
    /// Aggregate allocated size, logical size, item count and dominant category from children
    public func recalculateAggregates() {
        guard isDirectory && !children.isEmpty else { return }
        
        var totalAllocated: Int64 = 0
        var totalLogical: Int64 = 0
        var count = 0
        var totalDataless: Int64 = 0
        var aggregatedBreakdown: [StorageCategory: Int64] = [:]
        
        for child in children {
            child.recalculateAggregates()
            totalAllocated += child.allocatedSizeBytes
            totalLogical += child.logicalSizeBytes
            totalDataless += child.datalessLogicalBytes
            // An aggregate already stands for several entries, so it contributes its own
            // count rather than one.
            if child.isAggregate {
                count += child.itemCount
            } else {
                count += child.isDirectory ? (child.itemCount + 1) : 1
            }
            
            // The breakdown is expressed in allocated bytes so that its proportions match
            // the space the folder really uses. Placeholders contribute zero here and are
            // surfaced through `datalessLogicalBytes` instead.
            if !child.categoryBreakdown.isEmpty {
                for (cat, sz) in child.categoryBreakdown {
                    aggregatedBreakdown[cat, default: 0] += sz
                }
            } else if child.allocatedSizeBytes > 0 {
                aggregatedBreakdown[child.category, default: 0] += child.allocatedSizeBytes
            }
        }
        
        self.allocatedSizeBytes = totalAllocated
        self.logicalSizeBytes = totalLogical
        self.datalessLogicalBytes = totalDataless
        self.itemCount = count
        self.categoryBreakdown = aggregatedBreakdown
        
        // Dynamically assign dominant category (prefer meaningful non-other category with highest size)
        if let dominant = aggregatedBreakdown.filter({ $0.key != .other }).max(by: { $0.value < $1.value })?.key {
            self.category = dominant
        } else if let fallback = aggregatedBreakdown.max(by: { $0.value < $1.value })?.key {
            self.category = fallback
        }
    }
    
    /// Finds a node in subtree by UUID
    public func findNode(byID targetID: UUID) -> StorageNode? {
        if self.id == targetID { return self }
        for child in children {
            if let found = child.findNode(byID: targetID) {
                return found
            }
        }
        return nil
    }
    
    /// Normalises the two spellings macOS gives the same file: `/var/...` and
    /// `/private/var/...` (likewise `/tmp` and `/etc`) both reach the same inode, and
    /// which one a URL carries depends on how it was built.
    private static func comparablePath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }
    
    /// Finds a node in subtree by URL
    public func findNode(byURL targetURL: URL) -> StorageNode? {
        if Self.comparablePath(self.url) == Self.comparablePath(targetURL) { return self }
        for child in children {
            if let found = child.findNode(byURL: targetURL) {
                return found
            }
        }
        return nil
    }
    
    /// Total number of nodes in this subtree, self included.
    public var nodeCount: Int {
        var total = 1
        for child in children {
            total += child.nodeCount
        }
        return total
    }

    /// Builds the synthetic node that stands in for a set of folded entries.
    ///
    /// The aggregate carries the summed sizes, item count and category breakdown of
    /// everything it replaces, so every total stays exact: what is lost is only the
    /// ability to inspect entries individually.
    static func makeAggregate(in dirNode: StorageNode, folded: StorageScanner.FoldedEntries) -> StorageNode {
        let dominantCategory = folded.breakdown.max(by: { $0.value < $1.value })?.key ?? .other
        let aggregate = StorageNode(
            url: dirNode.url,
            name: "\(folded.count) éléments plus petits",
            logicalSizeBytes: folded.logical,
            allocatedSizeBytes: folded.allocated,
            itemCount: folded.count,
            isDirectory: false,
            isAggregate: true,
            modifiedDate: dirNode.modifiedDate,
            category: dominantCategory
        )
        aggregate.datalessLogicalBytes = folded.dataless
        aggregate.categoryBreakdown = folded.breakdown
        aggregate.parent = dirNode
        return aggregate
    }

    /// Collapses in place everything the map can no longer draw, folding it into one
    /// aggregate per directory.
    ///
    /// A whole-disk walk keeps a node for every entry above the scanner floor, which on a
    /// full drive runs past a million: more tiles than the treemap could ever draw, and a
    /// cache that takes longer to decode than the scan that produced it. Sizes, item
    /// counts and category breakdowns are preserved, so only per-entry inspection below
    /// the threshold is lost.
    public func collapseEntries(belowAllocatedBytes threshold: Int64, maxDepth: Int) {
        guard isDirectory, !children.isEmpty else { return }

        guard maxDepth > 0 else {
            var fold = StorageScanner.FoldedEntries()
            for child in children {
                fold.merge(child)
                child.parent = nil
            }
            children = fold.count > 0 ? [Self.makeAggregate(in: self, folded: fold)] : []
            return
        }

        guard threshold > 0 else {
            for child in children {
                child.collapseEntries(belowAllocatedBytes: threshold, maxDepth: maxDepth - 1)
            }
            return
        }

        var retained: [StorageNode] = []
        var fold = StorageScanner.FoldedEntries()

        for child in children {
            // An entry that reported an error is always kept: a map must be able to point
            // at what it could not read, however small it measured.
            let mustKeep = child.allocatedSizeBytes >= threshold || child.accessError != nil
            if mustKeep {
                retained.append(child)
            } else {
                fold.merge(child)
                child.parent = nil
            }
        }

        if fold.count > 0 {
            retained.append(Self.makeAggregate(in: self, folded: fold))
        }
        children = retained

        for child in retained where child.isDirectory {
            child.collapseEntries(belowAllocatedBytes: threshold, maxDepth: maxDepth - 1)
        }
    }

    /// Returns breadcrumb trail from root to self
    public var breadcrumbs: [StorageNode] {
        var trail: [StorageNode] = [self]
        var current = self.parent
        while let node = current {
            trail.insert(node, at: 0)
            current = node.parent
        }
        return trail
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case path
        case name
        case logicalSizeBytes
        case allocatedSizeBytes
        case itemCount
        case isDirectory
        case isPackage
        case isCloudPlaceholder
        case isSymlink
        case isAggregate
        case accessError
        case modifiedDate
        case fileExtension
        case category
        case categoryBreakdown
        case datalessLogicalBytes
        case children
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(logicalSizeBytes, forKey: .logicalSizeBytes)
        try container.encode(allocatedSizeBytes, forKey: .allocatedSizeBytes)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(isPackage, forKey: .isPackage)
        try container.encode(isCloudPlaceholder, forKey: .isCloudPlaceholder)
        try container.encode(isSymlink, forKey: .isSymlink)
        try container.encode(isAggregate, forKey: .isAggregate)
        try container.encodeIfPresent(accessError, forKey: .accessError)
        try container.encode(modifiedDate, forKey: .modifiedDate)
        try container.encode(fileExtension, forKey: .fileExtension)
        try container.encode(category, forKey: .category)
        try container.encode(categoryBreakdown, forKey: .categoryBreakdown)
        try container.encode(datalessLogicalBytes, forKey: .datalessLogicalBytes)
        try container.encode(children, forKey: .children)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(URL.self, forKey: .url)
        self.path = try container.decodeIfPresent(String.self, forKey: .path) ?? url.path
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? url.lastPathComponent
        self.logicalSizeBytes = try container.decode(Int64.self, forKey: .logicalSizeBytes)
        self.allocatedSizeBytes = try container.decode(Int64.self, forKey: .allocatedSizeBytes)
        self.itemCount = try container.decode(Int.self, forKey: .itemCount)
        self.isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        self.isPackage = try container.decode(Bool.self, forKey: .isPackage)
        self.isCloudPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isCloudPlaceholder) ?? false
        self.isSymlink = try container.decodeIfPresent(Bool.self, forKey: .isSymlink) ?? false
        self.isAggregate = try container.decodeIfPresent(Bool.self, forKey: .isAggregate) ?? false
        self.accessError = try container.decodeIfPresent(String.self, forKey: .accessError)
        self.modifiedDate = try container.decodeIfPresent(Date.self, forKey: .modifiedDate) ?? Date()
        self.fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension) ?? url.pathExtension
        self.category = try container.decode(StorageCategory.self, forKey: .category)
        self.categoryBreakdown = try container.decodeIfPresent([StorageCategory: Int64].self, forKey: .categoryBreakdown) ?? [:]
        self.datalessLogicalBytes = try container.decodeIfPresent(Int64.self, forKey: .datalessLogicalBytes) ?? 0
        let decodedChildren = try container.decodeIfPresent([StorageNode].self, forKey: .children) ?? []
        self.children = decodedChildren
        self.parent = nil
        
        // Reconstruct parent references throughout the hierarchy
        for child in decodedChildren {
            child.parent = self
        }
    }
}

/// Represents a persistent snapshot of the Storage Map on disk
public struct StorageMapSnapshot: Codable, Sendable {
    public let targetURL: URL
    public let lastScanDate: Date
    public let maxDepth: Int
    public let rootNode: StorageNode
    /// Completeness of the scan that produced this tree. Persisted so a restored snapshot
    /// cannot present itself as complete when the original scan was not.
    public let report: StorageScanReport?
    
    public init(
        targetURL: URL,
        lastScanDate: Date,
        maxDepth: Int,
        rootNode: StorageNode,
        report: StorageScanReport? = nil
    ) {
        self.targetURL = targetURL
        self.lastScanDate = lastScanDate
        self.maxDepth = maxDepth
        self.rootNode = rootNode
        self.report = report
    }
}
