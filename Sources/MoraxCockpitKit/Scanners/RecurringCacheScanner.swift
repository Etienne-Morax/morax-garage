import Foundation

/// Finds the download and build caches that refill on their own after every install
/// or build — npm, uv, pip, Yarn, Homebrew, SwiftPM, Xcode DerivedData, superseded
/// Playwright browser builds — so they can be cleared in one pass.
///
/// Every target is a cache its tool refills on demand. A cache whose owning
/// application is open is tiered `.rebuildCost` instead of `.safe`, so the one-click
/// preselection (which only picks `.safe`) leaves it alone until the app is quit.
/// The pnpm store stays out on purpose: SafetyGate refuses it, `pnpm store prune` is
/// the only correct way to shrink it.
public struct RecurringCacheScanner: Sendable {
    /// Below this size an entry is noise in the results list.
    public static let minimumReportedBytes: Int64 = 1024 * 1024

    static let xcodeBundleIdentifiers = ["com.apple.dt.Xcode"]

    struct Target: Sendable {
        let relativePath: String
        let displayName: String
        let category: CleanupCategory
        let riskReason: String
        /// Bundle identifiers of the application writing into this cache, if any.
        let ownerBundleIdentifiers: [String]
    }

    static let directTargets: [Target] = [
        Target(relativePath: ".npm/_cacache", displayName: "npm cache",
               category: .devToolCaches,
               riskReason: "npm tarball cache — packages are downloaded again on the next install.",
               ownerBundleIdentifiers: []),
        Target(relativePath: ".npm/_npx", displayName: "npx cache",
               category: .devToolCaches,
               riskReason: "Packages fetched by npx — fetched again on the next npx run.",
               ownerBundleIdentifiers: []),
        Target(relativePath: ".cache/uv", displayName: "uv cache",
               category: .devToolCaches,
               riskReason: "uv wheel and source cache — let running uv commands finish first.",
               ownerBundleIdentifiers: []),
        Target(relativePath: "Library/Caches/pip", displayName: "pip cache",
               category: .devToolCaches,
               riskReason: "pip wheel cache — wheels are downloaded again on the next install.",
               ownerBundleIdentifiers: []),
        Target(relativePath: "Library/Caches/Yarn", displayName: "Yarn cache",
               category: .devToolCaches,
               riskReason: "Yarn package cache — packages are downloaded again on the next install.",
               ownerBundleIdentifiers: []),
        Target(relativePath: "Library/Caches/go-build", displayName: "Go build cache",
               category: .devToolCaches,
               riskReason: "Go compiler cache — rebuilt on the next go build.",
               ownerBundleIdentifiers: []),
        Target(relativePath: "Library/Caches/CocoaPods", displayName: "CocoaPods cache",
               category: .devToolCaches,
               riskReason: "CocoaPods download cache — pods are downloaded again on the next pod install.",
               ownerBundleIdentifiers: []),
        Target(relativePath: "Library/Caches/org.swift.swiftpm", displayName: "SwiftPM cache",
               category: .devToolCaches,
               riskReason: "Swift Package Manager repository cache — dependencies are fetched again on resolve.",
               ownerBundleIdentifiers: xcodeBundleIdentifiers),
        Target(relativePath: "Library/Caches/Homebrew", displayName: "Homebrew cache",
               category: .brewCache,
               riskReason: "Homebrew bottle and source downloads — fetched again when a formula is reinstalled.",
               ownerBundleIdentifiers: [])
    ]

    static let derivedDataPath = "Library/Developer/Xcode/DerivedData"
    static let playwrightPath = "Library/Caches/ms-playwright"

    private let homeDirectory: URL
    private let runningChecker: any RunningAppChecking
    private let trashService = TrashService.shared

    public init(
        homeDirectory: URL? = nil,
        runningChecker: any RunningAppChecking = DefaultRunningAppChecker()
    ) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.runningChecker = runningChecker
    }

    public func scan(progressHandler: (@Sendable (String) -> Void)? = nil) async -> [FileItem] {
        var items: [FileItem] = []

        progressHandler?("Measuring package manager caches...")
        for target in Self.directTargets {
            if Task.isCancelled { return items }
            let url = homeDirectory.appendingPathComponent(target.relativePath)
            if let item = makeItem(url: url, name: target.displayName, category: target.category,
                                   riskReason: target.riskReason, owners: target.ownerBundleIdentifiers) {
                items.append(item)
            }
        }

        progressHandler?("Measuring Xcode DerivedData...")
        items.append(contentsOf: derivedDataItems())

        progressHandler?("Looking for superseded Playwright browsers...")
        items.append(contentsOf: playwrightItems())

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Per-project DerivedData folders; `ModuleCache.noindex` is shared by every project.
    private func derivedDataItems() -> [FileItem] {
        let root = homeDirectory.appendingPathComponent(Self.derivedDataPath)
        return childDirectories(of: root)
            .filter { $0.lastPathComponent != "ModuleCache.noindex" }
            .compactMap { url in
                makeItem(url: url, name: "DerivedData/\(url.lastPathComponent)",
                         category: .devXcodeDerivedData,
                         riskReason: "Xcode build products — rebuilt on the next build.",
                         owners: Self.xcodeBundleIdentifiers)
            }
    }

    /// Older builds of each Playwright browser; the newest build of every browser is kept.
    private func playwrightItems() -> [FileItem] {
        let root = homeDirectory.appendingPathComponent(Self.playwrightPath)
        let children = childDirectories(of: root)
        let superseded = Set(Self.supersededPlaywrightBuilds(children.map(\.lastPathComponent)))
        return children
            .filter { superseded.contains($0.lastPathComponent) }
            .compactMap { url in
                makeItem(url: url, name: "Playwright/\(url.lastPathComponent)",
                         category: .devToolCaches,
                         riskReason: "Superseded Playwright browser build — a project still pinned to it downloads it again with 'npx playwright install'.",
                         owners: [])
            }
    }

    /// Names of Playwright build folders (`chromium-1223`) older than the newest build
    /// of the same browser. Names without a numeric build suffix are never returned.
    static func supersededPlaywrightBuilds(_ names: [String]) -> [String] {
        let parsed: [(name: String, family: String, build: Int)] = names.compactMap { name in
            guard let dash = name.lastIndex(of: "-"),
                  let build = Int(name[name.index(after: dash)...]) else { return nil }
            return (name, String(name[..<dash]), build)
        }
        let newestByFamily = Dictionary(grouping: parsed, by: \.family)
            .mapValues { builds in builds.map(\.build).max() ?? 0 }
        return parsed
            .filter { $0.build < (newestByFamily[$0.family] ?? 0) }
            .map(\.name)
            .sorted()
    }

    private func childDirectories(of root: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    private func makeItem(
        url: URL,
        name: String,
        category: CleanupCategory,
        riskReason: String,
        owners: [String]
    ) -> FileItem? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = trashService.calculateSize(url: url)
        guard size >= Self.minimumReportedBytes else { return nil }

        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let isOwnerRunning = !owners.isEmpty && runningChecker.isRunning(bundleIdentifiers: owners, names: [])

        return FileItem(
            url: url,
            name: name,
            sizeBytes: size,
            modifiedDate: modDate,
            category: category,
            riskTier: isOwnerRunning ? .rebuildCost : .safe,
            riskReason: isOwnerRunning
                ? "Xcode is open and may be writing here — quit it, then clear this cache."
                : riskReason,
            isRecent: false,
            isSelected: false,
            details: "Recurring cache: \(url.path)"
        )
    }
}
