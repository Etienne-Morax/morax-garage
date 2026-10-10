import Foundation

public enum DiagnosticCategory: String, Codable, Sendable {
    case memory
    case process
    case thermal
    case storage
    case availability
}

public enum DiagnosticSeverity: String, Codable, Sendable, Comparable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum DiagnosticConfidence: String, Codable, Sendable {
    case insufficientData
    case low
    case medium
    case high
}

public enum DiagnosticAction: String, Codable, Sendable {
    case inspect
    case showDetails
    case openStorageMap
    case reviewApplications
    case none
}

public struct DiagnosticFinding: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let category: DiagnosticCategory
    public let severity: DiagnosticSeverity
    public let title: String
    public let explanation: String
    public let evidence: [String]
    public let recommendation: String
    public let actions: [DiagnosticAction]
    public let confidence: DiagnosticConfidence
    public let timestamp: Date
    public let isActionable: Bool

    public init(
        id: String,
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        title: String,
        explanation: String,
        evidence: [String],
        recommendation: String,
        actions: [DiagnosticAction],
        confidence: DiagnosticConfidence,
        timestamp: Date,
        isActionable: Bool
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.recommendation = recommendation
        self.actions = actions
        self.confidence = confidence
        self.timestamp = timestamp
        self.isActionable = isActionable
    }
}

public enum MemoryPressureState: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

public struct DiagnosticInput: Sendable {
    public let now: Date
    public let memoryPressure: MemoryPressureState?
    public let currentSystem: SystemSnapshot?
    public let previousSystem: SystemSnapshot?
    public let currentProcesses: ProcessSnapshot?
    public let previousProcesses: ProcessSnapshot?
    public let cacheSnapshot: CacheSnapshot?
    public let processBaselines: [String: HistoryStatistics]
    public let cacheBaselines: [String: HistoryStatistics]

    public init(
        now: Date = Date(),
        memoryPressure: MemoryPressureState? = nil,
        currentSystem: SystemSnapshot? = nil,
        previousSystem: SystemSnapshot? = nil,
        currentProcesses: ProcessSnapshot? = nil,
        previousProcesses: ProcessSnapshot? = nil,
        cacheSnapshot: CacheSnapshot? = nil,
        processBaselines: [String: HistoryStatistics] = [:],
        cacheBaselines: [String: HistoryStatistics] = [:]
    ) {
        self.now = now
        self.memoryPressure = memoryPressure
        self.currentSystem = currentSystem
        self.previousSystem = previousSystem
        self.currentProcesses = currentProcesses
        self.previousProcesses = previousProcesses
        self.cacheSnapshot = cacheSnapshot
        self.processBaselines = processBaselines
        self.cacheBaselines = cacheBaselines
    }
}

/// Deterministic, read-only rules for turning available telemetry into explanations.
/// Missing telemetry produces no claim; it never becomes a zero-valued alert.
public struct DiagnosticEngine: Sendable {
    public static let sustainedProcessInterval: TimeInterval = 60
    public static let sustainedCpuThreshold = 80.0

    public init() {}

    public func evaluate(_ input: DiagnosticInput) -> [DiagnosticFinding] {
        var findings: [DiagnosticFinding] = []
        if let pressure = input.memoryPressure {
            findings.append(contentsOf: memoryFindings(pressure: pressure, input: input))
        }
        if let processFinding = sustainedProcessFinding(input) {
            findings.append(processFinding)
        }
        findings.append(contentsOf: unusualProcessMemoryFindings(input))
        findings.append(contentsOf: growingCacheFindings(input))
        if let thermalFinding = sustainedThermalFinding(input) {
            findings.append(thermalFinding)
        }
        return findings.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.id < $1.id
        }
    }

    private func unusualProcessMemoryFindings(_ input: DiagnosticInput) -> [DiagnosticFinding] {
        guard let current = input.currentProcesses else { return [] }
        return current.topRamApps.compactMap { process in
            let identity = process.bundlePath?.lowercased() ?? process.name.lowercased()
            guard let baseline = input.processBaselines[identity], baseline.count >= 5,
                  let average = baseline.average, average > 0,
                  Double(process.ramBytes) >= average * 1.75 else { return nil }
            let percentIncrease = Int(((Double(process.ramBytes) - average) / average) * 100)
            let avgFormatted = ByteCountFormatter.string(fromByteCount: Int64(average), countStyle: .memory)
            return DiagnosticFinding(
                id: "process.memory.baseline.\(identity)",
                category: .process,
                severity: .warning,
                title: "\(process.name) : hausse de mémoire RAM (\(process.formattedRam))",
                explanation: "Utilise \(process.formattedRam) de RAM (moyenne observée : \(avgFormatted), hausse de +\(percentIncrease)%).",
                evidence: [
                    "Application : \(process.name)",
                    "Mémoire actuelle : \(process.formattedRam)",
                    "Moyenne récente (24h) : \(avgFormatted)",
                    "Augmentation observée : +\(percentIncrease)%",
                    "Échantillons : \(baseline.count)"
                ],
                recommendation: "Inspectez l'application dans la section Applications ou fermez les tâches lourdes inutilisées.",
                actions: [.reviewApplications, .showDetails],
                confidence: baseline.count >= 12 ? .high : .medium,
                timestamp: input.now,
                isActionable: false
            )
        }
    }

    private func growingCacheFindings(_ input: DiagnosticInput) -> [DiagnosticFinding] {
        guard let cache = input.cacheSnapshot else { return [] }
        let categories: [(String, String, Int64)] = [
            ("resolve", "DaVinci Resolve", cache.resolveSizeBytes),
            ("lightroom", "Lightroom", cache.lightroomSizeBytes),
            ("photoshop", "Photoshop", cache.photoshopSizeBytes),
            ("captureOne", "Capture One", cache.captureOneSizeBytes),
            ("browsers", "Navigateurs", cache.browsersSizeBytes),
            ("system", "Système", cache.systemSizeBytes)
        ]
        return categories.compactMap { key, name, current in
            guard let baseline = input.cacheBaselines[key], baseline.count >= 2,
                  let first = baseline.average, let delta = baseline.delta,
                  delta >= 1_000_000_000, Double(current) > first * 1.25 else { return nil }
            let deltaFormatted = ByteCountFormatter.string(fromByteCount: Int64(delta), countStyle: .file)
            let currentFormatted = ByteCountFormatter.string(fromByteCount: current, countStyle: .file)
            return DiagnosticFinding(
                id: "cache.growth.\(key)",
                category: .storage,
                severity: .info,
                title: "Cache \(name) : forte augmentation (+\(deltaFormatted))",
                explanation: "Le volume du cache atteint \(currentFormatted) (hausse de +\(deltaFormatted) sur les 30 derniers jours).",
                evidence: [
                    "Catégorie : \(name)",
                    "Taille actuelle : \(currentFormatted)",
                    "Hausse observée : +\(deltaFormatted)",
                    "Échantillons : \(baseline.count)"
                ],
                recommendation: "Consultez la carte de stockage ou la section Nettoyage pour gérer les caches volumineux.",
                actions: [.openStorageMap, .showDetails],
                confidence: baseline.count >= 4 ? .high : .medium,
                timestamp: input.now,
                isActionable: false
            )
        }
    }

    private func memoryFindings(pressure: MemoryPressureState, input: DiagnosticInput) -> [DiagnosticFinding] {
        if let system = input.currentSystem, system.ramTotal > 0,
           (system.ramUsed < 0 || system.ramUsed > system.ramTotal) { return [] }
        switch pressure {
        case .normal:
            return []
        case .warning:
            guard input.previousSystem?.memoryPressure == .warning || input.previousSystem?.memoryPressure == .critical else {
                return []
            }
            fallthrough
        case .critical:
            let severity: DiagnosticSeverity = pressure == .critical ? .critical : .warning
            let title = pressure == .critical ? "Pression mémoire macOS : Critique" : "Pression mémoire macOS : Élevée"
            let explanation = "Le système signale une saturation de la mémoire vive."
            let evidence: [String] = {
                if let sys = input.currentSystem {
                    let usedFormatted = ByteCountFormatter.string(fromByteCount: sys.ramUsed, countStyle: .memory)
                    let totFormatted = ByteCountFormatter.string(fromByteCount: sys.ramTotal, countStyle: .memory)
                    return [
                        "Niveau de pression système : \(pressure.rawValue)",
                        "RAM occupée : \(usedFormatted) sur \(totFormatted)"
                    ]
                }
                return ["Niveau de pression système : \(pressure.rawValue)"]
            }()
            return [DiagnosticFinding(
                id: "memory.pressure.\(pressure.rawValue)",
                category: .memory,
                severity: severity,
                title: title,
                explanation: explanation,
                evidence: evidence,
                recommendation: "Inspectez les applications les plus gourmandes en RAM pour libérer de la mémoire.",
                actions: [.reviewApplications, .showDetails],
                confidence: .high,
                timestamp: input.now,
                isActionable: true
            )]
        }
    }

    private func sustainedProcessFinding(_ input: DiagnosticInput) -> DiagnosticFinding? {
        guard let current = input.currentProcesses,
              let previous = input.previousProcesses,
              current.timestamp.timeIntervalSince(previous.timestamp) >= Self.sustainedProcessInterval,
              let process = current.topCpuApps.first(where: { $0.cpuPercent >= Self.sustainedCpuThreshold }),
              let earlier = previous.topCpuApps.first(where: { $0.id == process.id }) else { return nil }
        guard earlier.cpuPercent >= Self.sustainedCpuThreshold else { return nil }

        let durationSeconds = Int(current.timestamp.timeIntervalSince(previous.timestamp))
        return DiagnosticFinding(
            id: "process.cpu.sustained.\(process.id)",
            category: .process,
            severity: .warning,
            title: "\(process.name) : charge CPU élevée continue (\(String(format: "%.0f", process.cpuPercent))%)",
            explanation: "L'application maintient une charge CPU de \(String(format: "%.1f", process.cpuPercent))% depuis plus de \(durationSeconds)s.",
            evidence: [
                "Application : \(process.name)",
                "Charge CPU actuelle : \(String(format: "%.1f", process.cpuPercent))%",
                "Charge précédente : \(String(format: "%.1f", earlier.cpuPercent))%",
                "Durée observée : \(durationSeconds) secondes"
            ],
            recommendation: "Inspectez les processus actifs dans l'onglet Applications pour voir la charge détaillée.",
            actions: [.reviewApplications, .showDetails],
            confidence: .medium,
            timestamp: input.now,
            isActionable: false
        )
    }

    private func sustainedThermalFinding(_ input: DiagnosticInput) -> DiagnosticFinding? {
        guard let current = input.currentSystem,
              let previous = input.previousSystem,
              let currentTemp = current.cpuTemp,
              let previousTemp = previous.cpuTemp,
              current.cpuUsage >= 85,
              currentTemp >= 90,
              previousTemp >= 90,
              current.timestamp.timeIntervalSince(previous.timestamp) >= Self.sustainedProcessInterval else { return nil }

        return DiagnosticFinding(
            id: "thermal.cpu.sustained",
            category: .thermal,
            severity: .warning,
            title: "Température CPU élevée (\(String(format: "%.0f", currentTemp))°C)",
            explanation: "Forte activité CPU (\(String(format: "%.0f", current.cpuUsage))%) et température prolongée à \(String(format: "%.1f", currentTemp))°C.",
            evidence: [
                "Charge CPU : \(String(format: "%.1f", current.cpuUsage))%",
                "Température actuelle : \(String(format: "%.1f", currentTemp))°C",
                "Température précédente : \(String(format: "%.1f", previousTemp))°C"
            ],
            recommendation: "Vérifiez la ventilation et les tâches en arrière-plan consommant du processeur.",
            actions: [.showDetails],
            confidence: .medium,
            timestamp: input.now,
            isActionable: false
        )
    }
}
