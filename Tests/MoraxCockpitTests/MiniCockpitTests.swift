import XCTest
import SwiftUI
@testable import MoraxCockpitKit

final class MiniCockpitTests: XCTestCase {
    
    // MARK: - 1. MiniSparklineBuffer Tests
    
    func testSparklineBufferCapacityAndFifo() {
        var buffer = MiniSparklineBuffer(capacity: 5)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        
        buffer.push(0.1)
        buffer.push(0.2)
        buffer.push(0.3)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.values, [0.1, 0.2, 0.3])
        
        buffer.push(0.4)
        buffer.push(0.5)
        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.values, [0.1, 0.2, 0.3, 0.4, 0.5])
        
        // Push beyond capacity: should drop oldest 0.1
        buffer.push(0.6)
        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.values, [0.2, 0.3, 0.4, 0.5, 0.6])
        
        // Push another: should drop 0.2
        buffer.push(0.7)
        XCTAssertEqual(buffer.values, [0.3, 0.4, 0.5, 0.6, 0.7])
    }
    
    func testSparklineBufferClamping() {
        var buffer = MiniSparklineBuffer(capacity: 3)
        buffer.push(-0.5) // Below 0.0 -> clamp to 0.0
        buffer.push(1.5)  // Above 1.0 -> clamp to 1.0
        buffer.push(0.5)
        
        XCTAssertEqual(buffer.values, [0.0, 1.0, 0.5])
    }
    
    func testSparklineBufferReset() {
        var buffer = MiniSparklineBuffer(capacity: 4)
        buffer.push(0.2)
        buffer.push(0.8)
        XCTAssertFalse(buffer.isEmpty)
        
        buffer.reset()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
    }
    
    // MARK: - 2. MiniCockpitEvaluator & Hysteresis Tests
    
    func testEvaluatorInitialStateIsNormal() {
        var evaluator = MiniCockpitEvaluator()
        let normalSnapshot = SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.15,
            gpuUsage: 0.10,
            swapUsed: 0,
            memoryPressure: .normal
        )
        
        let state = evaluator.evaluate(snapshot: normalSnapshot)
        XCTAssertEqual(state, .normal)
        XCTAssertEqual(state.label, "NORMAL")
    }
    
    func testEvaluatorRejectsSingleTransientSpike() {
        var evaluator = MiniCockpitEvaluator()
        
        // 1. Initial normal baseline
        _ = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.20,
            gpuUsage: 0.10,
            swapUsed: 0,
            memoryPressure: .normal
        ))
        XCTAssertEqual(evaluator.state, .normal)
        
        // 2. Single 100% CPU spike (500ms momentary load)
        let spikeState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 1.0,
            gpuUsage: 0.10,
            swapUsed: 0,
            memoryPressure: .normal
        ))
        
        // MUST NOT trigger LOADED or SATURATED on a single spike
        XCTAssertEqual(spikeState, .normal, "A single transient CPU spike must not trigger an alert")
        
        // 3. Single 100% GPU spike
        let gpuSpikeState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.20,
            gpuUsage: 1.0,
            swapUsed: 0,
            memoryPressure: .normal
        ))
        XCTAssertEqual(gpuSpikeState, .normal, "A single transient GPU spike must not trigger an alert")
        
        // 4. Recovery
        let recoveredState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.25,
            gpuUsage: 0.15,
            swapUsed: 0,
            memoryPressure: .normal
        ))
        XCTAssertEqual(recoveredState, .normal)
    }
    
    func testEvaluatorSustainedCpuTriggersLoadedAndSaturated() {
        var evaluator = MiniCockpitEvaluator(
            cpuLoadedThreshold: 0.75,
            cpuSaturatedThreshold: 0.90,
            requiredSamplesForEscalation: 3
        )
        
        // Sample 1: 80% (high, but only 1 sample)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.80, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .normal)
        
        // Sample 2: 82% (2 samples)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.82, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .normal)
        
        // Sample 3: 85% (3 samples -> sustained loaded)
        let loadedState = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.85, memoryPressure: .normal))
        XCTAssertEqual(loadedState, .loaded, "3 consecutive samples >= 75% must trigger CHARGÉ")
        
        // Sample 4: 95% (sample 1 of saturated)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.95, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded)
        
        // Sample 5: 96% (sample 2 of saturated)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.96, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded)
        
        // Sample 6: 98% (sample 3 of saturated -> escalation to SATURÉ)
        let satState = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.98, memoryPressure: .normal))
        XCTAssertEqual(satState, .saturated, "3 consecutive samples >= 90% must trigger SATURÉ")
    }
    
    func testEvaluatorSustainedGpuTriggersLoadedAndSaturated() {
        var evaluator = MiniCockpitEvaluator(
            gpuLoadedThreshold: 0.75,
            gpuSaturatedThreshold: 0.90,
            gpuRecoveryThreshold: 0.65,
            requiredSamplesForEscalation: 3,
            requiredSamplesForRecovery: 2
        )
        
        // Sample 1: 80% GPU
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.80, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .normal)
        
        // Sample 2: 82% GPU
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.82, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .normal)
        
        // Sample 3: 85% GPU -> CHARGÉ
        let loadedState = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.85, memoryPressure: .normal))
        XCTAssertEqual(loadedState, .loaded, "3 consecutive GPU samples >= 75% must trigger CHARGÉ")
        
        // Sample 4: 95% GPU
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.95, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded)
        
        // Sample 5: 96% GPU
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.96, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded)
        
        // Sample 6: 98% GPU -> SATURÉ
        let satState = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.98, memoryPressure: .normal))
        XCTAssertEqual(satState, .saturated, "3 consecutive GPU samples >= 90% must trigger SATURÉ")
        
        // Recovery test: 2 samples below 65%
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.40, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded, "Requires 2 recovery samples")
        
        let recState = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.20, gpuUsage: 0.35, memoryPressure: .normal))
        XCTAssertEqual(recState, .normal, "Must return to NORMAL after 2 low GPU samples")
    }
    
    func testEvaluatorHysteresisRecovery() {
        var evaluator = MiniCockpitEvaluator(
            cpuLoadedThreshold: 0.75,
            cpuRecoveryThreshold: 0.65,
            requiredSamplesForEscalation: 3,
            requiredSamplesForRecovery: 2
        )
        
        // Trigger loaded state (3 samples at 80%)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.80, memoryPressure: .normal))
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.80, memoryPressure: .normal))
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.80, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded)
        
        // Drop to 70%: Below 75% loaded threshold, but NOT below 65% recovery threshold (Hysteresis deadband)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.70, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded, "Must remain CHARGÉ within hysteresis deadband")
        
        // Sample 1 below recovery threshold (50%)
        _ = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.50, memoryPressure: .normal))
        XCTAssertEqual(evaluator.state, .loaded, "Requires 2 recovery samples to return to NORMAL")
        
        // Sample 2 below recovery threshold (45%)
        let recoveredState = evaluator.evaluate(snapshot: SystemSnapshot(status: .live(source: "macmon"), cpuUsage: 0.45, memoryPressure: .normal))
        XCTAssertEqual(recoveredState, .normal, "Must return to NORMAL after 2 confirmed low samples")
    }
    
    func testEvaluatorMemoryPressureTriggers() {
        var evaluator = MiniCockpitEvaluator()
        
        // Warning pressure -> Loaded
        let warningState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.10,
            memoryPressure: .warning
        ))
        XCTAssertEqual(warningState, .loaded)
        
        // Critical pressure -> Saturated
        let criticalState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.10,
            memoryPressure: .critical
        ))
        XCTAssertEqual(criticalState, .saturated)
    }
    
    func testEvaluatorSwapTriggers() {
        var evaluator = MiniCockpitEvaluator(swapThresholdBytes: 2 * 1024 * 1024 * 1024)
        
        // Swap > 2GB with normal pressure -> Loaded
        let loadedSwapState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.10,
            swapUsed: 3 * 1024 * 1024 * 1024, // 3 GB
            memoryPressure: .normal
        ))
        XCTAssertEqual(loadedSwapState, .loaded)
        
        // Swap > 2GB with warning pressure -> Saturated
        let saturatedSwapState = evaluator.evaluate(snapshot: SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.10,
            swapUsed: 3 * 1024 * 1024 * 1024, // 3 GB
            memoryPressure: .warning
        ))
        XCTAssertEqual(saturatedSwapState, .saturated)
    }
    
    func testEvaluatorHandlesUnavailableTelemetrySafely() {
        var evaluator = MiniCockpitEvaluator()
        
        let unavailSnapshot = SystemSnapshot(
            status: .unavailable(reason: "Monitoring offline"),
            cpuUsage: 0.0,
            gpuUsage: 0.0,
            memoryPressure: nil
        )
        
        let state = evaluator.evaluate(snapshot: unavailSnapshot)
        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(state.label, "INDISPONIBLE")
    }
    
    // MARK: - 3. MiniCockpitStore Lifecycle & GPU Buffers Tests
    
    @MainActor
    func testMiniCockpitDisplayModesAndPanelResizing() {
        let store = MiniCockpitStore.shared
        
        // Standard mode default
        store.displayMode = .standard
        XCTAssertEqual(store.displayMode, .standard)
        XCTAssertFalse(store.isCompact)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(MiniCockpitDisplayMode.standard.targetHeight, 178)
        
        // Switch to Compact (True reduced window)
        store.toggleCompact()
        XCTAssertEqual(store.displayMode, .compact)
        XCTAssertTrue(store.isCompact)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(MiniCockpitDisplayMode.compact.targetHeight, 86)
        
        // Switch to Expanded
        store.toggleExpanded()
        XCTAssertEqual(store.displayMode, .expanded)
        XCTAssertFalse(store.isCompact)
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(MiniCockpitDisplayMode.expanded.targetHeight, 286)
        
        // Toggle back to standard
        store.toggleExpanded()
        XCTAssertEqual(store.displayMode, .standard)
        
        // Test controller resizing does not crash
        let controller = MiniCockpitWindowController.shared
        controller.updatePanelHeight(to: 86, animate: false)
        controller.updatePanelHeight(to: 178, animate: false)
    }
    
    @MainActor
    func testMiniCockpitTrioGaugesInstantiation() {
        let store = MiniCockpitStore.shared
        let snapshot = SystemSnapshot(
            status: .live(source: "macmon"),
            cpuUsage: 0.25,
            gpuUsage: 0.50,
            eCoreCount: 4,
            pCoreCount: 6,
            ramTotal: 32 * 1024 * 1024 * 1024,
            ramUsed: 16 * 1024 * 1024 * 1024
        )
        store.updateMetrics(system: snapshot, process: ProcessSnapshot())
        
        let cpuTile = MiniMetricTile(
            iconName: "cpu",
            title: "CPU",
            valueText: "25%",
            fraction: 0.25,
            secondaryText: "10 Coeurs",
            accentColor: .cyan,
            isDarkMode: true,
            gaugeType: .arc()
        )
        XCTAssertNotNil(cpuTile)
        
        let gpuTile = MiniMetricTile(
            iconName: "gauge.with.dots.needle.bottom.50percent",
            title: "GPU",
            valueText: "50%",
            fraction: 0.50,
            secondaryText: "Actif",
            accentColor: .blue,
            isDarkMode: true,
            gaugeType: .arc()
        )
        XCTAssertNotNil(gpuTile)
        
        let ramTile = MiniMetricTile(
            iconName: "memorychip",
            title: "RAM",
            valueText: "50%",
            fraction: 0.50,
            secondaryText: "16.0 Go",
            accentColor: .purple,
            isDarkMode: true,
            gaugeType: .arc()
        )
        XCTAssertNotNil(ramTile)
    }
    
    @MainActor
    func testMiniCockpitStoreLifecycle() {
        // An isolated coordinator without controls: starting the store must not
        // launch the real shared feeds (macmon, ps, Keychain-backed pollers).
        let store = MiniCockpitStore(telemetryCoordinator: TelemetryCoordinator(controls: [:], stopGracePeriod: 0))
        store.isExpanded = false
        XCTAssertNotNil(store.currentSnapshot)
        XCTAssertNotNil(store.healthState)
        XCTAssertNotNil(store.gpuSparkline)
        XCTAssertNotNil(store.cpuSparkline)
        
        store.start()
        XCTAssertTrue(store.isVisible)
        
        store.toggleExpanded()
        XCTAssertTrue(store.isExpanded)
        
        store.toggleExpanded()
        XCTAssertFalse(store.isExpanded)
        
        store.stop()
        XCTAssertFalse(store.isVisible)
    }
    
    @MainActor
    func testMiniCockpitStoreTopMonitoredAppsResolution() {
        let store = MiniCockpitStore.shared
        
        let app1 = ProcessResourceUsage(name: "DaVinci Resolve", bundlePath: "/Applications/DaVinci Resolve/DaVinci Resolve.app", cpuPercent: 45.2, ramBytes: 4 * 1024 * 1024 * 1024)
        let app2 = ProcessResourceUsage(name: "Adobe Lightroom", bundlePath: "/Applications/Adobe Lightroom.app", cpuPercent: 28.6, ramBytes: 2 * 1024 * 1024 * 1024)
        let app3 = ProcessResourceUsage(name: "Xcode", bundlePath: "/Applications/Xcode.app", cpuPercent: 12.1, ramBytes: 1 * 1024 * 1024 * 1024)
        
        let snapshot = ProcessSnapshot(
            timestamp: Date(),
            topCpuApps: [app1, app2, app3],
            topRamApps: [app1, app2, app3],
            status: .active
        )
        
        store.updateMetrics(system: store.currentSnapshot, process: snapshot)
        let topApps = store.topMonitoredApps
        XCTAssertEqual(topApps.count, 2)
        XCTAssertEqual(topApps.first?.name, "DaVinci Resolve")
        XCTAssertEqual(topApps.last?.name, "Adobe Lightroom")
    }
    
    // MARK: - 4. Geometric Placement & Preferences Tests
    
    @MainActor
    func testWindowPlacementDefaultCoordinates() {
        let controller = MiniCockpitWindowController.shared
        XCTAssertFalse(controller.isVisible)
        
        // Validate repositioning does not crash with null panel or multi-screen setups
        controller.validateAndRepositionIfNeeded(nil)
    }
    
    @MainActor
    func testAppSettingsMiniCockpitProperties() {
        let settings = AppSettings.shared
        let originalEnabled = settings.miniCockpitEnabled
        let originalAlwaysOnTop = settings.miniCockpitAlwaysOnTop
        let originalAllSpaces = settings.miniCockpitAllSpaces
        
        settings.miniCockpitEnabled = true
        XCTAssertTrue(settings.miniCockpitEnabled)
        
        settings.miniCockpitAlwaysOnTop = false
        XCTAssertFalse(settings.miniCockpitAlwaysOnTop)
        
        settings.miniCockpitAllSpaces = false
        XCTAssertFalse(settings.miniCockpitAllSpaces)
        
        // Restore
        settings.miniCockpitEnabled = originalEnabled
        settings.miniCockpitAlwaysOnTop = originalAlwaysOnTop
        settings.miniCockpitAllSpaces = originalAllSpaces
    }
    
    @MainActor
    func testAppAppearanceModeAndThemeAdaptations() {
        let settings = AppSettings.shared
        let originalAppearance = settings.miniCockpitAppearance
        
        settings.miniCockpitAppearance = .dark
        XCTAssertEqual(settings.miniCockpitAppearance, .dark)
        XCTAssertEqual(settings.miniCockpitAppearance.colorScheme, .dark)
        XCTAssertEqual(settings.miniCockpitAppearance.iconName, "moon.stars.fill")
        
        settings.miniCockpitAppearance = .light
        XCTAssertEqual(settings.miniCockpitAppearance, .light)
        XCTAssertEqual(settings.miniCockpitAppearance.colorScheme, .light)
        XCTAssertEqual(settings.miniCockpitAppearance.iconName, "sun.max.fill")
        
        settings.miniCockpitAppearance = .system
        XCTAssertEqual(settings.miniCockpitAppearance, .system)
        XCTAssertNil(settings.miniCockpitAppearance.colorScheme)
        XCTAssertEqual(settings.miniCockpitAppearance.iconName, "circle.lefthalf.filled")
        
        // Test health state dark / light colors
        let normalDarkColor = MiniCockpitHealthState.normal.color(isDark: true)
        let normalLightColor = MiniCockpitHealthState.normal.color(isDark: false)
        XCTAssertNotNil(normalDarkColor)
        XCTAssertNotNil(normalLightColor)
        
        // Restore
        settings.miniCockpitAppearance = originalAppearance
    }
    
    // MARK: - 5. AI Counters Resolution & Telemetry Tests
    
    func testResolveMiniAICounterItemsWithFullSnapshot() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let claudeWindow = QuotaWindow(
            windowMinutes: 300, label: "5 heures", usedPercent: 42, remainingPercent: 58,
            resetsAt: now.addingTimeInterval(3_600), observedAt: now, tone: .ok,
            resetLabel: "reset dans 1 h", resetAtLabel: "12:00"
        )
        let claudeGauge = ProviderQuotaGauge(
            provider: "claude", label: "Claude Max", planType: "Max",
            windows: [claudeWindow], worst: claudeWindow, outer: claudeWindow, inner: nil,
            tone: .ok, observedAt: now, stale: false, observedLabel: "à l'instant"
        )
        
        let gptWindow = QuotaWindow(
            windowMinutes: 180, label: "3 heures", usedPercent: 88, remainingPercent: 12,
            resetsAt: now.addingTimeInterval(1_800), observedAt: now, tone: .warn,
            resetLabel: "reset dans 30 min", resetAtLabel: "11:30"
        )
        let gptGauge = ProviderQuotaGauge(
            provider: "openai-codex", label: "ChatGPT Plus", planType: "Plus",
            windows: [gptWindow], worst: gptWindow, outer: gptWindow, inner: nil,
            tone: .warn, observedAt: now, stale: false, observedLabel: "à l'instant"
        )
        
        let geminiWindow = QuotaWindow(
            windowMinutes: 1440, label: "1 jour", usedPercent: 15, remainingPercent: 85,
            resetsAt: now.addingTimeInterval(43_200), observedAt: now, tone: .ok,
            resetLabel: "reset dans 12 h", resetAtLabel: "22:00"
        )
        let geminiGauge = ProviderQuotaGauge(
            provider: "antigravity", label: "Gemini Advanced", planType: "Advanced",
            windows: [geminiWindow], worst: geminiWindow, outer: geminiWindow, inner: nil,
            tone: .ok, observedAt: now, stale: false, observedLabel: "à l'instant"
        )
        
        let openAiSpend = PaidApiSpend(
            provider: "openai", label: "OpenAI API", costUsd: 2.5, calls: 14, totalTokens: 8500,
            since: now.addingTimeInterval(-86_400), latestAt: now, balanceUsd: 17.5,
            balanceCurrency: "USD", balanceObservedAt: now, balanceAvailable: true,
            balanceSpendUsd: 1.8, balanceSpendSince: now.addingTimeInterval(-86_400)
        )
        
        let snapshot = UsageQuotaSnapshot(
            ok: true,
            capturedAt: now,
            gauges: [claudeGauge, gptGauge, geminiGauge],
            paidApiMonthToDate: [openAiSpend]
        )
        
        let items = MiniAICounterItem.resolveItems(from: snapshot, at: now)
        XCTAssertEqual(items.count, 4)
        
        // Claude
        let claude = items.first(where: { $0.id == "claude" })
        XCTAssertNotNil(claude)
        XCTAssertEqual(claude?.name, "Claude")
        XCTAssertEqual(claude?.usedPercent, 42)
        XCTAssertEqual(claude?.tone, .ok)
        XCTAssertEqual(claude?.resetLabel, "reset dans 1 h")
        XCTAssertTrue(claude?.hasData == true)
        
        // ChatGPT
        let gpt = items.first(where: { $0.id == "chatgpt" })
        XCTAssertNotNil(gpt)
        XCTAssertEqual(gpt?.name, "ChatGPT")
        XCTAssertEqual(gpt?.usedPercent, 88)
        XCTAssertEqual(gpt?.tone, .warn)
        XCTAssertTrue(gpt?.hasData == true)
        
        // Gemini
        let gemini = items.first(where: { $0.id == "gemini" })
        XCTAssertNotNil(gemini)
        XCTAssertEqual(gemini?.name, "Gemini")
        XCTAssertEqual(gemini?.usedPercent, 15)
        XCTAssertEqual(gemini?.tone, .ok)
        XCTAssertTrue(gemini?.hasData == true)
        
        // OpenAI API (remplace Grok)
        XCTAssertFalse(items.contains(where: { $0.id == "grok" }))
        let openai = items.first(where: { $0.id == "openai" })
        XCTAssertNotNil(openai)
        XCTAssertEqual(openai?.name, "OpenAI API")
        XCTAssertEqual(openai?.shortName, "OpenAI")
        XCTAssertEqual(openai?.spendAmount, 1.8)
        XCTAssertEqual(openai?.spendCurrency, "USD")
        XCTAssertEqual(openai?.tone, .ok)
        XCTAssertTrue(openai?.hasData == true)
    }
    
    func testResolveMiniAICounterItemsWithEmptySnapshot() {
        let items = MiniAICounterItem.resolveItems(from: nil)
        XCTAssertEqual(items.count, 4)
        for item in items {
            XCTAssertFalse(item.hasData)
            XCTAssertNil(item.usedPercent)
            XCTAssertNil(item.spendAmount)
            XCTAssertNil(item.resetLabel)
        }
    }
    
    @MainActor
    func testMiniAICounterCardInstantiationAndReadability() {
        let planItem = MiniAICounterItem(
            id: "claude",
            name: "Claude",
            shortName: "Claude",
            usedPercent: 42,
            spendAmount: nil,
            spendCurrency: nil,
            tone: .ok,
            resetLabel: "reset dans 1 h",
            planType: "Max",
            isStale: false,
            hasData: true
        )
        let planCard = MiniAICounterCard(item: planItem, isDarkMode: true)
        XCTAssertNotNil(planCard.body)
        
        let emptyItem = MiniAICounterItem(
            id: "openai",
            name: "OpenAI API",
            shortName: "OpenAI",
            usedPercent: nil,
            spendAmount: nil,
            spendCurrency: nil,
            tone: .ok,
            resetLabel: nil,
            planType: nil,
            isStale: false,
            hasData: false
        )
        let emptyCard = MiniAICounterCard(item: emptyItem, isDarkMode: false)
        XCTAssertNotNil(emptyCard.body)
    }
    
    @MainActor
    func testMiniCockpitAcquiresUsageFeed() {
        let coordinator = TelemetryCoordinator(controls: [:], stopGracePeriod: 0)
        let store = MiniCockpitStore(telemetryCoordinator: coordinator)
        store.isExpanded = false
        
        store.start()
        XCTAssertTrue(coordinator.requestedFeeds.contains(.usage), "Mini Cockpit must acquire .usage feed")
        XCTAssertTrue(coordinator.requestedFeeds.contains(.system), "Mini Cockpit must acquire .system feed")
        XCTAssertTrue(coordinator.requestedFeeds.contains(.process), "Mini Cockpit must acquire .process feed")
        
        store.toggleExpanded()
        XCTAssertTrue(coordinator.requestedFeeds.contains(.usage))
        XCTAssertTrue(coordinator.requestedFeeds.contains(.process))
        
        store.isExpanded = false
        store.stop()
    }

    @MainActor
    func testShowingWithoutCallbackKeepsTheRegisteredOpenMainWindowAction() {
        let controller = MiniCockpitWindowController.shared
        var openCount = 0
        controller.registerOpenMainWindowCallback { openCount += 1 }

        // What `showMiniCockpit()` does when a caller passes no callback.
        controller.registerOpenMainWindowCallback(nil)
        controller.openMainWindow()

        XCTAssertEqual(openCount, 1)
    }

    func testCompactModeRequestsOnlyTheSystemFeed() {
        XCTAssertEqual(MiniCockpitDisplayMode.compact.telemetryFeeds, [.system])
    }

    func testStandardAndExpandedModesRequestTopAppsAndAICounterFeeds() {
        let displayedFeeds: Set<TelemetryFeed> = [.system, .process, .usage, .openAICosts]
        XCTAssertEqual(MiniCockpitDisplayMode.standard.telemetryFeeds, displayedFeeds)
        XCTAssertEqual(MiniCockpitDisplayMode.expanded.telemetryFeeds, displayedFeeds)
    }

    // MARK: - 6. Native GPU Sampler & GPU Gauge Tests
    
    func testNativeGpuSamplerDoesNotCrashAndReturnsClampedValue() {
        let sample = NativeGpuSampler.sampleGpuUsage()
        if let val = sample {
            XCTAssertGreaterThanOrEqual(val, 0.0)
            XCTAssertLessThanOrEqual(val, 1.0)
        }
    }
    
    func testGpuUsageNormalization() {
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(0.0), 0.0)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(0.5), 0.5)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(1.0), 1.0)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(75.0), 0.75) // Percentage -> ratio
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(-10.0), 0.0)
        XCTAssertEqual(MacmonSample.normalizeUsageRatio(150.0), 1.0)
    }
}
