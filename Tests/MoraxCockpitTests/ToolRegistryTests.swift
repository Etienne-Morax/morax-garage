import XCTest
import Foundation
@testable import MoraxCockpitKit

final class ToolRegistryTests: XCTestCase {
    
    func testDetectAllToolsReturnsValidList() async {
        let registry = ToolRegistry()
        let tools = await registry.discoverAll()
        
        XCTAssertEqual(tools.count, 6)
        let ids = tools.map { $0.id }
        XCTAssertTrue(ids.contains("brew"))
        XCTAssertTrue(ids.contains("macmon"))
        XCTAssertTrue(ids.contains("mole"))
        XCTAssertTrue(ids.contains("pearcleaner"))
        XCTAssertTrue(ids.contains("stats"))
        XCTAssertTrue(ids.contains("higgsfield"))
    }
    
    func testBrewPrefixDetection() {
        let registry = ToolRegistry()
        let prefix = registry.detectBrewPrefix()
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            XCTAssertEqual(prefix, "/opt/homebrew")
        }
    }

    func testResolveBinaryPathFindsManagedUserTool() throws {
        let managedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("bin")
            .path
        let registry = ToolRegistry(managedToolsDirectory: managedDirectory)
        let managedMacmon = (managedDirectory as NSString).appendingPathComponent("macmon")
        let fileManager = FileManager.default

        try fileManager.createDirectory(atPath: managedDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(toFile: managedMacmon, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedMacmon)
        defer { try? fileManager.removeItem(atPath: (managedDirectory as NSString).deletingLastPathComponent) }

        XCTAssertEqual(registry.resolveBinaryPath(name: "macmon"), managedMacmon)
    }
}
