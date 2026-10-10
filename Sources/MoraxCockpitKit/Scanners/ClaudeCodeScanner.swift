import Foundation
import AppKit

public protocol ClaudeProcessChecking: Sendable {
    func isClaudeCodeRunning() -> Bool
}

public struct DefaultClaudeProcessChecker: ClaudeProcessChecking {
    public init() {}
    
    public func isClaudeCodeRunning() -> Bool {
        // 1. Check NSWorkspace running applications
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            if let name = app.localizedName?.lowercased(), name.contains("claude") {
                return true
            }
            if let bundleId = app.bundleIdentifier?.lowercased(), bundleId.contains("claude") {
                return true
            }
        }
        
        // 2. Check pgrep -f "claude"
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "claude"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            }
        } catch {
            // Ignore failure
        }
        
        return false
    }
}

public struct ClaudeCodeScanner: Sendable {
    private let trashService = TrashService.shared
    private let processChecker: any ClaudeProcessChecking
    
    public init(processChecker: any ClaudeProcessChecking = DefaultClaudeProcessChecker()) {
        self.processChecker = processChecker
    }
    
    /// Scans both user project roots for local Claude artifacts (worktrees, preadopt backups)
    /// and the global ~/.claude directory for transcripts, plugin cache, and telemetry.
    public func scan(
        projectRoots: [URL] = DevArtefactScanner.defaultProjectRoots,
        claudeHome: URL? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        // 1. Scan Local Project Artifacts (.claude/worktrees, *.preadopt-*, *.pre-move-*)
        for root in projectRoots {
            if Task.isCancelled { break }
            guard fileManager.fileExists(atPath: root.path) else { continue }
            
            progressHandler?("Scanning project root \(root.lastPathComponent) for Claude artifacts...")
            let projectItems = scanProjectRootForClaudeArtifacts(root: root, cutoffDate: sevenDaysAgo, progress: progressHandler)
            items.append(contentsOf: projectItems)
        }
        
        // 2. Scan Global ~/.claude Directory
        let targetClaudeHome = claudeHome ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        if fileManager.fileExists(atPath: targetClaudeHome.path) {
            progressHandler?("Scanning global Claude cache & transcripts (~/.claude)...")
            let globalItems = scanGlobalClaudeDirectory(claudeHome: targetClaudeHome, cutoffDate: sevenDaysAgo, progress: progressHandler)
            items.append(contentsOf: globalItems)
        }
        
        return items
    }
    
    // MARK: - Project Level Scanner
    
    private func scanProjectRootForClaudeArtifacts(
        root: URL,
        cutoffDate: Date,
        progress: (@Sendable (String) -> Void)?
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }
        
        for item in contents {
            if Task.isCancelled { break }
            let name = item.lastPathComponent
            
            // Check for preadopt / pre-move backup directories (e.g. Project.preadopt-20260813T170352Z)
            if name.contains(".preadopt-") || name.contains(".pre-move-") {
                let size = trashService.calculateSize(url: item)
                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                if size > 0 {
                    results.append(FileItem(
                        url: item,
                        name: name,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .claudePreadoptBackups,
                        riskTier: .destructive,
                        riskReason: "Project backup snapshot created before preadopt or move.",
                        isRecent: isRecent,
                        isSelected: false,
                        details: isRecent ? "Recent preadopt project snapshot (within 7 days)" : "Archived preadopt project snapshot"
                    ))
                }
                continue
            }
            
            // If it's a project directory, inspect its .claude folder
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let projectClaudeDir = item.appendingPathComponent(".claude")
                if fileManager.fileExists(atPath: projectClaudeDir.path) {
                    let worktreesDir = projectClaudeDir.appendingPathComponent("worktrees")
                    if fileManager.fileExists(atPath: worktreesDir.path) {
                        let worktreeItems = scanWorktreesDirectory(
                            worktreesURL: worktreesDir,
                            projectName: name,
                            cutoffDate: cutoffDate
                        )
                        results.append(contentsOf: worktreeItems)
                    }
                    
                    let localCacheDir = projectClaudeDir.appendingPathComponent("cache")
                    if fileManager.fileExists(atPath: localCacheDir.path) {
                        let size = trashService.calculateSize(url: localCacheDir)
                        let modDate = (try? localCacheDir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                        let isRecent = modDate > cutoffDate
                        
                        if size > 0 {
                            results.append(FileItem(
                                url: localCacheDir,
                                name: "\(name)/.claude/cache",
                                sizeBytes: size,
                                modifiedDate: modDate,
                                category: .claudeSnapshotsAndTasks,
                                riskTier: .safe,
                                riskReason: "Project-local Claude cache.",
                                isRecent: isRecent,
                                isSelected: false,
                                details: "Project-local Claude cache"
                            ))
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    private func scanWorktreesDirectory(
        worktreesURL: URL,
        projectName: String,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        
        guard let entries = try? fileManager.contentsOfDirectory(
            at: worktreesURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for worktreeURL in entries {
            if Task.isCancelled { break }
            let size = trashService.calculateSize(url: worktreeURL)
            let modDate = (try? worktreeURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            let isModifiedWithin24h = modDate > twentyFourHoursAgo
            
            let tier: RiskTier = isModifiedWithin24h ? .blocked : .destructive
            let reason: String = isModifiedWithin24h
                ? "Active Claude Code worktree modified within 24 hours."
                : "Claude subagent git worktree with unmerged branch state."
            
            if size > 0 {
                results.append(FileItem(
                    url: worktreeURL,
                    name: "\(projectName)/worktrees/\(worktreeURL.lastPathComponent)",
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .claudeWorktrees,
                    riskTier: tier,
                    riskReason: reason,
                    isRecent: isRecent,
                    isSelected: false,
                    details: isModifiedWithin24h ? "Active Claude worktree (<24h) — blocked" : (isRecent ? "Recent Claude subagent worktree" : "Orphaned Claude subagent worktree")
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Global ~/.claude Scanner
    
    private func scanGlobalClaudeDirectory(
        claudeHome: URL,
        cutoffDate: Date,
        progress: (@Sendable (String) -> Void)?
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        let isRunning = processChecker.isClaudeCodeRunning()
        
        // 1. Session Transcripts (~/.claude/projects/*)
        let projectsDir = claudeHome.appendingPathComponent("projects")
        if fileManager.fileExists(atPath: projectsDir.path) {
            let transcriptItems = scanProjectTranscripts(projectsDir: projectsDir, cutoffDate: cutoffDate)
            results.append(contentsOf: transcriptItems)
        }
        
        // 2. Plugin Download Cache (~/.claude/plugins/cache)
        let pluginCacheDir = claudeHome.appendingPathComponent("plugins/cache")
        if fileManager.fileExists(atPath: pluginCacheDir.path) {
            let size = trashService.calculateSize(url: pluginCacheDir)
            let modDate = (try? pluginCacheDir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            if size > 0 {
                results.append(FileItem(
                    url: pluginCacheDir,
                    name: "~/.claude/plugins/cache",
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .claudePluginCache,
                    riskTier: .rebuildCost,
                    riskReason: "Installed plugins run from this cache — hooks and status lines break until it is re-downloaded.",
                    isRecent: isRecent,
                    isSelected: false,
                    details: "Downloaded Claude plugin tarballs and package cache"
                ))
            }
        }
        
        // 3. Telemetry (~/.claude/telemetry)
        let telemetryDir = claudeHome.appendingPathComponent("telemetry")
        if fileManager.fileExists(atPath: telemetryDir.path) {
            let size = trashService.calculateSize(url: telemetryDir)
            let modDate = (try? telemetryDir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate
            
            if size > 0 {
                results.append(FileItem(
                    url: telemetryDir,
                    name: "~/.claude/telemetry",
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .claudeTelemetry,
                    riskTier: .safe,
                    riskReason: "Claude Code telemetry, event logs and diagnostics.",
                    isRecent: isRecent,
                    isSelected: false,
                    details: "Claude Code telemetry, event logs and diagnostics"
                ))
            }
        }
        
        // 4. Shell snapshots, tasks, session-data, backups, general cache
        struct TransientConfig {
            let subPath: String
            let displayName: String
            let category: CleanupCategory
            let defaultTier: RiskTier
            let defaultReason: String
            let runningTier: RiskTier?
            let runningReason: String?
        }
        
        let transientFolders: [TransientConfig] = [
            TransientConfig(
                subPath: "shell-snapshots",
                displayName: "~/.claude/shell-snapshots",
                category: .claudeSnapshotsAndTasks,
                defaultTier: .safe,
                defaultReason: "Regenerated at each session start.",
                runningTier: nil,
                runningReason: nil
            ),
            TransientConfig(
                subPath: "cache",
                displayName: "~/.claude/cache",
                category: .claudeSnapshotsAndTasks,
                defaultTier: .safe,
                defaultReason: "Pure cache.",
                runningTier: nil,
                runningReason: nil
            ),
            TransientConfig(
                subPath: "tasks",
                displayName: "~/.claude/tasks",
                category: .claudeSnapshotsAndTasks,
                defaultTier: .destructive,
                defaultReason: "Live agent task state.",
                runningTier: .blocked,
                runningReason: "A Claude Code session is running — trashing this corrupts live state."
            ),
            TransientConfig(
                subPath: "session-data",
                displayName: "~/.claude/session-data",
                category: .claudeSnapshotsAndTasks,
                defaultTier: .destructive,
                defaultReason: "Live session state.",
                runningTier: .blocked,
                runningReason: "A Claude Code session is running — trashing this corrupts live state."
            ),
            TransientConfig(
                subPath: "sessions",
                displayName: "~/.claude/sessions",
                category: .claudeSnapshotsAndTasks,
                defaultTier: .destructive,
                defaultReason: "Live session state.",
                runningTier: .blocked,
                runningReason: "A Claude Code session is running — trashing this corrupts live state."
            ),
            TransientConfig(
                subPath: "backups",
                displayName: "~/.claude/backups",
                category: .claudeSnapshotsAndTasks,
                defaultTier: .blocked,
                defaultReason: "Recovery net; no gain.",
                runningTier: nil,
                runningReason: nil
            )
        ]
        
        for config in transientFolders {
            let folderURL = claudeHome.appendingPathComponent(config.subPath)
            if fileManager.fileExists(atPath: folderURL.path) {
                let size = trashService.calculateSize(url: folderURL)
                let modDate = (try? folderURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let isRecent = modDate > cutoffDate
                
                let tier: RiskTier
                let reason: String
                if isRunning, let runTier = config.runningTier, let runReason = config.runningReason {
                    tier = runTier
                    reason = runReason
                } else {
                    tier = config.defaultTier
                    reason = config.defaultReason
                }
                
                if size > 0 {
                    results.append(FileItem(
                        url: folderURL,
                        name: config.displayName,
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: config.category,
                        riskTier: tier,
                        riskReason: reason,
                        isRecent: isRecent,
                        isSelected: false,
                        details: "Transient Claude Code execution state (\(config.subPath))"
                    ))
                }
            }
        }
        
        return results
    }
    
    private func scanProjectTranscripts(
        projectsDir: URL,
        cutoffDate: Date
    ) -> [FileItem] {
        let fileManager = FileManager.default
        var results: [FileItem] = []
        
        guard let projectFolders = try? fileManager.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for projFolder in projectFolders {
            if Task.isCancelled { break }

            // Format human-readable project title from encoded folder name
            // e.g. -Users-user-Documents-Code-my-project -> my-project
            let rawName = projFolder.lastPathComponent
            let readableName = rawName.split(separator: "-").last.map(String.init) ?? rawName

            // A project folder holds session transcripts *and*, for some projects, the
            // persistent memory directory. Memory never regenerates and is not part of
            // what "clearing transcripts" means, so those folders are offered file by
            // file with the memory directory left out.
            let memoryURL = projFolder.appendingPathComponent("memory")
            let holdsMemory = fileManager.fileExists(atPath: memoryURL.path)

            if holdsMemory {
                let children = (try? fileManager.contentsOfDirectory(
                    at: projFolder,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: []
                )) ?? []

                for child in children where child.lastPathComponent != "memory" {
                    let size = trashService.calculateSize(url: child)
                    guard size > 0 else { continue }
                    let modDate = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

                    results.append(FileItem(
                        url: child,
                        name: "Transcripts: \(readableName)/\(child.lastPathComponent)",
                        sizeBytes: size,
                        modifiedDate: modDate,
                        category: .claudeSessionTranscripts,
                        riskTier: .destructive,
                        riskReason: "Conversation history — breaks --resume and episodic memory search.",
                        isRecent: modDate > cutoffDate,
                        isSelected: false,
                        details: "Session transcript (persistent memory in this project is excluded)"
                    ))
                }
                continue
            }

            let size = trashService.calculateSize(url: projFolder)
            let modDate = (try? projFolder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let isRecent = modDate > cutoffDate

            if size > 0 {
                results.append(FileItem(
                    url: projFolder,
                    name: "Transcripts: \(readableName)",
                    sizeBytes: size,
                    modifiedDate: modDate,
                    category: .claudeSessionTranscripts,
                    riskTier: .destructive,
                    riskReason: "Conversation history — breaks --resume and episodic memory search.",
                    isRecent: isRecent,
                    isSelected: false,
                    details: isRecent ? "Recent project session logs & tool transcripts" : "Archived project session logs & tool transcripts"
                ))
            }
        }
        
        return results
    }
}
