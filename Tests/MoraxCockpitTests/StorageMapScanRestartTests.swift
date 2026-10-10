import XCTest
import Foundation
@testable import MoraxCockpitKit

@MainActor
final class StorageMapScanRestartTests: XCTestCase {
    private static let fixtureDirectoryCount = 1_500
    private static let pollInterval: UInt64 = 2_000_000
    private static let scanTimeout: TimeInterval = 60

    private nonisolated(unsafe) var sandboxURL: URL!

    override func setUpWithError() throws {
        sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageMapScanRestartTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandboxURL)
    }

    private func makeFixture(named name: String) throws -> URL {
        let root = sandboxURL.appendingPathComponent(name)
        for index in 0..<Self.fixtureDirectoryCount {
            let dir = root.appendingPathComponent("dir-\(index)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appendingPathComponent("file.txt"))
        }
        return root
    }

    func testRestartingAScanKeepsTheNewScanVisibleUntilItFinishes() async throws {
        // Arrange
        let firstTarget = try makeFixture(named: "first")
        let secondTarget = try makeFixture(named: "second")
        let service = StorageMapStateService(customCacheDirectory: sandboxURL.appendingPathComponent("cache"))

        // Act: the second scan replaces the first while it is still walking.
        service.startScan(url: firstTarget)
        service.startScan(url: secondTarget)

        var sawEmptyStateMidScan = false
        let deadline = Date().addingTimeInterval(Self.scanTimeout)
        while service.rootNode == nil && Date() < deadline {
            if !service.isScanning { sawEmptyStateMidScan = true }
            try await Task.sleep(nanoseconds: Self.pollInterval)
        }

        // Assert
        XCTAssertFalse(sawEmptyStateMidScan, "a cancelled scan must not end the scan that replaced it")
        XCTAssertFalse(service.isScanning)
        XCTAssertEqual(service.rootNode?.url.lastPathComponent, secondTarget.lastPathComponent)
        XCTAssertEqual(service.targetURL, secondTarget)
    }

    func testCancelledScanNeverPublishesItsTree() async throws {
        // Arrange
        let target = try makeFixture(named: "cancelled")
        let service = StorageMapStateService(customCacheDirectory: sandboxURL.appendingPathComponent("cache"))

        // Act
        service.startScan(url: target)
        service.cancelScan()
        try await Task.sleep(nanoseconds: 500_000_000)

        // Assert
        XCTAssertFalse(service.isScanning)
        XCTAssertNil(service.rootNode)
        XCTAssertNil(service.lastErrorMessage)
    }
}
