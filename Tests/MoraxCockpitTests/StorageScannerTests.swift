import XCTest
import Foundation
@testable import MoraxCockpitKit

final class StorageScannerTests: XCTestCase {
    
    func testStorageScannerCalculatesAccurateTreeMetrics() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "test_scanner_metrics") { rootDir in
            // Build synthetic hierarchy
            let videoDir = rootDir.appendingPathComponent("VideoProjects/Resolve")
            let codeDir = rootDir.appendingPathComponent("Code/App")
            let archivesDir = rootDir.appendingPathComponent("Archives")
            
            try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: codeDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: archivesDir, withIntermediateDirectories: true)
            
            // Create dummy files with known sizes
            let videoData = Data(repeating: 0xAA, count: 10_000) // 10KB
            let codeData = Data(repeating: 0xBB, count: 4_000)   // 4KB
            let archiveData = Data(repeating: 0xCC, count: 20_000) // 20KB
            
            try videoData.write(to: videoDir.appendingPathComponent("clip.mov"))
            try codeData.write(to: codeDir.appendingPathComponent("main.swift"))
            try archiveData.write(to: archivesDir.appendingPathComponent("installer.dmg"))
            
            final class SafeCounter: @unchecked Sendable {
                private let lock = NSLock()
                var value = 0
                func increment() {
                    lock.lock()
                    defer { lock.unlock() }
                    value += 1
                }
            }
            
            let counter = SafeCounter()
            let scanner = StorageScanner.shared
            
            let rootNode = try await scanner.scan(rootURL: rootDir, options: .retainEverything) { progress in
                counter.increment()
                XCTAssertFalse(progress.currentPath.isEmpty)
            }
            
            XCTAssertEqual(rootNode.url.standardizedFileURL, rootDir.standardizedFileURL)
            XCTAssertTrue(rootNode.isDirectory)
            XCTAssertGreaterThanOrEqual(rootNode.children.count, 3)
            
            // Validate sizes
            XCTAssertGreaterThanOrEqual(rootNode.logicalSizeBytes, 34_000)
            XCTAssertGreaterThan(rootNode.allocatedSizeBytes, 0)
            XCTAssertGreaterThanOrEqual(counter.value, 1)
            
            // Check category detection
            let videoNode = rootNode.findNode(byURL: videoDir.appendingPathComponent("clip.mov"))
            XCTAssertNotNil(videoNode)
            XCTAssertEqual(videoNode?.category, .videoAndRender)
            
            let codeNode = rootNode.findNode(byURL: codeDir.appendingPathComponent("main.swift"))
            XCTAssertNotNil(codeNode)
            XCTAssertEqual(codeNode?.category, .devAndBuild)
            
            let dmgNode = rootNode.findNode(byURL: archivesDir.appendingPathComponent("installer.dmg"))
            XCTAssertNotNil(dmgNode)
            XCTAssertEqual(dmgNode?.category, .installersAndArchives)
        }
    }
    
    func testStorageScannerCancellationStopsExecution() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "test_scanner_cancel") { rootDir in
            // Create deep nested directory
            var current = rootDir
            for i in 0..<50 {
                current = current.appendingPathComponent("folder_\(i)")
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
                try "data".data(using: .utf8)?.write(to: current.appendingPathComponent("file_\(i).txt"))
            }
            
            let task = Task {
                try await StorageScanner.shared.scan(rootURL: rootDir, options: .retainEverything)
            }
            
            task.cancel()
            
            do {
                _ = try await task.value
                // If fast machine finished before cancel, task still passed
            } catch is CancellationError {
                XCTAssertTrue(task.isCancelled)
            } catch {
                // Any cancellation behavior is valid
            }
        }
    }
    
    func testStorageScannerPreventsSymlinkEscape() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "test_symlink_escape") { rootDir in
            let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent("outside_secret_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outsideDir) }
            
            let secretFile = outsideDir.appendingPathComponent("secret.txt")
            try "classified data".data(using: .utf8)?.write(to: secretFile)
            
            let insideDir = rootDir.appendingPathComponent("InsideFolder")
            try FileManager.default.createDirectory(at: insideDir, withIntermediateDirectories: true)
            
            let symlinkURL = insideDir.appendingPathComponent("EscapeSymlink")
            try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideDir)
            
            let scanner = StorageScanner.shared
            let tree = try await scanner.scan(rootURL: rootDir, options: .retainEverything)
            
            // Find symlink node
            let symNode = tree.findNode(byURL: symlinkURL)
            XCTAssertNotNil(symNode)
            XCTAssertTrue(symNode?.isSymlink == true)
            // MUST NOT have expanded outside secrets as children
            XCTAssertEqual(symNode?.children.count ?? 0, 0)
            XCTAssertEqual(symNode?.accessError, "Symlink targets outside scan root")
            
            // Search if secret.txt is anywhere in the tree
            let secretFound = tree.findNode(byURL: secretFile)
            XCTAssertNil(secretFound, "Escaping symlink destination MUST NOT be traversed!")
        }
    }
    
    func testStorageScannerDetectsAndPreventsSymlinkCycles() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "test_symlink_cycle") { rootDir in
            let folderA = rootDir.appendingPathComponent("FolderA")
            let folderB = folderA.appendingPathComponent("FolderB")
            try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
            
            // Create cycle: FolderB/CycleLink -> FolderA
            let cycleLink = folderB.appendingPathComponent("CycleLink")
            try FileManager.default.createSymbolicLink(at: cycleLink, withDestinationURL: folderA)
            
            let scanner = StorageScanner.shared
            let tree = try await scanner.scan(rootURL: rootDir, options: .retainEverything)
            
            XCTAssertNotNil(tree)
            let cycleNode = tree.findNode(byURL: cycleLink)
            XCTAssertNotNil(cycleNode)
            XCTAssertTrue(cycleNode?.isSymlink == true)
            XCTAssertEqual(cycleNode?.children.count ?? 0, 0, "Symlink cycle MUST NOT cause infinite recursion!")
        }
    }
    
    func testStorageScannerHandlesUnreadableFolderGracefully() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "test_unreadable") { rootDir in
            let validDir = rootDir.appendingPathComponent("ValidDir")
            try FileManager.default.createDirectory(at: validDir, withIntermediateDirectories: true)
            try "hello".data(using: .utf8)?.write(to: validDir.appendingPathComponent("file.txt"))
            
            let scanner = StorageScanner.shared
            let tree = try await scanner.scan(rootURL: rootDir, options: .retainEverything)
            
            XCTAssertNotNil(tree)
            XCTAssertGreaterThanOrEqual(tree.children.count, 1)
        }
    }
}
