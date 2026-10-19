import XCTest
import Foundation
@testable import MoraxCockpitKit

final class RecurringCacheScannerTests: XCTestCase {
    private let payloadBytes = 2 * 1024 * 1024

    private func writePayload(at directory: URL, bytes: Int? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(count: bytes ?? payloadBytes).write(to: directory.appendingPathComponent("blob.bin"))
    }

    func testFindsPackageCachesAsSafeAndUnselected() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "recurring_cache") { home in
            let npm = home.appendingPathComponent(".npm/_cacache")
            let uv = home.appendingPathComponent(".cache/uv")
            let brew = home.appendingPathComponent("Library/Caches/Homebrew")
            let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-abc")
            try writePayload(at: npm)
            try writePayload(at: uv)
            try writePayload(at: brew)
            try writePayload(at: derived)
            try writePayload(at: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/ModuleCache.noindex"))

            let items = await RecurringCacheScanner(homeDirectory: home, runningChecker: NeverRunningAppChecker()).scan()
            let paths = Set(items.map(\.url.standardizedFileURL.path))

            XCTAssertEqual(paths, Set([npm, uv, brew, derived].map(\.standardizedFileURL.path)))
            XCTAssertTrue(items.allSatisfy { $0.riskTier == .safe })
            XCTAssertTrue(items.allSatisfy { !$0.isSelected }, "The scanner itself never preselects")
            XCTAssertEqual(items.first { $0.url.standardizedFileURL == brew.standardizedFileURL }?.category, .brewCache)
        }
    }

    func testSkipsMissingAndTinyCaches() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "recurring_tiny") { home in
            try writePayload(at: home.appendingPathComponent("Library/Caches/pip"), bytes: 1024)

            let items = await RecurringCacheScanner(homeDirectory: home, runningChecker: NeverRunningAppChecker()).scan()

            XCTAssertTrue(items.isEmpty)
        }
    }

    func testXcodeCachesAreNotSafeWhileXcodeRuns() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "recurring_xcode") { home in
            try writePayload(at: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-abc"))
            try writePayload(at: home.appendingPathComponent("Library/Caches/org.swift.swiftpm"))
            try writePayload(at: home.appendingPathComponent(".npm/_cacache"))

            let items = await RecurringCacheScanner(homeDirectory: home, runningChecker: XcodeRunningChecker()).scan()
            let tiers = Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0.riskTier) })

            XCTAssertEqual(tiers["App-abc"], .rebuildCost)
            XCTAssertEqual(tiers["org.swift.swiftpm"], .rebuildCost)
            XCTAssertEqual(tiers["_cacache"], .safe)
        }
    }

    func testOffersOnlySupersededPlaywrightBuilds() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "recurring_playwright") { home in
            let root = home.appendingPathComponent("Library/Caches/ms-playwright")
            for name in ["chromium-1223", "chromium-1234", "chromium_headless_shell-1223", "chromium_headless_shell-1234", "firefox-1490"] {
                try writePayload(at: root.appendingPathComponent(name))
            }

            let items = await RecurringCacheScanner(homeDirectory: home, runningChecker: NeverRunningAppChecker()).scan()

            XCTAssertEqual(Set(items.map(\.url.lastPathComponent)), ["chromium-1223", "chromium_headless_shell-1223"])
        }
    }

    func testSupersededPlaywrightBuildsIgnoresUnversionedNames() {
        let names = ["chromium-1223", "chromium-1234", "webkit-2100", ".links", "ffmpeg", "firefox-beta"]

        XCTAssertEqual(RecurringCacheScanner.supersededPlaywrightBuilds(names), ["chromium-1223"])
    }

    func testEveryTargetPassesSafetyGate() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = RecurringCacheScanner.directTargets.map(\.relativePath)
            + ["\(RecurringCacheScanner.derivedDataPath)/App-abc", "\(RecurringCacheScanner.playwrightPath)/chromium-1223"]

        for path in paths {
            XCTAssertNoThrow(try SafetyGate.validateForTrash(url: home.appendingPathComponent(path)), path)
        }
    }
}

private struct XcodeRunningChecker: RunningAppChecking {
    func isRunning(bundleIdentifiers: [String], names: [String]) -> Bool {
        bundleIdentifiers.contains("com.apple.dt.Xcode")
    }
}
