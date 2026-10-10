import Foundation
import Testing
@testable import MoraxCockpitKit

private struct SampleItem: Codable, Sendable, Equatable {
    let name: String
    let sizeBytes: Int64
}

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CachedScanStoreTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("CachedScanStore")
struct CachedScanStoreTests {
    @Test("Saved items survive a round trip through disk")
    func savedItemsRoundTrip() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "sample.plist", directory: directory)
        let items = [SampleItem(name: "Xcode", sizeBytes: 12_000), SampleItem(name: "Mail", sizeBytes: 340)]
        let scanDate = Date(timeIntervalSince1970: 1_700_000_000)

        store.saveSynchronously(items: items, scanDate: scanDate)

        let reloaded = try #require(CachedScanStore<SampleItem>(fileName: "sample.plist", directory: directory).load())
        #expect(reloaded.items == items)
        #expect(reloaded.scanDate == scanDate)
    }

    @Test("Loading an absent cache returns nil")
    func loadingAbsentCacheReturnsNil() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "missing.plist", directory: directory)
        #expect(store.load() == nil)
    }

    @Test("A scan is fresh until its time to live elapses")
    func freshnessFollowsTimeToLive() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "ttl.plist", timeToLive: 60, directory: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(store.isFresh(now.addingTimeInterval(-59), now: now))
        #expect(!store.isFresh(now.addingTimeInterval(-61), now: now))
        #expect(!store.isFresh(nil, now: now))
    }

    @Test("A scan dated in the future is treated as stale")
    func futureScanDateIsStale() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "future.plist", timeToLive: 60, directory: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(!store.isFresh(now.addingTimeInterval(120), now: now))
    }

    @Test("Clearing removes the persisted cache")
    func clearingRemovesCache() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "clear.plist", directory: directory)
        store.saveSynchronously(items: [SampleItem(name: "Notes", sizeBytes: 1)], scanDate: Date())
        #expect(store.load() != nil)

        store.clear()
        #expect(store.load() == nil)
    }

    @Test("Multi-key read and write maintains distinct snapshots per key")
    func multiKeyReadWrite() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "multikey.plist", directory: directory)
        let resolveItems = [SampleItem(name: "ResolveCache", sizeBytes: 50_000)]
        let photoItems = [SampleItem(name: "LightroomPreview", sizeBytes: 120_000)]
        let date1 = Date(timeIntervalSince1970: 1_700_000_100)
        let date2 = Date(timeIntervalSince1970: 1_700_000_200)

        store.saveSynchronously(items: resolveItems, scanDate: date1, for: "Resolve")
        store.saveSynchronously(items: photoItems, scanDate: date2, for: "Photo")

        let reloaded = CachedScanStore<SampleItem>(fileName: "multikey.plist", directory: directory)
        let all = reloaded.loadAll()
        #expect(all.count == 2)
        #expect(all["Resolve"]?.items == resolveItems)
        #expect(all["Resolve"]?.scanDate == date1)
        #expect(all["Photo"]?.items == photoItems)
        #expect(all["Photo"]?.scanDate == date2)

        #expect(reloaded.load(for: "Resolve")?.items == resolveItems)
        #expect(reloaded.load(for: "Photo")?.items == photoItems)
        #expect(reloaded.load(for: "Dev") == nil)

        // Clear only one key
        reloaded.clear(for: "Resolve")
        #expect(reloaded.load(for: "Resolve") == nil)
        #expect(reloaded.load(for: "Photo")?.items == photoItems)
    }

    @Test("Migrates legacy v1 single snapshot file silently to v2")
    func migratesV1SingleSnapshot() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("legacy_v1.plist")
        let legacySnapshot = CachedScanStore<SampleItem>.Snapshot(
            scanDate: Date(timeIntervalSince1970: 1_700_000_000),
            items: [SampleItem(name: "LegacyItem", sizeBytes: 999)]
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(legacySnapshot)
        try data.write(to: fileURL)

        let store = CachedScanStore<SampleItem>(fileName: "legacy_v1.plist", directory: directory)
        let loaded = try #require(store.load())
        #expect(loaded.items == legacySnapshot.items)
        #expect(loaded.scanDate == legacySnapshot.scanDate)

        // Verify the file was rewritten to v2 dictionary format
        let all = store.loadAll()
        #expect(all[CachedScanStore<SampleItem>.defaultKey]?.items == legacySnapshot.items)
    }

    @Test("Migrates legacy CleanupSnapshot file format silently to v2")
    func migratesLegacyCleanupSnapshot() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        struct MockLegacyCleanupSnapshot: Codable {
            let scannerRawValue: String
            let lastScanDate: Date
            let items: [SampleItem]
        }

        let fileURL = directory.appendingPathComponent("cleanup_cache.plist")
        let legacy = MockLegacyCleanupSnapshot(
            scannerRawValue: "DaVinci Resolve Caches",
            lastScanDate: Date(timeIntervalSince1970: 1_700_000_000),
            items: [SampleItem(name: "Render.mov", sizeBytes: 40_000)]
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(legacy)
        try data.write(to: fileURL)

        let store = CachedScanStore<SampleItem>(fileName: "cleanup_cache.plist", directory: directory)
        let all = store.loadAll()
        #expect(all["DaVinci Resolve Caches"]?.items == legacy.items)
        #expect(all["DaVinci Resolve Caches"]?.scanDate == legacy.lastScanDate)
    }

    @Test("Keyed freshness checks validate individual key TTL")
    func keyedFreshnessFollowsTTL() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CachedScanStore<SampleItem>(fileName: "keyed_ttl.plist", timeToLive: 60, directory: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.saveSynchronously(items: [], scanDate: now.addingTimeInterval(-30), for: "FreshKey")
        store.saveSynchronously(items: [], scanDate: now.addingTimeInterval(-100), for: "StaleKey")

        #expect(store.isFresh(for: "FreshKey", now: now))
        #expect(!store.isFresh(for: "StaleKey", now: now))
        #expect(!store.isFresh(for: "MissingKey", now: now))
    }
}
