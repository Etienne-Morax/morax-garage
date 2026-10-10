import Foundation

/// Finds the caches of everyday desktop applications — WhatsApp, Spotify, Telegram,
/// Slack, Discord, Notion, VS Code… — that quietly grow to several gigabytes.
///
/// Only directories each application rebuilds on its own are offered. Anything that
/// holds conversations, logins or offline content is either tiered above `.safe` or
/// left out entirely, and every cache is refused while its application is open.
public struct AppCacheScanner: Sendable {
    /// Below this size an entry is noise in the results list.
    public static let minimumReportedBytes: Int64 = 1024 * 1024

    /// `~/Library/Caches` children owned by this scanner, so the generic system cache
    /// scanner does not report the same bytes a second time.
    public static let ownedCacheDirectoryNames: [String] = [
        "com.spotify.client", "WhatsApp", "net.whatsapp.WhatsApp"
    ]

    /// Chromium/Electron sub-directories that only hold regenerable network, script
    /// and GPU caches. Cookies, Local Storage and IndexedDB are deliberately absent:
    /// they carry the signed-in session and offline data.
    static let electronCacheSubpaths: [String] = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "GrShaderCache", "ShaderCache",
        "Service Worker/CacheStorage", "Service Worker/ScriptCache"
    ]

    private let libraryDirectory: URL
    private let runningChecker: any RunningAppChecking

    public init(
        libraryDirectory: URL? = nil,
        runningChecker: any RunningAppChecking = DefaultRunningAppChecker()
    ) {
        self.libraryDirectory = libraryDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        self.runningChecker = runningChecker
    }

    public func scan(progressHandler: (@Sendable (String) -> Void)? = nil) async -> [FileItem] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var items: [FileItem] = []

        for profile in AppCacheProfile.all(library: libraryDirectory) {
            if Task.isCancelled { break }
            progressHandler?("Scanning \(profile.appName) caches...")
            let isRunning = runningChecker.isRunning(
                bundleIdentifiers: profile.bundleIdentifiers,
                names: profile.processNames
            )
            items.append(contentsOf: profile.targets.compactMap {
                makeItem(for: $0, profile: profile, isRunning: isRunning, cutoffDate: cutoffDate)
            })
        }
        return items
    }

    private func makeItem(
        for target: AppCacheTarget,
        profile: AppCacheProfile,
        isRunning: Bool,
        cutoffDate: Date
    ) -> FileItem? {
        guard FileManager.default.fileExists(atPath: target.url.path) else { return nil }
        let size = TrashService.shared.calculateSize(url: target.url)
        guard size >= Self.minimumReportedBytes else { return nil }

        let modDate = (try? target.url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        let tier: RiskTier = isRunning ? .blocked : target.tier
        let reason = isRunning
            ? "\(profile.appName) is running — quit it before clearing this cache."
            : target.reason

        return FileItem(
            url: target.url,
            name: "\(profile.appName)/\(target.label)",
            sizeBytes: size,
            modifiedDate: modDate,
            category: target.category,
            riskTier: tier,
            riskReason: reason,
            isRecent: modDate > cutoffDate,
            isSelected: false,
            details: target.details
        )
    }
}

// MARK: - Catalogue

struct AppCacheTarget: Sendable {
    let url: URL
    let label: String
    let category: CleanupCategory
    let tier: RiskTier
    let reason: String
    let details: String
}

struct AppCacheProfile: Sendable {
    let appName: String
    let bundleIdentifiers: [String]
    let processNames: [String]
    let targets: [AppCacheTarget]

    /// Every known application, with paths resolved against `library`.
    static func all(library: URL) -> [AppCacheProfile] {
        let caches = library.appendingPathComponent("Caches")
        let appSupport = library.appendingPathComponent("Application Support")
        let containers = library.appendingPathComponent("Containers")
        let groups = library.appendingPathComponent("Group Containers")

        return [
            whatsApp(caches: caches, appSupport: appSupport, containers: containers, groups: groups),
            spotify(caches: caches, appSupport: appSupport),
            telegram(appSupport: appSupport, groups: groups),
            electron("Slack", ids: ["com.tinyspeck.slackmacgap"], names: ["slack"], category: .appMessagingCache, roots: [
                appSupport.appendingPathComponent("Slack"),
                containers.appendingPathComponent("com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack")
            ]),
            electron("Discord", ids: ["com.hnc.Discord"], names: ["discord"], category: .appMessagingCache, roots: [
                appSupport.appendingPathComponent("discord")
            ]),
            microsoftTeams(appSupport: appSupport, containers: containers),
            electron("Signal", ids: ["org.whispersystems.signal-desktop"], names: ["signal"], category: .appMessagingCache, roots: [
                appSupport.appendingPathComponent("Signal")
            ]),
            sandboxCaches("Messenger", ids: ["com.facebook.archon"], names: ["messenger"], category: .appMessagingCache,
                          container: containers.appendingPathComponent("com.facebook.archon")),
            notion(appSupport: appSupport),
            codeEditor("VS Code", ids: ["com.microsoft.VSCode"], root: appSupport.appendingPathComponent("Code")),
            codeEditor("Cursor", ids: ["com.todesktop.230313mzl4w4u92"], root: appSupport.appendingPathComponent("Cursor")),
            electron("Figma", ids: ["com.figma.Desktop"], names: ["figma"], category: .appDesktopCache, roots: [
                appSupport.appendingPathComponent("Figma")
            ]),
            // Matched by bundle identifier only: "claude" as a name would also match
            // unrelated processes such as Claude Code helpers.
            electron("Claude", ids: ["com.anthropic.claudefordesktop"], names: [], category: .appDesktopCache, roots: [
                appSupport.appendingPathComponent("Claude")
            ])
        ]
    }

    // MARK: Builders

    static func electron(
        _ appName: String,
        ids: [String],
        names: [String],
        category: CleanupCategory,
        roots: [URL]
    ) -> AppCacheProfile {
        AppCacheProfile(
            appName: appName,
            bundleIdentifiers: ids,
            processNames: names,
            targets: roots.flatMap { electronTargets(appName: appName, root: $0, category: category) }
        )
    }

    static func electronTargets(
        appName: String,
        root: URL,
        category: CleanupCategory,
        labelPrefix: String = ""
    ) -> [AppCacheTarget] {
        AppCacheScanner.electronCacheSubpaths.map { subpath in
            AppCacheTarget(
                url: root.appendingPathComponent(subpath),
                label: labelPrefix + subpath,
                category: category,
                tier: .safe,
                reason: "\(appName) web content cache — rebuilt automatically, you stay signed in.",
                details: "\(appName) \(subpath) (network, script or GPU cache)"
            )
        }
    }

    static func sandboxCaches(
        _ appName: String,
        ids: [String],
        names: [String],
        category: CleanupCategory,
        container: URL
    ) -> AppCacheProfile {
        AppCacheProfile(appName: appName, bundleIdentifiers: ids, processNames: names, targets: [
            AppCacheTarget(
                url: container.appendingPathComponent("Data/Library/Caches"),
                label: "Caches",
                category: category,
                tier: .safe,
                reason: "\(appName) sandbox cache — rebuilt automatically.",
                details: "\(appName) sandboxed application cache"
            )
        ])
    }

    static func whatsApp(caches: URL, appSupport: URL, containers: URL, groups: URL) -> AppCacheProfile {
        let container = containers.appendingPathComponent("net.whatsapp.WhatsApp")
        let shared = groups.appendingPathComponent("group.net.whatsapp.WhatsApp.shared")
        let safeReason = "WhatsApp cache — rebuilt automatically, chats are untouched."

        var targets: [AppCacheTarget] = [
            container.appendingPathComponent("Data/Library/Caches"),
            container.appendingPathComponent("Data/tmp"),
            shared.appendingPathComponent("Library/Caches"),
            caches.appendingPathComponent("WhatsApp"),
            caches.appendingPathComponent("net.whatsapp.WhatsApp")
        ].map {
            AppCacheTarget(url: $0, label: $0.lastPathComponent, category: .appWhatsAppCache, tier: .safe,
                           reason: safeReason, details: "WhatsApp application cache")
        }
        // Legacy Electron build of WhatsApp Desktop.
        targets += electronTargets(appName: "WhatsApp", root: appSupport.appendingPathComponent("WhatsApp"),
                                   category: .appWhatsAppCache)
        // Received photos, videos, voice notes and documents. Clearing them frees the
        // most space, but WhatsApp only keeps media on its servers for a short time.
        targets.append(AppCacheTarget(
            url: shared.appendingPathComponent("Message/Media"),
            label: "Received media",
            category: .appWhatsAppMedia,
            tier: .destructive,
            reason: "Photos, videos and documents received in chats — older media can no longer be downloaded again.",
            details: "WhatsApp received media (chat history itself is kept)"
        ))
        return AppCacheProfile(appName: "WhatsApp", bundleIdentifiers: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"],
                               processNames: ["whatsapp"], targets: targets)
    }

    static func spotify(caches: URL, appSupport: URL) -> AppCacheProfile {
        let clientCaches = caches.appendingPathComponent("com.spotify.client")
        var targets: [AppCacheTarget] = [
            AppCacheTarget(
                url: clientCaches.appendingPathComponent("Data"),
                label: "Streaming cache",
                category: .appSpotifyCache,
                tier: .safe,
                reason: "Spotify streaming cache — tracks are streamed again on next play.",
                details: "Spotify audio streaming cache"
            )
        ]
        targets += electronTargets(appName: "Spotify", root: clientCaches.appendingPathComponent("Browser"),
                                   category: .appSpotifyCache)
        targets.append(AppCacheTarget(
            url: appSupport.appendingPathComponent("Spotify/PersistentCache/Storage"),
            label: "Offline storage",
            category: .appSpotifyCache,
            tier: .rebuildCost,
            reason: "Includes songs and podcasts downloaded for offline listening — they must be downloaded again.",
            details: "Spotify persistent cache and offline downloads"
        ))
        return AppCacheProfile(appName: "Spotify", bundleIdentifiers: ["com.spotify.client"],
                               processNames: ["spotify"], targets: targets)
    }

    static func telegram(appSupport: URL, groups: URL) -> AppCacheProfile {
        let reason = "Telegram media cache — photos and videos stay in the Telegram cloud and download again when opened."
        let groupRoot = groups.appendingPathComponent("6N38VWS5BX.ru.keepcoder.Telegram")
        var targets = ["stable", "appstore"].flatMap { channel in
            accountDirectories(in: groupRoot.appendingPathComponent(channel)).map { account in
                AppCacheTarget(
                    url: account.appendingPathComponent("postbox/media"),
                    label: "\(account.lastPathComponent)/media",
                    category: .appMessagingCache,
                    tier: .rebuildCost,
                    reason: reason,
                    details: "Telegram downloaded media cache"
                )
            }
        }
        targets.append(AppCacheTarget(
            url: appSupport.appendingPathComponent("Telegram Desktop/tdata/user_data"),
            label: "user_data",
            category: .appMessagingCache,
            tier: .rebuildCost,
            reason: reason,
            details: "Telegram Desktop media cache"
        ))
        return AppCacheProfile(appName: "Telegram", bundleIdentifiers: ["ru.keepcoder.Telegram", "org.telegram.desktop"],
                               processNames: ["telegram"], targets: targets)
    }

    static func microsoftTeams(appSupport: URL, containers: URL) -> AppCacheProfile {
        var targets = sandboxCaches("Microsoft Teams", ids: [], names: [], category: .appMessagingCache,
                                    container: containers.appendingPathComponent("com.microsoft.teams2")).targets
        targets += electronTargets(appName: "Microsoft Teams", root: appSupport.appendingPathComponent("Microsoft/Teams"),
                                   category: .appMessagingCache)
        return AppCacheProfile(appName: "Microsoft Teams", bundleIdentifiers: ["com.microsoft.teams"],
                               processNames: ["microsoft teams"], targets: targets)
    }

    static func notion(appSupport: URL) -> AppCacheProfile {
        let root = appSupport.appendingPathComponent("Notion")
        let targets = electronTargets(appName: "Notion", root: root, category: .appDesktopCache)
            + electronTargets(appName: "Notion", root: root.appendingPathComponent("Partitions/notion"),
                              category: .appDesktopCache, labelPrefix: "Workspace/")
        return AppCacheProfile(appName: "Notion", bundleIdentifiers: ["notion.id"], processNames: ["notion"], targets: targets)
    }

    static func codeEditor(_ appName: String, ids: [String], root: URL) -> AppCacheProfile {
        var targets = electronTargets(appName: appName, root: root, category: .appDesktopCache)
        targets += [
            ("CachedData", "Compiled JavaScript cache — rebuilt on next launch."),
            ("CachedExtensionVSIXs", "Copies of downloaded extension packages — installed extensions keep working.")
        ].map { subpath, reason in
            AppCacheTarget(url: root.appendingPathComponent(subpath), label: subpath, category: .appDesktopCache,
                           tier: .safe, reason: "\(appName): \(reason)", details: "\(appName) \(subpath)")
        }
        return AppCacheProfile(appName: appName, bundleIdentifiers: ids, processNames: [], targets: targets)
    }

    private static func accountDirectories(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix("account-") }
    }
}
