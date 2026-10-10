import XCTest
import Foundation
@testable import MoraxCockpitKit

final class ScannerTests: XCTestCase {
    
    func testResolveScannerFindsCachesAndProtectsDatabases() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "resolve_test") { root in
            let cacheClip = root.appendingPathComponent("CacheClip/project-uuid")
            let gallery = root.appendingPathComponent(".gallery/stills-uuid")
            let projectLib = root.appendingPathComponent("Resolve Project Library/Resolve Projects/Project.db")
            let drpFile = root.appendingPathComponent("TimelineExport.drp")
            let backups = root.appendingPathComponent("Project Backups/ProjectBackup_2026.bak")
            
            try FileManager.default.createDirectory(at: cacheClip, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: projectLib.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: backups.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            try "cache data".data(using: .utf8)?.write(to: cacheClip.appendingPathComponent("frame001.dvcc"))
            try "still data".data(using: .utf8)?.write(to: gallery.appendingPathComponent("still001.dpx"))
            try "CRITICAL DATABASE".data(using: .utf8)?.write(to: projectLib)
            try "CRITICAL DRP EXPORT".data(using: .utf8)?.write(to: drpFile)
            try "CRITICAL BACKUP".data(using: .utf8)?.write(to: backups)
            
            let scanner = ResolveScanner()
            let items = await scanner.scan(customScratchRoot: root)
            
            // 1. Must find CacheClip & Gallery
            let cacheItem = items.first(where: { $0.category == .resolveRenderCache })
            let galleryItem = items.first(where: { $0.category == .resolveGalleryStills })
            XCTAssertNotNil(cacheItem)
            XCTAssertNotNil(galleryItem)
            
            // 2. CRITICAL NEGATIVE TEST: Must NOT contain any project databases, libraries, backups or .drp files
            for item in items {
                let lower = item.path.lowercased()
                XCTAssertFalse(lower.contains("resolve project library"), "Found protected project library: \(item.path)")
                XCTAssertFalse(lower.contains("project backups"), "Found protected project backups: \(item.path)")
                XCTAssertFalse(lower.hasSuffix(".drp"), "Found protected .drp export: \(item.path)")
                XCTAssertFalse(lower.hasSuffix("project.db"), "Found protected Project.db: \(item.path)")
            }
        }
    }
    
    func testDevArtefactScannerDetectsArtifactsAndFlagsRecent() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "dev_scan_test") { root in
            let projectA = root.appendingPathComponent("ProjectA")
            let projectB = root.appendingPathComponent("ProjectB")
            
            let nodeModulesA = projectA.appendingPathComponent("node_modules/pkg")
            let nextCacheB = projectB.appendingPathComponent(".next/cache")
            
            try FileManager.default.createDirectory(at: nodeModulesA, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nextCacheB, withIntermediateDirectories: true)
            
            try "dummy js".data(using: .utf8)?.write(to: nodeModulesA.appendingPathComponent("index.js"))
            try "dummy cache".data(using: .utf8)?.write(to: nextCacheB.appendingPathComponent("build.js"))
            
            // Set projectA to recent (now) and projectB to old (30 days ago)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            try FileManager.default.setAttributes([.modificationDate: thirtyDaysAgo], ofItemAtPath: projectB.path)
            
            let scanner = DevArtefactScanner()
            let items = await scanner.scan(projectRoots: [root], includeXcodeDerivedData: false, includeGlobalCaches: false)
            
            XCTAssertEqual(items.count, 2)
            
            // Verify everything is deselected by default
            for item in items {
                XCTAssertFalse(item.isSelected, "Item must be deselected by default: \(item.name)")
            }
            
            let itemA = items.first(where: { $0.category == .devNodeModules })
            let itemB = items.first(where: { $0.category == .devBuildArtifacts })
            
            XCTAssertNotNil(itemA)
            XCTAssertNotNil(itemB)
            XCTAssertTrue(itemA?.isRecent ?? false)
            XCTAssertFalse(itemB?.isRecent ?? true)
        }
    }
    
    func testInstallerScannerFiltersBySize() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "installer_test") { root in
            let dmgFile = root.appendingPathComponent("AppInstaller.dmg")
            let pkgFile = root.appendingPathComponent("Plugin.pkg")
            let smallZip = root.appendingPathComponent("small.zip")
            let largeZip = root.appendingPathComponent("LargeArchive.zip")
            
            // Create small dummy files
            try "dmg data".data(using: .utf8)?.write(to: dmgFile)
            try "pkg data".data(using: .utf8)?.write(to: pkgFile)
            try "small zip data".data(using: .utf8)?.write(to: smallZip)
            
            // Create 55MB large zip
            let largeData = Data(count: 55 * 1024 * 1024)
            try largeData.write(to: largeZip)
            
            let scanner = InstallerScanner()
            let items = await scanner.scan(customSearchDirectories: [root])
            
            let names = items.map { $0.name }
            XCTAssertTrue(names.contains("AppInstaller.dmg"))
            XCTAssertTrue(names.contains("Plugin.pkg"))
            XCTAssertTrue(names.contains("LargeArchive.zip"))
            XCTAssertFalse(names.contains("small.zip"), "Small zip (<50MB) should not be returned")
            
            for item in items {
                XCTAssertFalse(item.isSelected, "Item must be deselected by default")
            }
        }
    }
    
    func testClaudeCodeScannerDetectsWorktreesTranscriptsAndProtectsConfigs() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "claude_scan_test") { root in
            let projectRoots = root.appendingPathComponent("Projects")
            let claudeHome = root.appendingPathComponent("dot_claude")
            
            // 1. Create project with worktrees, preadopt backups, and protected configs
            let projectA = projectRoots.appendingPathComponent("ProjectA")
            let worktree1 = projectA.appendingPathComponent(".claude/worktrees/agent-worktree-abc")
            let projectSettings = projectA.appendingPathComponent(".claude/settings.json")
            let claudeMd = projectA.appendingPathComponent("CLAUDE.md")
            let preadoptBackup = projectRoots.appendingPathComponent("ProjectA.preadopt-20260813T170352Z")
            
            try FileManager.default.createDirectory(at: worktree1, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: preadoptBackup, withIntermediateDirectories: true)
            
            try "worktree code".data(using: .utf8)?.write(to: worktree1.appendingPathComponent("main.swift"))
            try "backup code".data(using: .utf8)?.write(to: preadoptBackup.appendingPathComponent("old.swift"))
            try "{\"allowedTools\":[]}".data(using: .utf8)?.write(to: projectSettings)
            try "# Claude Guidelines".data(using: .utf8)?.write(to: claudeMd)
            
            // 2. Create global ~/.claude structure with caches, telemetry, and protected configs
            let transcriptsDir = claudeHome.appendingPathComponent("projects/-Users-test-Projects-ProjectA")
            let pluginCacheDir = claudeHome.appendingPathComponent("plugins/cache")
            let telemetryDir = claudeHome.appendingPathComponent("telemetry")
            let globalSettings = claudeHome.appendingPathComponent("settings.json")
            let globalSettingsLocal = claudeHome.appendingPathComponent("settings.local.json")
            let installedPlugins = claudeHome.appendingPathComponent("plugins/installed_plugins.json")
            let agentsDir = claudeHome.appendingPathComponent("agents")
            let skillsDir = claudeHome.appendingPathComponent("skills")
            
            try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: pluginCacheDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: telemetryDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            
            try "session log data".data(using: .utf8)?.write(to: transcriptsDir.appendingPathComponent("session1.jsonl"))
            try "plugin cache tar".data(using: .utf8)?.write(to: pluginCacheDir.appendingPathComponent("plugin.tar.gz"))
            try "telemetry event".data(using: .utf8)?.write(to: telemetryDir.appendingPathComponent("events.log"))
            
            try "{\"apiKey\":\"secret\"}".data(using: .utf8)?.write(to: globalSettings)
            try "{\"theme\":\"dark\"}".data(using: .utf8)?.write(to: globalSettingsLocal)
            try "{\"plugins\":[]}".data(using: .utf8)?.write(to: installedPlugins)
            try "agent prompt".data(using: .utf8)?.write(to: agentsDir.appendingPathComponent("helper.md"))
            try "skill prompt".data(using: .utf8)?.write(to: skillsDir.appendingPathComponent("coder.md"))
            
            // 3. Execute scan
            let scanner = ClaudeCodeScanner()
            let items = await scanner.scan(
                projectRoots: [projectRoots],
                claudeHome: claudeHome
            )
            
            // 4. Assertions on detected categories
            let worktreeItem = items.first(where: { $0.category == .claudeWorktrees })
            let preadoptItem = items.first(where: { $0.category == .claudePreadoptBackups })
            let transcriptItem = items.first(where: { $0.category == .claudeSessionTranscripts })
            let pluginCacheItem = items.first(where: { $0.category == .claudePluginCache })
            let telemetryItem = items.first(where: { $0.category == .claudeTelemetry })
            
            XCTAssertNotNil(worktreeItem, "Should detect worktree")
            XCTAssertNotNil(preadoptItem, "Should detect preadopt backup")
            XCTAssertNotNil(transcriptItem, "Should detect session transcripts")
            XCTAssertNotNil(pluginCacheItem, "Should detect plugin cache")
            XCTAssertNotNil(telemetryItem, "Should detect telemetry")
            
            // 5. Assertions on safety & selection
            for item in items {
                XCTAssertFalse(item.isSelected, "Item must be deselected by default: \(item.name)")
                
                let lower = item.path.lowercased()
                XCTAssertFalse(lower.hasSuffix("settings.json"), "Must never include settings.json: \(item.path)")
                XCTAssertFalse(lower.hasSuffix("settings.local.json"), "Must never include settings.local.json: \(item.path)")
                XCTAssertFalse(lower.hasSuffix("installed_plugins.json"), "Must never include installed_plugins.json: \(item.path)")
                XCTAssertFalse(lower.hasSuffix("claude.md"), "Must never include CLAUDE.md: \(item.path)")
                XCTAssertFalse(lower.contains("/agents"), "Must never include agents: \(item.path)")
                XCTAssertFalse(lower.contains("/skills"), "Must never include skills: \(item.path)")
            }
        }
    }
    
    func testPhotoAppsScannerDetectsCachesAndProtectsMasterData() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "photo_scan_test") { root in
            let picturesDir = root.appendingPathComponent("Pictures")
            let cachesDir = root.appendingPathComponent("Caches")
            let appSupportDir = root.appendingPathComponent("Application Support")
            
            // 1. Setup Lightroom structures
            let lrDir = picturesDir.appendingPathComponent("Lightroom")
            let lrPreviews = lrDir.appendingPathComponent("Lightroom Catalog Previews.lrdata")
            let lrSmartPreviews = lrDir.appendingPathComponent("Lightroom Catalog Smart Previews.lrdata")
            let lrMasterCat = lrDir.appendingPathComponent("Lightroom Catalog.lrcat")
            let lrBackups = lrDir.appendingPathComponent("Backups/2026/Catalog.lrcat")
            
            try FileManager.default.createDirectory(at: lrPreviews, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: lrSmartPreviews, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: lrBackups.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            try "preview blob".data(using: .utf8)?.write(to: lrPreviews.appendingPathComponent("root-preview.db"))
            try "smart preview blob".data(using: .utf8)?.write(to: lrSmartPreviews.appendingPathComponent("smart.db"))
            try "CRITICAL MASTER LRCAT".data(using: .utf8)?.write(to: lrMasterCat)
            try "CRITICAL BACKUP LRCAT".data(using: .utf8)?.write(to: lrBackups)
            
            // 2. Setup Capture One structures
            let c1SessionCache = picturesDir.appendingPathComponent("ShootA/CaptureOne/Cache")
            let c1SessionSettings = picturesDir.appendingPathComponent("ShootA/CaptureOne/Settings140")
            let c1SessionDb = picturesDir.appendingPathComponent("ShootA/ShootA.cosessiondb")
            let c1CatalogCache = picturesDir.appendingPathComponent("Wedding.cocatalog/Cache")
            let c1CatalogDb = picturesDir.appendingPathComponent("Wedding.cocatalog/CaptureOne.cocatalogdb")
            
            try FileManager.default.createDirectory(at: c1SessionCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: c1SessionSettings, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: c1CatalogCache, withIntermediateDirectories: true)
            
            try "cop proxy".data(using: .utf8)?.write(to: c1SessionCache.appendingPathComponent("img001.cop"))
            try "cot thumb".data(using: .utf8)?.write(to: c1CatalogCache.appendingPathComponent("img002.cot"))
            try "CRITICAL EDIT SETTING".data(using: .utf8)?.write(to: c1SessionSettings.appendingPathComponent("img001.cos"))
            try "CRITICAL SESSION DB".data(using: .utf8)?.write(to: c1SessionDb)
            try "CRITICAL CATALOG DB".data(using: .utf8)?.write(to: c1CatalogDb)
            
            // 3. Setup Caches & AppSupport
            let acrCache = cachesDir.appendingPathComponent("Adobe Camera Raw 2")
            let psCache = cachesDir.appendingPathComponent("com.adobe.Photoshop")
            let c1AppCache = cachesDir.appendingPathComponent("com.captureone.captureone16")
            let c1ImageCore = appSupportDir.appendingPathComponent("Capture One/ImageCore")
            
            try FileManager.default.createDirectory(at: acrCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: psCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: c1AppCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: c1ImageCore, withIntermediateDirectories: true)
            
            try "acr cache".data(using: .utf8)?.write(to: acrCache.appendingPathComponent("cache.dat"))
            try "ps cache".data(using: .utf8)?.write(to: psCache.appendingPathComponent("ps.dat"))
            try "c1 app cache".data(using: .utf8)?.write(to: c1AppCache.appendingPathComponent("c1.dat"))
            try "opencl kernel".data(using: .utf8)?.write(to: c1ImageCore.appendingPathComponent("kernel.bin"))
            
            // 4. Scan
            let scanner = PhotoAppsScanner(runningChecker: NeverRunningAppChecker())
            let items = await scanner.scan(
                picturesRoots: [picturesDir],
                customCachesDirectory: cachesDir,
                customAppSupportDirectory: appSupportDir
            )
            
            // 5. Category assertions
            let lrPrevItem = items.first(where: { $0.category == .lightroomPreviews })
            let lrSmartItem = items.first(where: { $0.category == .lightroomSmartPreviews })
            let c1SessItem = items.first(where: { $0.category == .captureOneSessionCache })
            let c1CatItem = items.first(where: { $0.category == .captureOneCatalogCache })
            let psItem = items.first(where: { $0.category == .photoshopCache })
            let c1AppItem = items.first(where: { $0.category == .captureOneAppCache })
            
            XCTAssertNotNil(lrPrevItem, "Should detect Lightroom previews")
            XCTAssertNotNil(lrSmartItem, "Should detect Lightroom smart previews")
            XCTAssertNotNil(c1SessItem, "Should detect Capture One session cache")
            XCTAssertNotNil(c1CatItem, "Should detect Capture One catalog cache")
            XCTAssertNotNil(psItem, "Should detect Photoshop / ACR cache")
            XCTAssertNotNil(c1AppItem, "Should detect Capture One app cache")
            
            // 6. Strict Negative Safety Assertions
            for item in items {
                XCTAssertFalse(item.isSelected, "Item must be deselected by default: \(item.name)")
                
                let lower = item.path.lowercased()
                XCTAssertFalse(lower.hasSuffix(".lrcat"), "Must NEVER include .lrcat: \(item.path)")
                XCTAssertFalse(lower.hasSuffix(".lrcat-data"), "Must NEVER include .lrcat-data: \(item.path)")
                XCTAssertFalse(lower.contains("/backups"), "Must NEVER include Lightroom backups: \(item.path)")
                XCTAssertFalse(lower.hasSuffix(".cocatalogdb"), "Must NEVER include .cocatalogdb: \(item.path)")
                XCTAssertFalse(lower.hasSuffix(".cosessiondb"), "Must NEVER include .cosessiondb: \(item.path)")
                XCTAssertFalse(lower.contains("settings140"), "Must NEVER include Settings140: \(item.path)")
                XCTAssertFalse(lower.hasSuffix(".cos"), "Must NEVER include .cos adjustments: \(item.path)")
            }
        }
    }
    
    func testResolveScannerDefaultOptionsCompletesQuicklyWithoutScanningRoot() async throws {
        let scanner = ResolveScanner()
        let startTime = Date()
        
        let items = await scanner.scan { p in
            // Progress callback invoked
        }
        
        let duration = Date().timeIntervalSince(startTime)
        // Ensure the default scan takes well under 20 seconds (previously took hours because of "/")
        XCTAssertLessThan(duration, 20.0, "ResolveScanner default scan took too long: \(duration)s")
        
        for item in items {
            // Verify it never crawls system paths or root /
            XCTAssertFalse(item.path.hasPrefix("/System"), "Must not scan /System: \(item.path)")
            XCTAssertFalse(item.path.hasPrefix("/private"), "Must not scan /private: \(item.path)")
            XCTAssertFalse(item.path == "/", "Must not return root /")
            XCTAssertFalse(item.isSelected, "Items must be unselected by default")
        }
    }
    
    func testSystemCacheAndBrowserScannersCompleteInAcceptableTime() async throws {
        let sysScanner = SystemCacheScanner()
        let browserScanner = BrowserCacheScanner(runningChecker: NeverRunningAppChecker())
        let installerScanner = InstallerScanner()
        
        let t0 = Date()
        let sysItems = await sysScanner.scan()
        let sysDuration = Date().timeIntervalSince(t0)
        XCTAssertLessThan(sysDuration, 30.0, "SystemCacheScanner took too long: \(sysDuration)s")
        
        let t1 = Date()
        let browserItems = await browserScanner.scan()
        let browserDuration = Date().timeIntervalSince(t1)
        XCTAssertLessThan(browserDuration, 20.0, "BrowserCacheScanner took too long: \(browserDuration)s")
        
        let t2 = Date()
        let instItems = await installerScanner.scan()
        let instDuration = Date().timeIntervalSince(t2)
        XCTAssertLessThan(instDuration, 10.0, "InstallerScanner took too long: \(instDuration)s")
        
        for item in sysItems + browserItems + instItems {
            XCTAssertFalse(item.isSelected, "All items must be deselected by default")
        }
    }
    
    func testClaudeCodeScanner_splitTiers() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "claude_split_tiers") { root in
            let claudeHome = root.appendingPathComponent("dot_claude")
            let shellSnapshots = claudeHome.appendingPathComponent("shell-snapshots")
            let cacheDir = claudeHome.appendingPathComponent("cache")
            let backupsDir = claudeHome.appendingPathComponent("backups")
            let tasksDir = claudeHome.appendingPathComponent("tasks")
            let sessionDataDir = claudeHome.appendingPathComponent("session-data")
            
            try FileManager.default.createDirectory(at: shellSnapshots, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sessionDataDir, withIntermediateDirectories: true)
            
            try "snapshot".data(using: .utf8)?.write(to: shellSnapshots.appendingPathComponent("snap1"))
            try "cached data".data(using: .utf8)?.write(to: cacheDir.appendingPathComponent("data1"))
            try "backup".data(using: .utf8)?.write(to: backupsDir.appendingPathComponent("bak1"))
            try "task item".data(using: .utf8)?.write(to: tasksDir.appendingPathComponent("task1"))
            try "session data".data(using: .utf8)?.write(to: sessionDataDir.appendingPathComponent("sess1"))
            
            // 1. Idle (Claude NOT running)
            let idleScanner = ClaudeCodeScanner(processChecker: MockClaudeProcessChecker(isRunning: false))
            let idleItems = await idleScanner.scan(projectRoots: [], claudeHome: claudeHome)
            
            let snapItem = idleItems.first(where: { $0.url.lastPathComponent == "shell-snapshots" })
            let cItem = idleItems.first(where: { $0.url.lastPathComponent == "cache" })
            let bakItem = idleItems.first(where: { $0.url.lastPathComponent == "backups" })
            let taskItem = idleItems.first(where: { $0.url.lastPathComponent == "tasks" })
            let sessItem = idleItems.first(where: { $0.url.lastPathComponent == "session-data" })
            
            XCTAssertEqual(snapItem?.riskTier, .safe)
            XCTAssertEqual(cItem?.riskTier, .safe)
            XCTAssertEqual(bakItem?.riskTier, .blocked)
            XCTAssertEqual(taskItem?.riskTier, .destructive)
            XCTAssertEqual(sessItem?.riskTier, .destructive)
            
            // 2. Active (Claude IS running)
            let runningScanner = ClaudeCodeScanner(processChecker: MockClaudeProcessChecker(isRunning: true))
            let runningItems = await runningScanner.scan(projectRoots: [], claudeHome: claudeHome)
            
            let runningTaskItem = runningItems.first(where: { $0.url.lastPathComponent == "tasks" })
            let runningSessItem = runningItems.first(where: { $0.url.lastPathComponent == "session-data" })
            
            XCTAssertEqual(runningTaskItem?.riskTier, .blocked)
            XCTAssertEqual(runningSessItem?.riskTier, .blocked)
        }
    }
    
    func testClaudeCodeScanner_worktreeTiers() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "claude_worktree_tiers") { root in
            let projectRoots = root.appendingPathComponent("Projects")
            let project = projectRoots.appendingPathComponent("TestApp")
            let recentWorktree = project.appendingPathComponent(".claude/worktrees/recent-tree")
            let staleWorktree = project.appendingPathComponent(".claude/worktrees/stale-tree")
            
            try FileManager.default.createDirectory(at: recentWorktree, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staleWorktree, withIntermediateDirectories: true)
            
            try "recent code".data(using: .utf8)?.write(to: recentWorktree.appendingPathComponent("App.swift"))
            try "stale code".data(using: .utf8)?.write(to: staleWorktree.appendingPathComponent("App.swift"))
            
            let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
            try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: staleWorktree.path)
            
            let scanner = ClaudeCodeScanner(processChecker: MockClaudeProcessChecker(isRunning: false))
            let items = await scanner.scan(projectRoots: [projectRoots], claudeHome: root.appendingPathComponent("empty_claude"))
            
            let recentItem = items.first(where: { $0.name.contains("recent-tree") })
            let staleItem = items.first(where: { $0.name.contains("stale-tree") })
            
            XCTAssertEqual(recentItem?.riskTier, .blocked)
            XCTAssertEqual(staleItem?.riskTier, .destructive)
        }
    }
    
    func testDevArtefactScanner_globalCaches() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "dev_global_caches") { root in
            let uvCache = root.appendingPathComponent(".cache/uv")
            let npmCache = root.appendingPathComponent(".npm")
            let playwrightCache = root.appendingPathComponent("Library/Caches/ms-playwright")
            let pnpmLib = root.appendingPathComponent("Library/pnpm")
            let pnpmCache = root.appendingPathComponent("Library/Caches/pnpm")
            
            try FileManager.default.createDirectory(at: uvCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: playwrightCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: pnpmLib, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: pnpmCache, withIntermediateDirectories: true)
            
            try "uv wheel".data(using: .utf8)?.write(to: uvCache.appendingPathComponent("pkg.whl"))
            try "npm tarball".data(using: .utf8)?.write(to: npmCache.appendingPathComponent("pkg.tgz"))
            try "browser bin".data(using: .utf8)?.write(to: playwrightCache.appendingPathComponent("chromium"))
            try "pnpm hardlink".data(using: .utf8)?.write(to: pnpmLib.appendingPathComponent("store.db"))
            try "pnpm meta".data(using: .utf8)?.write(to: pnpmCache.appendingPathComponent("index.json"))
            
            let scanner = DevArtefactScanner()
            let items = await scanner.scan(
                projectRoots: [],
                includeXcodeDerivedData: false,
                includeGlobalCaches: true,
                customHomeDirectory: root
            )
            
            let uvItem = items.first(where: { $0.url.standardized.path == uvCache.standardized.path || $0.url.path.hasSuffix(".cache/uv") })
            let npmItem = items.first(where: { $0.url.standardized.path == npmCache.standardized.path || $0.url.path.hasSuffix(".npm") })
            let pwItem = items.first(where: { $0.url.standardized.path == playwrightCache.standardized.path || $0.url.path.hasSuffix("ms-playwright") })
            let pnpmLibItem = items.first(where: { $0.url.standardized.path == pnpmLib.standardized.path || $0.url.path.hasSuffix("Library/pnpm") })
            let pnpmCacheItem = items.first(where: { $0.url.standardized.path == pnpmCache.standardized.path || $0.url.path.hasSuffix("Library/Caches/pnpm") })
            
            XCTAssertEqual(uvItem?.riskTier, .rebuildCost)
            XCTAssertEqual(npmItem?.riskTier, .rebuildCost)
            XCTAssertEqual(pwItem?.riskTier, .rebuildCost)
            XCTAssertEqual(pnpmLibItem?.riskTier, .blocked)
            XCTAssertEqual(pnpmCacheItem?.riskTier, .blocked)
        }
    }
    
    @MainActor
    func testCleanupStateService_selectionRules() {
        // Temp cache directory: never load the user's real cleanup cache into test state.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupSelectionTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let service = CleanupStateService(customCacheDirectory: tempDir)
        
        let itemSafe = FileItem(
            url: URL(fileURLWithPath: "/tmp/safe.cache"),
            name: "Safe Item",
            sizeBytes: 100,
            modifiedDate: Date(),
            category: .systemQuickLook,
            riskTier: .safe
        )
        let itemRebuild = FileItem(
            url: URL(fileURLWithPath: "/tmp/rebuild.cache"),
            name: "Rebuild Item",
            sizeBytes: 200,
            modifiedDate: Date(),
            category: .devNodeModules,
            riskTier: .rebuildCost
        )
        let itemDestructive = FileItem(
            url: URL(fileURLWithPath: "/tmp/destructive.txt"),
            name: "Destructive Item",
            sizeBytes: 300,
            modifiedDate: Date(),
            category: .claudeSessionTranscripts,
            riskTier: .destructive
        )
        var itemBlocked = FileItem(
            url: URL(fileURLWithPath: "/tmp/blocked.db"),
            name: "Blocked Item",
            sizeBytes: 400,
            modifiedDate: Date(),
            category: .claudeSnapshotsAndTasks,
            riskTier: .blocked
        )
        
        // 1. Blocked item can never be selected
        itemBlocked.isSelected = true
        XCTAssertFalse(itemBlocked.isSelected)
        
        service.scannedItems = [itemSafe, itemRebuild, itemDestructive, itemBlocked]
        
        // 2. selectAllSafe() selects only .safe
        service.selectAllSafe()
        XCTAssertEqual(service.selectedCount, 1)
        XCTAssertEqual(service.totalReclaimableBytes, 100)
        XCTAssertFalse(service.hasSelectedDestructiveItems)
        
        // 3. select(tier: .rebuildCost)
        service.select(tier: .rebuildCost)
        XCTAssertEqual(service.selectedCount, 2)
        XCTAssertEqual(service.totalReclaimableBytes, 300)
        
        // 4. select(tier: .blocked) does nothing
        service.select(tier: .blocked)
        XCTAssertEqual(service.selectedCount, 2)
        
        // 5. select(tier: .destructive)
        service.select(tier: .destructive)
        XCTAssertEqual(service.selectedCount, 3)
        XCTAssertEqual(service.totalReclaimableBytes, 600)
        XCTAssertTrue(service.hasSelectedDestructiveItems)
        
        // 6. Risk Summaries
        let selectionSummary = service.selectionRiskSummary
        XCTAssertEqual(selectionSummary.safe, 100)
        XCTAssertEqual(selectionSummary.rebuild, 200)
        XCTAssertEqual(selectionSummary.destructive, 300)
        
        let totalSummary = service.totalRiskSummary
        XCTAssertEqual(totalSummary.safe, 100)
        XCTAssertEqual(totalSummary.rebuild, 200)
        XCTAssertEqual(totalSummary.destructive, 300)
        XCTAssertEqual(totalSummary.blocked, 400)
        
        // 7. deselectAll
        service.deselectAll()
        XCTAssertEqual(service.selectedCount, 0)
        XCTAssertEqual(service.totalReclaimableBytes, 0)
    }
    
    func testSafetyGate_userDataDenylist() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        let protectedPaths = [
            home.appendingPathComponent(".claude/backups"),
            home.appendingPathComponent(".claude/plans"),
            home.appendingPathComponent(".claude/scheduled-tasks"),
            home.appendingPathComponent(".claude/mcp-configs"),
            home.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/settings.local.json"),
            home.appendingPathComponent(".claude/history.jsonl"),
            home.appendingPathComponent("Library/pnpm"),
            home.appendingPathComponent("Library/Caches/pnpm")
        ]
        
        for url in protectedPaths {
            XCTAssertThrowsError(try SafetyGate.validateForTrash(url: url)) { error in
                guard case SafetyGateError.userDataProtected = error else {
                    XCTFail("Expected userDataProtected error for \(url.path), got \(error)")
                    return
                }
            }
        }
    }
    
    func testSafetyGate_batchSizeCap() throws {
        // Test that item cap and large batches are validated
        XCTAssertEqual(SafetyGate.maxBatchSizeBytes, 20 * 1024 * 1024 * 1024)
        
        // Exceeding item count cap throws itemCapExceeded
        let overCapURLs = (0...10_001).map { URL(fileURLWithPath: "/tmp/file\($0).tmp") }
        XCTAssertThrowsError(try SafetyGate.validateBatch(urls: overCapURLs, scanRoot: nil)) { error in
            guard case SafetyGateError.itemCapExceeded = error else {
                XCTFail("Expected itemCapExceeded error, got \(error)")
                return
            }
        }
    }
}

private struct MockClaudeProcessChecker: ClaudeProcessChecking {
    let isRunning: Bool
    func isClaudeCodeRunning() -> Bool {
        return isRunning
    }
}


// MARK: - Tier honesty regressions

extension ScannerTests {
    /// `dist`, `build` and `target` are ordinary words. Without a project manifest
    /// beside them they are somebody's data, not build output.
    func testDevArtefactScannerRequiresProjectMarkerForAmbiguousFolders() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "dev_marker_test") { root in
            let fileManager = FileManager.default

            // Real project: dist next to a package.json
            let realProject = root.appendingPathComponent("RealProject")
            try fileManager.createDirectory(at: realProject.appendingPathComponent("dist"), withIntermediateDirectories: true)
            try "{}".data(using: .utf8)?.write(to: realProject.appendingPathComponent("package.json"))
            try "bundle".data(using: .utf8)?.write(to: realProject.appendingPathComponent("dist/app.js"))

            // Not a project: a folder that merely happens to be called build
            let notAProject = root.appendingPathComponent("Renovation")
            try fileManager.createDirectory(at: notAProject.appendingPathComponent("build"), withIntermediateDirectories: true)
            try "plans".data(using: .utf8)?.write(to: notAProject.appendingPathComponent("build/plans.txt"))

            let items = await DevArtefactScanner().scan(
                projectRoots: [root],
                includeXcodeDerivedData: false,
                includeGlobalCaches: false
            )

            let paths = items.map { $0.url.lastPathComponent }
            XCTAssertTrue(paths.contains("dist"), "A dist folder beside package.json is build output")
            XCTAssertFalse(paths.contains("build"), "A build folder without any project manifest must not be offered")
        }
    }

    /// The Claude plugin cache is what installed plugins execute from, so clearing it
    /// costs a re-download and breaks hooks in the meantime.
    func testClaudePluginCacheIsNotTieredSafe() {
        XCTAssertEqual(CleanupCategory.claudePluginCache.defaultTier, .rebuildCost)
    }

    /// Persistent memory is not a transcript: a project holding one is offered file by
    /// file, with the memory directory left out of the results entirely.
    func testClaudeScannerExcludesPersistentMemoryFromTranscripts() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "claude_memory_test") { root in
            let fileManager = FileManager.default
            let projectDir = root.appendingPathComponent("projects/-Users-someone-project")
            let memoryDir = projectDir.appendingPathComponent("memory")
            try fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
            try "transcript".data(using: .utf8)?.write(to: projectDir.appendingPathComponent("session.jsonl"))
            try "remembered".data(using: .utf8)?.write(to: memoryDir.appendingPathComponent("MEMORY.md"))

            let items = await ClaudeCodeScanner().scan(projectRoots: [], claudeHome: root)
            let transcripts = items.filter { $0.category == .claudeSessionTranscripts }

            XCTAssertFalse(transcripts.isEmpty, "The session transcript should still be offered")
            for item in transcripts {
                XCTAssertFalse(
                    item.url.pathComponents.contains("memory"),
                    "Persistent memory must never appear in the cleanup results: \(item.url.path)"
                )
            }
        }
    }

    /// An item whose timestamp moved since the scan is left alone: a path is not an
    /// identity, and results can be served from a snapshot that is days old.
    func testStaleItemsAreSkippedByFreshnessCheck() throws {
        let fileManager = FileManager.default
        let fileURL = fileManager.temporaryDirectory.appendingPathComponent("stale_\(UUID().uuidString).cache")
        try "first".data(using: .utf8)?.write(to: fileURL)
        defer { try? fileManager.removeItem(at: fileURL) }

        let scannedDate = (try fileURL.resourceValues(forKeys: [.contentModificationDateKey])).contentModificationDate!
        let item = FileItem(
            url: fileURL,
            sizeBytes: 5,
            modifiedDate: scannedDate,
            category: .systemUserCaches,
            riskTier: .safe
        )
        XCTAssertTrue(CleanupStateService.isUnchangedSinceScan(item))

        try fileManager.setAttributes([.modificationDate: scannedDate.addingTimeInterval(600)], ofItemAtPath: fileURL.path)
        XCTAssertFalse(CleanupStateService.isUnchangedSinceScan(item), "A rewritten item must not be trashed on a stale reading")

        try fileManager.removeItem(at: fileURL)
        XCTAssertFalse(CleanupStateService.isUnchangedSinceScan(item))
    }
}

/// Reports every application as running, to exercise the guard that refuses a cache
/// while its owner might still be writing to it.
private struct AlwaysRunningAppChecker: RunningAppChecking {
    func isRunning(bundleIdentifiers: [String], names: [String]) -> Bool { true }
}

extension ScannerTests {
    /// Clearing a browser cache under an open browser can corrupt the profile, and
    /// the space is reclaimed just as well one quit later.
    func testBrowserCachesAreBlockedWhileTheBrowserRuns() async throws {
        try await TestFixtures.withTempDirectoryAsync(prefix: "browser_running_test") { root in
            let fileManager = FileManager.default
            let caches = root.appendingPathComponent("Caches")
            let safariCache = caches.appendingPathComponent("com.apple.Safari")
            try fileManager.createDirectory(at: safariCache, withIntermediateDirectories: true)
            try Data(count: 4096).write(to: safariCache.appendingPathComponent("cache.db"))

            let blockedItems = await BrowserCacheScanner(runningChecker: AlwaysRunningAppChecker()).scan(
                customCachesDirectory: caches,
                customAppSupportDirectory: root.appendingPathComponent("Application Support"),
                customContainersDirectory: root.appendingPathComponent("Containers")
            )
            XCTAssertFalse(blockedItems.isEmpty)
            for item in blockedItems {
                XCTAssertEqual(item.riskTier, .blocked, "\(item.name) must be blocked while its browser runs")
                XCTAssertFalse(item.isSelected)
            }

            let freeItems = await BrowserCacheScanner(runningChecker: NeverRunningAppChecker()).scan(
                customCachesDirectory: caches,
                customAppSupportDirectory: root.appendingPathComponent("Application Support"),
                customContainersDirectory: root.appendingPathComponent("Containers")
            )
            XCTAssertEqual(freeItems.first?.riskTier, .safe)
        }
    }
}
