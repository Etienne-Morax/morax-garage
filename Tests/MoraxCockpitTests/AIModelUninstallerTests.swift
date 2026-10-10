import XCTest
@testable import MoraxCockpitKit

final class AIModelUninstallerTests: XCTestCase {
    
    func testHuggingFaceModelIsTrashedAndReported() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "ai_uninstall_hf") { tempDir in
            let logDirectory = tempDir.appendingPathComponent("logs")
            let operationLog = OperationLog(customLogDirectory: logDirectory)
            let uninstaller = AIModelUninstaller(
                trashService: TrashService(operationLog: operationLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash"))),
                operationLog: operationLog
            )
            
            let modelDirectory = tempDir.appendingPathComponent("models--Qwen--Qwen3")
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            try Data(repeating: 0x55, count: 64_000).write(to: modelDirectory.appendingPathComponent("model.safetensors"))
            
            let model = AIModelItem(
                provider: .huggingFace,
                name: "Qwen/Qwen3",
                paths: [modelDirectory],
                totalSizeBytes: 64_000,
                reclaimableBytes: 64_000,
                modifiedDate: Date()
            )
            
            let result = await uninstaller.remove(model)
            
            XCTAssertTrue(result.isSuccess)
            XCTAssertEqual(result.method, .trash, "A removal must stay recoverable from the Trash")
            XCTAssertGreaterThan(result.reclaimedBytes, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: modelDirectory.path))
        }
    }
    
    func testRemovalFailureIsReportedRatherThanSwallowed() async throws {
        await TestFixtures.withTempDirectoryAsync(prefix: "ai_uninstall_fail") { tempDir in
            let operationLog = OperationLog(customLogDirectory: tempDir.appendingPathComponent("logs"))
            let uninstaller = AIModelUninstaller(
                trashService: TrashService(operationLog: operationLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash"))),
                operationLog: operationLog
            )
            
            let model = AIModelItem(
                provider: .lmStudio,
                name: "ghost/model",
                paths: [tempDir.appendingPathComponent("does-not-exist")],
                totalSizeBytes: 10,
                reclaimableBytes: 10,
                modifiedDate: Date()
            )
            
            let result = await uninstaller.remove(model)
            
            XCTAssertFalse(result.isSuccess)
            XCTAssertEqual(result.method, .failed)
            XCTAssertFalse(result.message.isEmpty)
        }
    }
    
    func testProtectedPathIsRefusedByTheSafetyGate() async throws {
        await TestFixtures.withTempDirectoryAsync(prefix: "ai_uninstall_guard") { tempDir in
            let operationLog = OperationLog(customLogDirectory: tempDir.appendingPathComponent("logs"))
            let uninstaller = AIModelUninstaller(
                trashService: TrashService(operationLog: operationLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash"))),
                operationLog: operationLog
            )
            
            // A malformed inventory must never let a system path through to the Trash.
            let model = AIModelItem(
                provider: .huggingFace,
                name: "bogus",
                paths: [URL(fileURLWithPath: "/System/Library")],
                totalSizeBytes: 1,
                reclaimableBytes: 1,
                modifiedDate: Date()
            )
            
            let result = await uninstaller.remove(model)
            
            XCTAssertFalse(result.isSuccess)
            XCTAssertTrue(FileManager.default.fileExists(atPath: "/System/Library"))
        }
    }
    
    func testOllamaExecutableLookupIgnoresMissingBinaries() {
        // The lookup must be location based: a GUI app does not inherit the shell PATH.
        XCTAssertTrue(AIModelUninstaller.ollamaExecutableCandidates.allSatisfy { $0.hasPrefix("/") })
        
        if let executable = AIModelUninstaller.ollamaExecutableURL() {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        }
    }
    
    /// A stopped Ollama daemon must not block the removal: the CLI is a convenience, not
    /// the only way to drop a manifest and its exclusive layers.
    func testStoppedOllamaServerIsDetectedAsAFallbackCase() {
        XCTAssertTrue(AIModelUninstaller.isServerUnavailable(
            "Error: could not connect to ollama server, run 'ollama serve' to start it"
        ))
        XCTAssertTrue(AIModelUninstaller.isServerUnavailable("dial tcp 127.0.0.1:11434: connection refused"))
        XCTAssertFalse(AIModelUninstaller.isServerUnavailable("Error: model 'ghost' not found"))
    }
    
    func testOllamaFallsBackToTrashWhenTheServerIsDown() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "ai_ollama_fallback") { tempDir in
            let operationLog = OperationLog(customLogDirectory: tempDir.appendingPathComponent("logs"))
            let uninstaller = AIModelUninstaller(
                trashService: TrashService(operationLog: operationLog, fileTrasher: TestFixtures.fakeTrasher(trashDirectory: tempDir.appendingPathComponent("FakeTrash"))),
                operationLog: operationLog
            )
            
            let manifest = tempDir.appendingPathComponent("manifests/library/ghost/latest")
            try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x66, count: 512).write(to: manifest)
            let blob = tempDir.appendingPathComponent("blobs/sha256-deadbeef")
            try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x77, count: 32_000).write(to: blob)
            
            let model = AIModelItem(
                provider: .ollama,
                // A name the CLI cannot resolve, so the command fails and the fallback runs.
                name: "morax-test-nonexistent-model:latest",
                paths: [manifest, blob],
                totalSizeBytes: 32_512,
                reclaimableBytes: 32_512,
                modifiedDate: Date()
            )
            
            let result = await uninstaller.remove(model)
            
            // Either the CLI is absent or the daemon is down: both land on the Trash path.
            // With a running daemon the unknown name is a genuine error, which must be
            // reported rather than silently deleting files.
            if result.isSuccess {
                XCTAssertEqual(result.method, .trash)
                XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
            } else {
                XCTAssertEqual(result.method, .failed)
                XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
            }
        }
    }
}
