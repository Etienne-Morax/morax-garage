import Foundation
import XCTest
@testable import MoraxCockpitKit

public struct TestFixtures {
    /// Error thrown by `fakeTrasher` for URLs it was told to fail.
    public struct FakeTrashFailure: Error, LocalizedError {
        public let path: String
        public var errorDescription: String? { "Fake trash failure: \(path)" }
    }

    /// A `TrashService.FileTrasher` that moves items into `trashDirectory` instead of the
    /// user's real Trash, and throws for any URL whose last path component is in `failing`.
    public static func fakeTrasher(
        trashDirectory: URL,
        failing: Set<String> = []
    ) -> TrashService.FileTrasher {
        { url in
            if failing.contains(url.lastPathComponent) {
                throw FakeTrashFailure(path: url.path)
            }
            try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            let destination = trashDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// A `TrashService` that logs into `directory/logs` and trashes into `directory/FakeTrash`.
    public static func isolatedTrashService(in directory: URL, failing: Set<String> = []) -> TrashService {
        TrashService(
            operationLog: OperationLog(customLogDirectory: directory.appendingPathComponent("logs")),
            fileTrasher: fakeTrasher(trashDirectory: directory.appendingPathComponent("FakeTrash"), failing: failing)
        )
    }

    /// Creates a temporary directory and executes a block inside it, cleaning up afterwards
    public static func withTempDirectory<T>(prefix: String = "morax_test", _ body: (URL) throws -> T) rethrows -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        return try body(tempDir)
    }
    
    /// Async overload for temporary directory execution
    public static func withTempDirectoryAsync<T>(prefix: String = "morax_test", _ body: (URL) async throws -> T) async rethrows -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        return try await body(tempDir)
    }
    
    /// Creates a fake isolated home directory tree
    public static func withTempHome<T>(_ body: (URL) throws -> T) rethrows -> T {
        try withTempDirectory(prefix: "fake_home") { homeDir in
            let library = homeDir.appendingPathComponent("Library")
            let appSupport = library.appendingPathComponent("Application Support")
            let keychains = library.appendingPathComponent("Keychains")
            let mobileSync = appSupport.appendingPathComponent("MobileSync")
            let downloads = homeDir.appendingPathComponent("Downloads")
            let desktop = homeDir.appendingPathComponent("Desktop")
            let projects = homeDir.appendingPathComponent("Projects")
            
            try? FileManager.default.createDirectory(at: keychains, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: mobileSync, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
            
            return try body(homeDir)
        }
    }
    
    /// Creates a fake project structure with build artifacts
    public static func withFakeProject<T>(name: String = "SampleApp", _ body: (URL) throws -> T) rethrows -> T {
        try withTempDirectory(prefix: name) { projectDir in
            let nodeModules = projectDir.appendingPathComponent("node_modules/lodash")
            let nextBuild = projectDir.appendingPathComponent(".next/cache")
            let dist = projectDir.appendingPathComponent("dist")
            let rustTarget = projectDir.appendingPathComponent("target/release")
            let pyCache = projectDir.appendingPathComponent("__pycache__")
            let src = projectDir.appendingPathComponent("src")
            
            try? FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: nextBuild, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: rustTarget, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: pyCache, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            
            // Create dummy files
            let dummyCode = "console.log('hello');".data(using: .utf8)
            try? dummyCode?.write(to: src.appendingPathComponent("index.ts"))
            try? dummyCode?.write(to: nodeModules.appendingPathComponent("index.js"))
            try? dummyCode?.write(to: dist.appendingPathComponent("bundle.js"))
            
            return try body(projectDir)
        }
    }
    
    /// Creates a fake DaVinci Resolve directory tree with render cache AND protected databases
    public static func withFakeResolveTree<T>(_ body: (_ cacheClip: URL, _ gallery: URL, _ projectDb: URL, _ root: URL) throws -> T) rethrows -> T {
        try withTempDirectory(prefix: "fake_resolve") { root in
            let cacheClip = root.appendingPathComponent("CacheClip/uuid-1234")
            let gallery = root.appendingPathComponent(".gallery/uuid-5678")
            let projectLib = root.appendingPathComponent("Resolve Project Library/Resolve Projects/Project.db")
            let drpFile = root.appendingPathComponent("Exports/FinalCutExport.drp")
            let backups = root.appendingPathComponent("Project Backups/ProjectBackup_2026.bak")
            
            try? FileManager.default.createDirectory(at: cacheClip, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: projectLib.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: drpFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: backups.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            let dummyData = "dummy cache".data(using: .utf8)!
            try? dummyData.write(to: cacheClip.appendingPathComponent("render.dvcc"))
            try? dummyData.write(to: gallery.appendingPathComponent("still.dpx"))
            try? dummyData.write(to: projectLib)
            try? dummyData.write(to: drpFile)
            try? dummyData.write(to: backups)
            
            return try body(cacheClip, gallery, projectLib, root)
        }
    }
}
