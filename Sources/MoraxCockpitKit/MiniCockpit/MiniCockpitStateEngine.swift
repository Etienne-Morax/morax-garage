import Foundation
import SwiftUI
import Observation

/// Représentation synthétique de l'état de santé global du Mac pour le Mini Cockpit.
public enum MiniCockpitHealthState: String, Sendable, CaseIterable, Identifiable, Equatable {
    case normal = "NORMAL"
    case loaded = "CHARGÉ"
    case saturated = "SATURÉ"
    case unavailable = "INDISPONIBLE"
    
    public var id: String { rawValue }
    
    public var label: String { rawValue }
    
    public var color: Color {
        switch self {
        case .normal:
            return MoraxTheme.successGreen
        case .loaded:
            return MoraxTheme.warningAmber
        case .saturated:
            return MoraxTheme.oxbloodRed
        case .unavailable:
            return MoraxTheme.textMuted
        }
    }
    
    public func color(isDark: Bool) -> Color {
        if isDark {
            return self.color
        } else {
            switch self {
            case .normal:
                return Color(hex: "#059669") // Deep Emerald for light mode
            case .loaded:
                return Color(hex: "#D97706") // Deep Amber for light mode
            case .saturated:
                return Color(hex: "#DC2626") // Deep Crimson for light mode
            case .unavailable:
                return Color(hex: "#64748B") // Slate gray for light mode
            }
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .normal:
            return "checkmark.shield.fill"
        case .loaded:
            return "exclamationmark.triangle.fill"
        case .saturated:
            return "flame.fill"
        case .unavailable:
            return "questionmark.circle.fill"
        }
    }
    
    public var accessibilityDescription: String {
        switch self {
        case .normal:
            return "État système normal. CPU, GPU et mémoire dans les plages optimales."
        case .loaded:
            return "Système chargé. CPU, GPU ou mémoire sous contrainte soutenue."
        case .saturated:
            return "Système saturé. Forte contrainte CPU, GPU, mémoire ou swap détectée."
        case .unavailable:
            return "Télémétrie indisponible."
        }
    }
}

/// Buffer circulaire ultra-léger à capacité fixe pour tracer l'historique CPU / GPU sans allocation continue.
public struct MiniSparklineBuffer: Sendable, Equatable {
    public let capacity: Int
    private var buffer: [Double]
    
    public init(capacity: Int = 30) {
        self.capacity = max(2, capacity)
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }
    
    public var count: Int {
        buffer.count
    }
    
    public var isEmpty: Bool {
        buffer.isEmpty
    }
    
    public var values: [Double] {
        buffer
    }
    
    public mutating func push(_ value: Double) {
        let clamped = min(1.0, max(0.0, value))
        if buffer.count >= capacity {
            buffer.removeFirst()
        }
        buffer.append(clamped)
    }
    
    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}

/// Moteur d'évaluation avec hystérésis et rejet des pics transitoires (CPU, GPU, RAM, Swap).
public struct MiniCockpitEvaluator: Sendable {
    private var cpuHistory: [Double] = []
    private var gpuHistory: [Double] = []
    private var currentHealth: MiniCockpitHealthState = .normal
    
    // Paramètres configurables et testables
    public let cpuLoadedThreshold: Double
    public let cpuSaturatedThreshold: Double
    public let cpuRecoveryThreshold: Double
    public let gpuLoadedThreshold: Double
    public let gpuSaturatedThreshold: Double
    public let gpuRecoveryThreshold: Double
    public let requiredSamplesForEscalation: Int
    public let requiredSamplesForRecovery: Int
    public let swapThresholdBytes: Int64
    
    public init(
        cpuLoadedThreshold: Double = 0.75,
        cpuSaturatedThreshold: Double = 0.90,
        cpuRecoveryThreshold: Double = 0.65,
        gpuLoadedThreshold: Double = 0.75,
        gpuSaturatedThreshold: Double = 0.90,
        gpuRecoveryThreshold: Double = 0.65,
        requiredSamplesForEscalation: Int = 3,
        requiredSamplesForRecovery: Int = 2,
        swapThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024 // 2 Go
    ) {
        self.cpuLoadedThreshold = cpuLoadedThreshold
        self.cpuSaturatedThreshold = cpuSaturatedThreshold
        self.cpuRecoveryThreshold = cpuRecoveryThreshold
        self.gpuLoadedThreshold = gpuLoadedThreshold
        self.gpuSaturatedThreshold = gpuSaturatedThreshold
        self.gpuRecoveryThreshold = gpuRecoveryThreshold
        self.requiredSamplesForEscalation = requiredSamplesForEscalation
        self.requiredSamplesForRecovery = requiredSamplesForRecovery
        self.swapThresholdBytes = swapThresholdBytes
    }
    
    public var state: MiniCockpitHealthState {
        currentHealth
    }
    
    public mutating func reset() {
        cpuHistory.removeAll()
        gpuHistory.removeAll()
        currentHealth = .normal
    }
    
    /// Évalue un snapshot et met à jour l'état interne en appliquant l'hystérésis.
    public mutating func evaluate(snapshot: SystemSnapshot) -> MiniCockpitHealthState {
        // 1. Vérification de la disponibilité de la télémétrie
        if snapshot.status.isUnavailable || snapshot.status.isError {
            currentHealth = .unavailable
            return .unavailable
        }
        
        // 2. Mise à jour des historiques CPU et GPU
        cpuHistory.append(snapshot.cpuUsage)
        if cpuHistory.count > 10 {
            cpuHistory.removeFirst()
        }
        
        gpuHistory.append(snapshot.gpuUsage)
        if gpuHistory.count > 10 {
            gpuHistory.removeFirst()
        }
        
        let recentCpuSamples = Array(cpuHistory.suffix(requiredSamplesForEscalation))
        let recoveryCpuSamples = Array(cpuHistory.suffix(requiredSamplesForRecovery))
        
        let recentGpuSamples = Array(gpuHistory.suffix(requiredSamplesForEscalation))
        let recoveryGpuSamples = Array(gpuHistory.suffix(requiredSamplesForRecovery))
        
        let isCpuSaturatedSustained = recentCpuSamples.count >= requiredSamplesForEscalation &&
            recentCpuSamples.allSatisfy { $0 >= cpuSaturatedThreshold }
        
        let isCpuLoadedSustained = recentCpuSamples.count >= requiredSamplesForEscalation &&
            recentCpuSamples.allSatisfy { $0 >= cpuLoadedThreshold }
        
        let isGpuSaturatedSustained = recentGpuSamples.count >= requiredSamplesForEscalation &&
            recentGpuSamples.allSatisfy { $0 >= gpuSaturatedThreshold }
        
        let isGpuLoadedSustained = recentGpuSamples.count >= requiredSamplesForEscalation &&
            recentGpuSamples.allSatisfy { $0 >= gpuLoadedThreshold }
        
        let isCpuRecovered = recoveryCpuSamples.count >= requiredSamplesForRecovery &&
            recoveryCpuSamples.allSatisfy { $0 < cpuRecoveryThreshold }
        
        let isGpuRecovered = recoveryGpuSamples.count >= requiredSamplesForRecovery &&
            recoveryGpuSamples.allSatisfy { $0 < gpuRecoveryThreshold }
        
        let pressure = snapshot.memoryPressure
        let isSwapHigh = snapshot.swapUsed > swapThresholdBytes
        
        // 3. Détermination de la cible brute de cet échantillon
        var candidateState: MiniCockpitHealthState = .normal
        
        if pressure == .critical || (isSwapHigh && pressure == .warning) || isCpuSaturatedSustained || isGpuSaturatedSustained {
            candidateState = .saturated
        } else if pressure == .warning || isSwapHigh || isCpuLoadedSustained || isGpuLoadedSustained {
            candidateState = .loaded
        } else {
            candidateState = .normal
        }
        
        // 4. Application de l'hystérésis d'escalade / désescalade
        switch currentHealth {
        case .unavailable:
            currentHealth = candidateState
            
        case .normal:
            if candidateState == .saturated {
                currentHealth = .saturated
            } else if candidateState == .loaded {
                currentHealth = .loaded
            }
            
        case .loaded:
            if candidateState == .saturated {
                currentHealth = .saturated
            } else if candidateState == .normal {
                // Pour redescendre à normal, il faut une confirmation de récupération CPU et GPU
                if isCpuRecovered && isGpuRecovered && pressure != .warning && pressure != .critical && !isSwapHigh {
                    currentHealth = .normal
                }
            }
            
        case .saturated:
            if candidateState == .loaded {
                // Redescend à loaded si plus de pression critique ni saturation soutenue
                if !isCpuSaturatedSustained && !isGpuSaturatedSustained && pressure != .critical {
                    currentHealth = .loaded
                }
            } else if candidateState == .normal {
                if isCpuRecovered && isGpuRecovered && pressure == .normal && !isSwapHigh {
                    currentHealth = .normal
                } else if !isCpuSaturatedSustained && !isGpuSaturatedSustained && pressure != .critical {
                    currentHealth = .loaded
                }
            }
        }
        
        return currentHealth
    }
}

/// Modes d'affichage et de réduction du Mini Cockpit HUD.
public enum MiniCockpitDisplayMode: String, Sendable, CaseIterable, Identifiable, Equatable {
    case compact = "COMPACT"     // Réduit : Header + 3 Jauges (CPU, GPU, RAM)
    case standard = "STANDARD"   // Normal : Header + 3 Jauges + Top Apps + Compteurs IA
    case expanded = "DÉTAILLÉ"   // Déplié : + Graphiques Historiques CPU/GPU + Swap/Temp + Ouvrir Garage
    
    public var id: String { rawValue }
    
    public var targetHeight: CGFloat {
        switch self {
        case .compact:
            return 86
        case .standard:
            return 178
        case .expanded:
            return 286
        }
    }
    
    /// Feeds the HUD actually renders in this mode. Compact shows only the CPU, GPU
    /// and RAM gauges and the health badge, all derived from the system sample;
    /// standard and expanded add the top apps (`ps`) and the AI counters.
    public var telemetryFeeds: Set<TelemetryFeed> {
        switch self {
        case .compact:
            return [.system]
        case .standard, .expanded:
            return [.system, .process, .usage, .openAICosts]
        }
    }
}

/// Modèle Observable gérant l'état et les données du Mini Cockpit avec suppression des redraws inutiles.
@Observable
@MainActor
public final class MiniCockpitStore {
    public static let shared = MiniCockpitStore()
    
    public private(set) var currentSnapshot: SystemSnapshot = SystemSnapshot()
    public private(set) var processSnapshot: ProcessSnapshot = ProcessSnapshot()
    public private(set) var healthState: MiniCockpitHealthState = .normal
    public private(set) var cpuSparkline: MiniSparklineBuffer = MiniSparklineBuffer(capacity: 30)
    public private(set) var gpuSparkline: MiniSparklineBuffer = MiniSparklineBuffer(capacity: 30)
    
    public var displayMode: MiniCockpitDisplayMode = .standard {
        didSet {
            syncTelemetryDemand()
            MiniCockpitWindowController.shared.updatePanelHeight(to: displayMode.targetHeight, animate: true)
        }
    }
    
    public var isExpanded: Bool {
        get { displayMode == .expanded }
        set { displayMode = newValue ? .expanded : .standard }
    }
    
    public var isCompact: Bool {
        get { displayMode == .compact }
        set { displayMode = newValue ? .compact : .standard }
    }
    
    public var isVisible: Bool = false {
        didSet {
            syncTelemetryDemand()
        }
    }
    
    private var evaluator = MiniCockpitEvaluator()
    private var lastObservedCpuInt: Int = -1
    private var lastObservedGpuInt: Int = -1
    private var lastObservedRamMB: Int64 = -1
    private var lastObservedSwapMB: Int64 = -1
    /// Timestamp of the last system sample fed to the evaluator and the sparklines,
    /// so a sample read twice is counted once.
    private var lastSystemSampleTimestamp: Date?
    /// Bumped on every start/stop so a change callback armed by a previous
    /// session cannot re-arm observation after the HUD was hidden or restarted.
    private var observationGeneration: Int = 0
    /// Where the HUD declares the feeds it needs. Tests inject an isolated
    /// coordinator so starting the store never launches the real shared feeds.
    private let telemetryCoordinator: TelemetryCoordinator
    
    public init(telemetryCoordinator: TelemetryCoordinator? = nil) {
        self.telemetryCoordinator = telemetryCoordinator ?? .shared
        // Initialisation baseline
        let initial = SystemMetricsService.shared.currentSnapshot
        self.currentSnapshot = initial
        self.healthState = evaluator.evaluate(snapshot: initial)
        self.cpuSparkline.push(initial.cpuUsage)
        self.gpuSparkline.push(initial.gpuUsage)
        self.lastSystemSampleTimestamp = initial.timestamp
    }
    
    public func start() {
        guard !isVisible else { return }
        isVisible = true
        syncTelemetryDemand()
        observationGeneration += 1
        observeSources(generation: observationGeneration)
    }
    
    public func stop() {
        isVisible = false
        syncTelemetryDemand()
        observationGeneration += 1
    }
    
    public func toggleExpanded() {
        if displayMode == .expanded {
            displayMode = .standard
        } else {
            displayMode = .expanded
        }
    }
    
    public func toggleCompact() {
        if displayMode == .compact {
            displayMode = .standard
        } else {
            displayMode = .compact
        }
    }
    
    public func updateMetrics(system: SystemSnapshot, process: ProcessSnapshot) {
        // Change detection pour éviter les invalidations SwiftUI inutiles :
        // Redraw uniquement si CPU change de >= 1%, GPU change de >= 1%, RAM change de >= 50Mo, Swap change de >= 100Mo, ou si l'état change
        let currentCpuInt = Int((system.cpuUsage * 100).rounded())
        let currentGpuInt = Int((system.gpuUsage * 100).rounded())
        let currentRamMB = system.ramUsed / (1024 * 1024)
        let currentSwapMB = system.swapUsed / (1024 * 1024)
        // Re-reading a sample (e.g. when only the process list was published) must not
        // feed the hysteresis twice nor add a duplicate sparkline point.
        let isNewSystemSample = system.timestamp != lastSystemSampleTimestamp
        let newHealth = isNewSystemSample ? evaluator.evaluate(snapshot: system) : healthState
        
        let hasCpuChanged = currentCpuInt != lastObservedCpuInt
        let hasGpuChanged = currentGpuInt != lastObservedGpuInt
        let hasRamChanged = abs(currentRamMB - lastObservedRamMB) >= 50
        let hasSwapChanged = abs(currentSwapMB - lastObservedSwapMB) >= 100
        let hasHealthChanged = newHealth != healthState
        // The process timestamp changes on every `ps` pass even when the lists are identical.
        let hasProcessChanged = !Self.hasSameProcessContent(process, processSnapshot)
        
        if hasCpuChanged || hasGpuChanged || hasRamChanged || hasSwapChanged || hasHealthChanged || hasProcessChanged {
            self.currentSnapshot = system
            self.processSnapshot = process
            self.healthState = newHealth
            
            self.lastObservedCpuInt = currentCpuInt
            self.lastObservedGpuInt = currentGpuInt
            self.lastObservedRamMB = currentRamMB
            self.lastObservedSwapMB = currentSwapMB
        }
        
        if isNewSystemSample {
            self.cpuSparkline.push(system.cpuUsage)
            self.gpuSparkline.push(system.gpuUsage)
            self.lastSystemSampleTimestamp = system.timestamp
        }
    }
    
    private static func hasSameProcessContent(_ lhs: ProcessSnapshot, _ rhs: ProcessSnapshot) -> Bool {
        lhs.topCpuApps == rhs.topCpuApps
            && lhs.topRamApps == rhs.topRamApps
            && lhs.topGpuApps == rhs.topGpuApps
            && lhs.totalRamBytes == rhs.totalRamBytes
            && lhs.status == rhs.status
            && lhs.gpuStatus == rhs.gpuStatus
    }
    
    /// Retourne les 2 principales applications consommatrices identifiées (Top GPU / CPU).
    public var topMonitoredApps: [ProcessResourceUsage] {
        // On sélectionne en priorité les 2 premières applications de CPU/charge active
        let apps = processSnapshot.topCpuApps
        if apps.count >= 2 {
            return Array(apps.prefix(2))
        }
        return apps
    }
    
    private func syncTelemetryDemand() {
        guard isVisible else {
            telemetryCoordinator.release(TelemetryConsumer.miniCockpit)
            telemetryCoordinator.release(TelemetryConsumer.miniCockpitDetail)
            return
        }
        
        telemetryCoordinator.acquire(TelemetryConsumer.miniCockpit, feeds: displayMode.telemetryFeeds)
        telemetryCoordinator.release(TelemetryConsumer.miniCockpitDetail)
    }
    
    /// Reads the telemetry snapshots and re-arms itself when either one is published,
    /// so the HUD follows the source cadence instead of waking the main actor on a timer.
    private func observeSources(generation: Int) {
        guard isVisible, generation == observationGeneration else { return }
        let (system, process) = withObservationTracking {
            (SystemMetricsService.shared.currentSnapshot, ProcessMetricsService.shared.currentSnapshot)
        } onChange: { [weak self] in
            // `onChange` fires before the new value is stored: hop so the read sees it.
            Task { @MainActor [weak self] in
                self?.observeSources(generation: generation)
            }
        }
        updateMetrics(system: system, process: process)
    }
}
