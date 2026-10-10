import XCTest
@testable import MoraxCockpitKit

final class AIModelScannerTests: XCTestCase {
    
    private let weightsSize = 3 * 1024 * 1024
    private let templateSize = 2 * 1024 * 1024
    
    /// Builds an Ollama store where two tags of the same model share the weights layer and
    /// each own a private template layer — the case where a naive size sums to twice the
    /// space that removing one tag would actually free.
    private func makeOllamaFixture(in home: URL) throws {
        let models = home.appendingPathComponent(".ollama/models")
        let blobs = models.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        
        let sharedDigest = "sha256:" + String(repeating: "a", count: 64)
        let firstPrivate = "sha256:" + String(repeating: "b", count: 64)
        let secondPrivate = "sha256:" + String(repeating: "c", count: 64)
        
        for (digest, size) in [(sharedDigest, weightsSize), (firstPrivate, templateSize), (secondPrivate, templateSize)] {
            let blobURL = blobs.appendingPathComponent(digest.replacingOccurrences(of: ":", with: "-"))
            try Data(repeating: 0x11, count: size).write(to: blobURL)
        }
        
        func writeManifest(at path: String, layers: [String]) throws {
            let url = models.appendingPathComponent("manifests/\(path)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "schemaVersion": 2,
                "layers": layers.map { ["digest": $0, "mediaType": "application/vnd.ollama.image.model"] }
            ]
            try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        }
        
        try writeManifest(at: "registry.ollama.ai/library/gemma4/12b", layers: [sharedDigest, firstPrivate])
        try writeManifest(at: "registry.ollama.ai/library/gemma4/latest", layers: [sharedDigest, secondPrivate])
    }
    
    func testOllamaModelsAreDiscoveredWithProviderNaming() throws {
        try TestFixtures.withTempDirectory(prefix: "ai_ollama") { home in
            try makeOllamaFixture(in: home)
            
            let models = AIModelScanner(homeDirectory: home).scanOllama()
            let names = Set(models.map(\.name))
            
            XCTAssertEqual(names, ["gemma4:12b", "gemma4:latest"])
            XCTAssertTrue(models.allSatisfy { $0.provider == .ollama })
        }
    }
    
    func testSharedLayersAreExcludedFromReclaimableSize() throws {
        try TestFixtures.withTempDirectory(prefix: "ai_shared") { home in
            try makeOllamaFixture(in: home)
            
            let models = AIModelScanner(homeDirectory: home).scanOllama()
            let tag = try XCTUnwrap(models.first { $0.name == "gemma4:12b" })
            
            XCTAssertGreaterThanOrEqual(tag.totalSizeBytes, Int64(weightsSize + templateSize))
            XCTAssertTrue(tag.sharesLayers, "The weights layer is referenced by both tags")
            XCTAssertLessThan(tag.reclaimableBytes, Int64(weightsSize))
            XCTAssertGreaterThanOrEqual(tag.reclaimableBytes, Int64(templateSize))
            
            // Only the manifest and the layer no other tag references may be deleted.
            let deletedNames = Set(tag.paths.map(\.lastPathComponent))
            XCTAssertTrue(deletedNames.contains("12b"))
            XCTAssertFalse(
                deletedNames.contains("sha256-" + String(repeating: "a", count: 64)),
                "A shared blob must never be listed for deletion"
            )
        }
    }
    
    func testUnsharedModelReclaimsItsWholeSize() throws {
        try TestFixtures.withTempDirectory(prefix: "ai_solo") { home in
            let models = home.appendingPathComponent(".ollama/models")
            let blobs = models.appendingPathComponent("blobs")
            try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
            
            let digest = "sha256:" + String(repeating: "d", count: 64)
            try Data(repeating: 0x22, count: weightsSize)
                .write(to: blobs.appendingPathComponent(digest.replacingOccurrences(of: ":", with: "-")))
            
            let manifestURL = models.appendingPathComponent("manifests/registry.ollama.ai/library/solo/latest")
            try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 2,
                "layers": [["digest": digest]]
            ]).write(to: manifestURL)
            
            let model = try XCTUnwrap(AIModelScanner(homeDirectory: home).scanOllama().first)
            
            XCTAssertEqual(model.name, "solo:latest")
            XCTAssertFalse(model.sharesLayers)
            XCTAssertEqual(model.reclaimableBytes, model.totalSizeBytes)
        }
    }
    
    func testNamespacedModelKeepsItsNamespaceForOllamaRemove() {
        let root = URL(fileURLWithPath: "/models/manifests")
        
        XCTAssertEqual(
            AIModelScanner.ollamaModelName(
                manifestURL: root.appendingPathComponent("registry.ollama.ai/library/gemma4/12b"),
                manifestsRoot: root
            ),
            "gemma4:12b"
        )
        XCTAssertEqual(
            AIModelScanner.ollamaModelName(
                manifestURL: root.appendingPathComponent("hf.co/unsloth/qwen3/q4"),
                manifestsRoot: root
            ),
            "unsloth/qwen3:q4"
        )
    }
    
    func testHuggingFaceAndLMStudioRepositoriesAreDiscovered() throws {
        try TestFixtures.withTempDirectory(prefix: "ai_repos") { home in
            let hub = home.appendingPathComponent(".cache/huggingface/hub/models--Qwen--Qwen3-TTS/snapshots/main")
            try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
            try Data(repeating: 0x33, count: 1_500_000).write(to: hub.appendingPathComponent("model.safetensors"))
            
            let lmStudio = home.appendingPathComponent(".lmstudio/models/lmstudio-community/Mistral-7B")
            try FileManager.default.createDirectory(at: lmStudio, withIntermediateDirectories: true)
            try Data(repeating: 0x44, count: 900_000).write(to: lmStudio.appendingPathComponent("model.gguf"))
            
            let scanner = AIModelScanner(homeDirectory: home)
            
            let hubModel = try XCTUnwrap(scanner.scanHuggingFace().first)
            XCTAssertEqual(hubModel.name, "Qwen/Qwen3-TTS")
            XCTAssertEqual(hubModel.provider, .huggingFace)
            XCTAssertGreaterThanOrEqual(hubModel.totalSizeBytes, 1_500_000)
            XCTAssertEqual(hubModel.reclaimableBytes, hubModel.totalSizeBytes)
            
            let lmModel = try XCTUnwrap(scanner.scanLMStudio().first)
            XCTAssertEqual(lmModel.name, "lmstudio-community/Mistral-7B")
            XCTAssertEqual(lmModel.provider, .lmStudio)
            XCTAssertGreaterThanOrEqual(lmModel.totalSizeBytes, 900_000)
        }
    }
    
    func testEmptyHomeYieldsNoModels() async throws {
        await TestFixtures.withTempDirectoryAsync(prefix: "ai_empty") { home in
            let models = await AIModelScanner(homeDirectory: home).scan()
            XCTAssertTrue(models.isEmpty)
        }
    }
}
