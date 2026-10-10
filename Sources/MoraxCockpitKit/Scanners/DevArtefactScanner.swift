import Foundation

public struct DevArtefactScanner: Sendable {
    private let trashService = TrashService.shared
    
    public init() {}
    
    /// Default project directories to scan
    public static var defaultProjectRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("GitHub"),
            home.appendingPathComponent("dev"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Documents/Claude/Projects")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    public func scan(
        projectRoots: [URL] = defaultProjectRoots,
        includeXcodeDerivedData: Bool = true,
        includeGlobalCaches: Bool = true,
        customHomeDirectory: URL? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        let home = customHomeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        // 1. Scan user project directories
        for root in projectRoots {
            if Task.isCancelled { break }
            guard fileManager.fileExists(atPath: root.path) else { continue }
            
            progressHandler?("Scanning project root \(root.lastPathComponent)...")
            let projectItems = scanProjectRoot(root: root, cutoffDate: sevenDaysAgo, progress: progressHandler)
            items.append(contentsOf: projectItems)
        }
        
        // 2. Scan Xcode DerivedData if enabled
        if includeXcodeDerivedData {
            let derivedDataURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            
            if fileManager.fileExists(atPath: derivedDataURL.path) {
                progressHandler?("Scanning Xcode DerivedData...")
                let ddItems = scanXcodeDerivedData(at: derivedDataURL, cutoffDate: sevenDaysAgo)
                items.append(contentsOf: ddItems)
            }
        }
        
        // 3. Scan Global Dev Caches (uv, npm, playwright, puppeteer, CoreSimulator, pnpm)
        if includeGlobalCaches {
            progressHandler?("Scanning global developer caches (uv, npm, browser binaries)...")
            let globalCacheItems = scanGlobalDevCaches(home: home, cutoffDate: sevenDaysAgo)
            items.append(contentsOf: globalCacheItems)
        }
        
        return items
    }
    
    /// Folder names that only mean "build output" when the parent really is a project.
    ///
    /// `dist`, `build` and `target` are ordinary English words: a photographer's
    /// `~/Documents/build` is not a build directory. Each one is therefore only
    /// offered when a recognised project manifest sits next to it.
    private static let markerRequirements: [String: [String]] = [
        "dist": ["package.json", "tsconfig.json", "pyproject.toml", "setup.py", "Makefile", "CMakeLists.txt"],
        "build": ["package.json", "CMakeLists.txt", "Makefile", "pyproject.toml", "setup.py", "build.gradle", "build.gradle.kts", "Package.swift"],
        "target": ["Cargo.toml", "pom.xml", "build.sbt"]
    ]

    private func hasProjectMarker(for folderName: String, parent: URL) -> Bool {
        guard let markers = Self.markerRequirements[folderName] else { return true }
        let fileManager = FileManager.default
        return markers.contains { fileManager.fileExists(atPath: parent.appendingPathComponent($0).path) }
    }

    private func scanProjectRoot(
        root: URL,
        cutoffDate: Date,
        progress: (@Sendable (String) -> Void)?
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }
        
        struct FolderSpec {
            let category: CleanupCategory
            let riskTier: RiskTier
            let riskReason: String
        }
        
        let targetFolderSpecs: [String: FolderSpec] = [
            "node_modules": FolderSpec(
                category: .devNodeModules,
                riskTier: .rebuildCost,
                riskReason: "Node.js dependencies — requires 'npm/pnpm/yarn install' to rebuild."
            ),
            ".next": FolderSpec(
                category: .devBuildArtifacts,
                riskTier: .safe,
                riskReason: "Next.js build cache — regenerated upon next build."
            ),
            "dist": FolderSpec(
                category: .devBuildArtifacts,
                riskTier: .safe,
                riskReason: "Distribution build output — regenerated upon build."
            ),
            "build": FolderSpec(
                category: .devBuildArtifacts,
                riskTier: .safe,
                riskReason: "Build output folder — regenerated upon build."
            ),
            "target": FolderSpec(
                category: .devRustTarget,
                riskTier: .rebuildCost,
                riskReason: "Rust target directory — cargo build will recompile from scratch."
            ),
            ".venv": FolderSpec(
                category: .devPythonVenv,
                riskTier: .rebuildCost,
                riskReason: "Python virtual environment — packages will need to be re-installed."
            ),
            "venv": FolderSpec(
                category: .devPythonVenv,
                riskTier: .rebuildCost,
                riskReason: "Python virtual environment — packages will need to be re-installed."
            ),
            "__pycache__": FolderSpec(
                category: .devPythonVenv,
                riskTier: .safe,
                riskReason: "Python bytecode cache — regenerated automatically."
            )
        ]
        
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            
            let name = url.lastPathComponent
            if name == ".git" || name == ".svn" || name == ".hg" || name == ".DS_Store" ||
               name == ".gradle" || name == ".cargo" || name == ".rustup" || name == ".npm" ||
               name == ".cache" || name == "Pods" || name == "vendor" || name == ".terraform" ||
               name == ".bundle" || name == ".idea" || name == ".vscode" || name == "tmp" {
                enumerator.skipDescendants()
                continue
            }
            
            if let spec = targetFolderSpecs[name] {
                // Skip searching inside this build artifact folder
                enumerator.skipDescendants()
                
                // Check parent project modification date to determine recentness
                let parentURL = url.deletingLastPathComponent()
                guard hasProjectMarker(for: name, parent: parentURL) else { continue }
                let parentModDate = (try? parentURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = parentModDate > cutoffDate
                
                let size = trashService.calculateSize(url: url)
                let itemModDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                
                if size > 0 {
                    let projectName = parentURL.lastPathComponent
                    results.append(FileItem(
                        url: url,
                        name: "\(projectName)/\(name)",
                        sizeBytes: size,
                        modifiedDate: itemModDate,
                        category: spec.category,
                        riskTier: spec.riskTier,
                        riskReason: spec.riskReason,
                        isRecent: isRecent,
                        isSelected: false, // Deselected by default
                        details: isRecent ? "Recent project (active within 7 days)" : "Inactive build artifact"
                    ))
                }
            }
        }
        
        return results
    }
    
    private func scanXcodeDerivedData(at derivedDataURL: URL, cutoffDate: Date) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: derivedDataURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for itemURL in contents {
            if Task.isCancelled { break }
            if itemURL.lastPathComponent == "ModuleCache.noindex" { continue }
            
            let size = trashService.calculateSize(url: itemURL)
            let modDate = (try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            if size > 0 {
                results.append(FileItem(
                    url: itemURL,
                    name: "DerivedData/\(itemURL.lastPathComponent)",
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .devXcodeDerivedData,
                    riskTier: .safe,
                    riskReason: "Xcode build cache — regenerated upon next build.",
                    isRecent: isRecent,
                    isSelected: false,
                    details: isRecent ? "Active Xcode project cache" : "Stale Xcode build cache"
                ))
            }
        }
        
        return results
    }
    
    private func scanGlobalDevCaches(home: URL, cutoffDate: Date) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        struct GlobalCacheSpec {
            let relativePath: String
            let displayName: String
            let category: CleanupCategory
            let riskTier: RiskTier
            let riskReason: String
            let details: String
        }
        
        let candidates: [GlobalCacheSpec] = [
            GlobalCacheSpec(
                relativePath: ".cache/uv",
                displayName: "uv Package Cache (~/.cache/uv)",
                category: .devPythonVenv,
                riskTier: .rebuildCost,
                riskReason: "uv Python package cache — packages will need to be re-downloaded.",
                details: "Python wheels and source tarballs cache for uv"
            ),
            GlobalCacheSpec(
                relativePath: ".npm",
                displayName: "npm Cache (~/.npm)",
                category: .devNodeModules,
                riskTier: .rebuildCost,
                riskReason: "npm package cache — packages will need to be re-downloaded. Prefer 'npm cache clean --force'.",
                details: "Node package manager global tarball and index cache"
            ),
            GlobalCacheSpec(
                relativePath: ".cache/puppeteer",
                displayName: "Puppeteer Binaries (~/.cache/puppeteer)",
                category: .devBuildArtifacts,
                riskTier: .rebuildCost,
                riskReason: "Puppeteer browser binaries cache.",
                details: "Downloaded Chrome/Chromium test browser binaries"
            ),
            GlobalCacheSpec(
                relativePath: "Library/Caches/ms-playwright",
                displayName: "Playwright Binaries (~/Library/Caches/ms-playwright)",
                category: .devBuildArtifacts,
                riskTier: .rebuildCost,
                riskReason: "Playwright browser binaries cache.",
                details: "Downloaded Chromium, Firefox and WebKit binaries for Playwright"
            ),
            GlobalCacheSpec(
                relativePath: "Library/Developer/CoreSimulator/Caches",
                displayName: "CoreSimulator Caches (~/Library/Developer/CoreSimulator/Caches)",
                category: .devXcodeDerivedData,
                riskTier: .rebuildCost,
                riskReason: "CoreSimulator runtime caches (excluding device state).",
                details: "iOS/watchOS/tvOS Simulator runtime download and execution caches"
            ),
            GlobalCacheSpec(
                relativePath: "Library/pnpm",
                displayName: "pnpm Content-Addressable Store (~/Library/pnpm)",
                category: .devNodeModules,
                riskTier: .blocked,
                riskReason: "pnpm content-addressable store — hardlinked to installed projects. Use 'pnpm store prune' instead.",
                details: "Global hardlink store for pnpm packages — trashing breaks installed projects"
            ),
            GlobalCacheSpec(
                relativePath: "Library/Caches/pnpm",
                displayName: "pnpm Metadata Cache (~/Library/Caches/pnpm)",
                category: .devNodeModules,
                riskTier: .blocked,
                riskReason: "pnpm download cache & metadata store. Use 'pnpm store prune' instead.",
                details: "pnpm registry metadata and index cache"
            )
        ]
        
        for candidate in candidates {
            if Task.isCancelled { break }
            let targetURL = home.appendingPathComponent(candidate.relativePath)
            guard fileManager.fileExists(atPath: targetURL.path) else { continue }
            
            let size = trashService.calculateSize(url: targetURL)
            let modDate = (try? targetURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            if size > 0 {
                results.append(FileItem(
                    url: targetURL,
                    name: candidate.displayName,
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: candidate.category,
                    riskTier: candidate.riskTier,
                    riskReason: candidate.riskReason,
                    isRecent: isRecent,
                    isSelected: false,
                    details: candidate.details
                ))
            }
        }
        
        return results
    }
}
