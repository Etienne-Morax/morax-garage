import XCTest
import Foundation
@testable import MoraxCockpitKit

final class AppCacheScannerTests: XCTestCase {
    private let payloadBytes = 2 * 1024 * 1024

    private func writePayload(at directory: URL, file: String = "blob.bin") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(count: payloadBytes).write(to: directory.appendingPathComponent(file))
    }

    func testFindsWhatsAppAndSpotifyCachesWithTheirTiers() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "app_cache_test") { library in
            let whatsAppCaches = library.appendingPathComponent("Containers/net.whatsapp.WhatsApp/Data/Library/Caches")
            let whatsAppMedia = library.appendingPathComponent("Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media")
            let spotifyStreaming = library.appendingPathComponent("Caches/com.spotify.client/Data")
            let spotifyOffline = library.appendingPathComponent("Application Support/Spotify/PersistentCache/Storage")
            try writePayload(at: whatsAppCaches)
            try writePayload(at: whatsAppMedia)
            try writePayload(at: spotifyStreaming)
            try writePayload(at: spotifyOffline)

            let items = await AppCacheScanner(libraryDirectory: library, runningChecker: NeverRunningAppChecker()).scan()
            let byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.url.standardizedFileURL.path, $0) })

            XCTAssertEqual(byPath[whatsAppCaches.standardizedFileURL.path]?.riskTier, .safe)
            XCTAssertEqual(byPath[whatsAppCaches.standardizedFileURL.path]?.category, .appWhatsAppCache)
            XCTAssertEqual(byPath[whatsAppMedia.standardizedFileURL.path]?.riskTier, .destructive)
            XCTAssertEqual(byPath[whatsAppMedia.standardizedFileURL.path]?.category, .appWhatsAppMedia)
            XCTAssertEqual(byPath[spotifyStreaming.standardizedFileURL.path]?.riskTier, .safe)
            XCTAssertEqual(byPath[spotifyOffline.standardizedFileURL.path]?.riskTier, .rebuildCost)
            XCTAssertTrue(items.allSatisfy { !$0.isSelected }, "Nothing may be pre-selected")
        }
    }

    func testNeverOffersSessionOrChatData() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "app_cache_userdata") { library in
            let slack = library.appendingPathComponent("Application Support/Slack")
            try writePayload(at: slack.appendingPathComponent("Cache"))
            try writePayload(at: slack.appendingPathComponent("Local Storage"))
            try writePayload(at: slack.appendingPathComponent("IndexedDB"))
            try writePayload(at: library.appendingPathComponent("Group Containers/group.net.whatsapp.WhatsApp.shared"),
                             file: "ChatStorage.sqlite")

            let items = await AppCacheScanner(libraryDirectory: library, runningChecker: NeverRunningAppChecker()).scan()
            let names = items.map(\.name)

            XCTAssertEqual(names, ["Slack/Cache"])
            for item in items {
                XCTAssertFalse(item.path.contains("Local Storage"))
                XCTAssertFalse(item.path.contains("IndexedDB"))
                XCTAssertFalse(item.path.contains("ChatStorage"))
            }
        }
    }

    func testCachesAreBlockedWhileTheAppRuns() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "app_cache_running") { library in
            try writePayload(at: library.appendingPathComponent("Caches/com.spotify.client/Data"))

            let items = await AppCacheScanner(libraryDirectory: library, runningChecker: AlwaysRunningChecker()).scan()

            XCTAssertFalse(items.isEmpty)
            for item in items {
                XCTAssertEqual(item.riskTier, .blocked)
                XCTAssertFalse(item.isSelected)
            }
        }
    }

    func testSkipsEntriesBelowTheReportingThreshold() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "app_cache_small") { library in
            let gpuCache = library.appendingPathComponent("Application Support/discord/GPUCache")
            try FileManager.default.createDirectory(at: gpuCache, withIntermediateDirectories: true)
            try Data(count: 4096).write(to: gpuCache.appendingPathComponent("data_0"))

            let items = await AppCacheScanner(libraryDirectory: library, runningChecker: NeverRunningAppChecker()).scan()

            XCTAssertTrue(items.isEmpty)
        }
    }

    func testFindsTelegramMediaForEveryAccount() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "app_cache_telegram") { library in
            let stable = library.appendingPathComponent("Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable")
            try writePayload(at: stable.appendingPathComponent("account-111/postbox/media"))
            try writePayload(at: stable.appendingPathComponent("account-222/postbox/media"))
            try writePayload(at: stable.appendingPathComponent("account-111/postbox/db"))

            let items = await AppCacheScanner(libraryDirectory: library, runningChecker: NeverRunningAppChecker()).scan()

            XCTAssertEqual(items.count, 2)
            XCTAssertTrue(items.allSatisfy { $0.path.hasSuffix("postbox/media") && $0.riskTier == .rebuildCost })
        }
    }

    func testSafetyGateRefusesChatDatabasesAndContainers() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let refused = [
            "\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared",
            "\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite",
            "\(home)/Library/Containers/net.whatsapp.WhatsApp",
            "\(home)/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable/account-1/postbox/db",
            "\(home)/Library/Application Support/Signal/sql"
        ]
        for path in refused {
            XCTAssertThrowsError(try SafetyGate.validateForTrash(path: path), "\(path) must be refused")
        }
        let allowed = "\(home)/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable/account-1/postbox/media"
        XCTAssertNoThrow(try SafetyGate.checkMessagingAppSafety(canonicalPath: allowed))
    }

    func testSystemScannerLeavesAppOwnedCachesToTheAppScanner() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "app_cache_dedup") { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches.appendingPathComponent("com.spotify.client"), withIntermediateDirectories: true)
            try Data(count: 12 * 1024 * 1024).write(to: caches.appendingPathComponent("com.spotify.client/blob"))

            let items = await SystemCacheScanner().scan(
                customCachesDirectory: caches,
                customLogsDirectory: root.appendingPathComponent("Logs")
            )

            XCTAssertFalse(items.contains { $0.name == "com.spotify.client" })
        }
    }
}

private struct AlwaysRunningChecker: RunningAppChecking {
    func isRunning(bundleIdentifiers: [String], names: [String]) -> Bool { true }
}
