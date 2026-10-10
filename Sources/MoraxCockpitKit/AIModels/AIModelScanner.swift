import Foundation

/// Finds locally installed AI models across the providers that keep them on disk.
///
/// Sizes come from the blobs themselves rather than from the manifests: a manifest states
/// what a layer should weigh, not what it currently occupies, and a partial pull would
/// otherwise be reported at its full advertised size.
public struct AIModelScanner: Sendable {
    private let homeDirectory: URL
    
    private var fileManager: FileManager { .default }
    
    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }
    
    public func scan() async -> [AIModelItem] {
        var items: [AIModelItem] = []
        items.append(contentsOf: scanOllama())
        items.append(contentsOf: scanHuggingFace())
        items.append(contentsOf: scanLMStudio())
        return items.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }
    
    // MARK: - Ollama
    
    public var ollamaRoot: URL {
        homeDirectory.appendingPathComponent(".ollama/models")
    }
    
    /// Ollama stores one manifest per tag and shares content-addressed blobs between tags.
    /// Two tags of the same model can share a 13 GB weights layer, so removing one frees
    /// nothing; only layers referenced by a single manifest are reclaimable.
    func scanOllama() -> [AIModelItem] {
        let manifestsRoot = ollamaRoot.appendingPathComponent("manifests")
        let blobsRoot = ollamaRoot.appendingPathComponent("blobs")
        guard fileManager.fileExists(atPath: manifestsRoot.path) else { return [] }
        
        let manifestFiles = filesRecursively(in: manifestsRoot)
        var digestsByModel: [String: (digests: Set<String>, url: URL, date: Date)] = [:]
        var referenceCount: [String: Int] = [:]
        
        for manifestURL in manifestFiles {
            guard let manifest = try? Data(contentsOf: manifestURL),
                  let parsed = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any] else {
                continue
            }
            
            var digests = Set<String>()
            if let config = parsed["config"] as? [String: Any], let digest = config["digest"] as? String {
                digests.insert(digest)
            }
            for layer in (parsed["layers"] as? [[String: Any]] ?? []) {
                if let digest = layer["digest"] as? String {
                    digests.insert(digest)
                }
            }
            guard !digests.isEmpty else { continue }
            
            let name = Self.ollamaModelName(manifestURL: manifestURL, manifestsRoot: manifestsRoot)
            let date = (try? manifestURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            digestsByModel[name] = (digests, manifestURL, date)
            for digest in digests {
                referenceCount[digest, default: 0] += 1
            }
        }
        
        return digestsByModel.map { name, entry in
            var total: Int64 = 0
            var exclusive: Int64 = 0
            var exclusivePaths: [URL] = [entry.url]
            
            for digest in entry.digests {
                let blobURL = blobsRoot.appendingPathComponent(digest.replacingOccurrences(of: ":", with: "-"))
                let size = fileSize(at: blobURL)
                total += size
                if referenceCount[digest] == 1 {
                    exclusive += size
                    exclusivePaths.append(blobURL)
                }
            }
            
            let sharedNote = exclusive < total
                ? " Une partie des couches est partagée avec un autre tag : seuls \(ByteCountFormatter.string(fromByteCount: exclusive, countStyle: .file)) seraient libérés."
                : ""
            
            return AIModelItem(
                provider: .ollama,
                name: name,
                paths: exclusivePaths,
                totalSizeBytes: total,
                reclaimableBytes: exclusive,
                modifiedDate: entry.date,
                details: "Modèle Ollama.\(sharedNote)"
            )
        }
    }
    
    /// `.../manifests/registry.ollama.ai/library/gemma4/12b` is the model `gemma4:12b`.
    /// A namespace other than `library` is kept, as `ollama rm` needs it.
    static func ollamaModelName(manifestURL: URL, manifestsRoot: URL) -> String {
        let components = manifestURL.path
            .replacingOccurrences(of: manifestsRoot.path + "/", with: "")
            .split(separator: "/")
            .map(String.init)
        guard components.count >= 2 else { return manifestURL.lastPathComponent }
        
        let tag = components[components.count - 1]
        let model = components[components.count - 2]
        // Drop the registry host, and `library` which is Ollama's default namespace.
        let namespaceComponents = components.dropLast(2).dropFirst()
        let namespace = namespaceComponents.filter { $0 != "library" }.joined(separator: "/")
        
        let qualifiedModel = namespace.isEmpty ? model : "\(namespace)/\(model)"
        return "\(qualifiedModel):\(tag)"
    }
    
    // MARK: - Hugging Face
    
    func scanHuggingFace() -> [AIModelItem] {
        let hubRoot = homeDirectory.appendingPathComponent(".cache/huggingface/hub")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: hubRoot.path) else { return [] }
        
        return entries.compactMap { entry in
            guard entry.hasPrefix("models--") else { return nil }
            let directory = hubRoot.appendingPathComponent(entry)
            let size = directorySize(at: directory)
            guard size > 0 else { return nil }
            
            let name = entry
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
            let date = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            
            return AIModelItem(
                provider: .huggingFace,
                name: name,
                paths: [directory],
                totalSizeBytes: size,
                reclaimableBytes: size,
                modifiedDate: date,
                details: "Dépôt du cache Hugging Face."
            )
        }
    }
    
    // MARK: - LM Studio
    
    func scanLMStudio() -> [AIModelItem] {
        let roots = [
            homeDirectory.appendingPathComponent(".lmstudio/models"),
            homeDirectory.appendingPathComponent(".cache/lm-studio/models")
        ]
        
        var items: [AIModelItem] = []
        for root in roots {
            guard let publishers = try? fileManager.contentsOfDirectory(atPath: root.path) else { continue }
            for publisher in publishers where !publisher.hasPrefix(".") {
                let publisherURL = root.appendingPathComponent(publisher)
                guard let repositories = try? fileManager.contentsOfDirectory(atPath: publisherURL.path) else { continue }
                
                for repository in repositories where !repository.hasPrefix(".") {
                    let directory = publisherURL.appendingPathComponent(repository)
                    let size = directorySize(at: directory)
                    guard size > 0 else { continue }
                    let date = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? Date()
                    
                    items.append(AIModelItem(
                        provider: .lmStudio,
                        name: "\(publisher)/\(repository)",
                        paths: [directory],
                        totalSizeBytes: size,
                        reclaimableBytes: size,
                        modifiedDate: date,
                        details: "Modèle téléchargé dans LM Studio."
                    ))
                }
            }
        }
        return items
    }
    
    // MARK: - Sizing
    
    private func fileSize(at url: URL) -> Int64 {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0 else { return 0 }
        return Int64(info.st_blocks) * 512
    }
    
    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return 0
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
    
    private func filesRecursively(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }
        
        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}
