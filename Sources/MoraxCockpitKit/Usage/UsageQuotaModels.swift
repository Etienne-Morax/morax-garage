import Foundation

public enum QuotaTone: String, Codable, Equatable, Sendable {
    case ok
    case warn
    case critical
}

public struct QuotaWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { windowMinutes }
    public let windowMinutes: Int
    public let label: String
    public let shortLabel: String?
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let observedAt: Date?
    public let tone: QuotaTone
    public let resetLabel: String
    public let resetInLabel: String?
    public let resetAtLabel: String

    public init(windowMinutes: Int, label: String, shortLabel: String? = nil, usedPercent: Double, remainingPercent: Double,
                resetsAt: Date?, observedAt: Date?, tone: QuotaTone, resetLabel: String,
                resetInLabel: String? = nil, resetAtLabel: String) {
        self.windowMinutes = windowMinutes
        self.label = label
        self.shortLabel = shortLabel
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.tone = tone
        self.resetLabel = resetLabel
        self.resetInLabel = resetInLabel
        self.resetAtLabel = resetAtLabel
    }
}

public struct ProviderQuotaGauge: Codable, Equatable, Sendable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let label: String
    public let planType: String?
    public let windows: [QuotaWindow]
    public let worst: QuotaWindow
    public let outer: QuotaWindow
    public let inner: QuotaWindow?
    public let tone: QuotaTone
    public let observedAt: Date?
    public let stale: Bool
    public let observedLabel: String

    public init(provider: String, label: String, planType: String?, windows: [QuotaWindow],
                worst: QuotaWindow, outer: QuotaWindow, inner: QuotaWindow?, tone: QuotaTone,
                observedAt: Date?, stale: Bool, observedLabel: String) {
        self.provider = provider
        self.label = label
        self.planType = planType
        self.windows = windows
        self.worst = worst
        self.outer = outer
        self.inner = inner
        self.tone = tone
        self.observedAt = observedAt
        self.stale = stale
        self.observedLabel = observedLabel
    }
}

public struct PaidApiSpend: Codable, Equatable, Sendable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let label: String
    public let costUsd: Double
    public let calls: Int
    public let totalTokens: Int
    public let since: Date
    public let latestAt: Date?
    public let balanceUsd: Double?
    public let balanceCurrency: String?
    public let balanceObservedAt: Date?
    public let balanceAvailable: Bool?
    public let balanceSpendUsd: Double?
    public let balanceSpendSince: Date?

    public init(provider: String, label: String, costUsd: Double, calls: Int, totalTokens: Int,
                since: Date, latestAt: Date?, balanceUsd: Double?, balanceCurrency: String?,
                balanceObservedAt: Date?, balanceAvailable: Bool?, balanceSpendUsd: Double?,
                balanceSpendSince: Date?) {
        self.provider = provider
        self.label = label
        self.costUsd = costUsd
        self.calls = calls
        self.totalTokens = totalTokens
        self.since = since
        self.latestAt = latestAt
        self.balanceUsd = balanceUsd
        self.balanceCurrency = balanceCurrency
        self.balanceObservedAt = balanceObservedAt
        self.balanceAvailable = balanceAvailable
        self.balanceSpendUsd = balanceSpendUsd
        self.balanceSpendSince = balanceSpendSince
    }
}

public struct UsageQuotaSnapshot: Codable, Equatable, Sendable {
    /// Copied from morax-os `gauges.ts`; the client re-evaluates freshness only.
    public static let staleAfterMinutes: TimeInterval = 120
    /// Copied from morax-os `gauges.ts`; a closed reset invalidates its measurement.
    public static let resetOverdueMinutes: TimeInterval = 20
    public let ok: Bool
    public let capturedAt: Date
    public let gauges: [ProviderQuotaGauge]
    public let paidApiMonthToDate: [PaidApiSpend]

    public init(ok: Bool, capturedAt: Date, gauges: [ProviderQuotaGauge], paidApiMonthToDate: [PaidApiSpend]) {
        self.ok = ok
        self.capturedAt = capturedAt
        self.gauges = gauges
        self.paidApiMonthToDate = paidApiMonthToDate
    }

    /// Mirrors the cockpit's STALE_AFTER_MINUTES and RESET_OVERDUE_MINUTES rules locally.
    /// Percentages and tones remain server-owned; only freshness is re-evaluated here.
    public func isLocallyStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(capturedAt) > Self.staleAfterMinutes * 60 || gauges.contains { $0.hasOverdueReset(at: now) }
    }

    public func localObservedLabel(at now: Date = Date()) -> String {
        LocalUsageDateLabel.relative(from: capturedAt, to: now)
    }
}

public extension ProviderQuotaGauge {
    func hasOverdueReset(at now: Date) -> Bool {
        windows.contains { $0.hasOverdueReset(at: now) }
    }

    func isLocallyStale(snapshot: UsageQuotaSnapshot, at now: Date) -> Bool {
        snapshot.isLocallyStale(at: now) || hasOverdueReset(at: now)
    }
}

public extension QuotaWindow {
    func hasOverdueReset(at now: Date) -> Bool {
        guard let resetsAt, now.timeIntervalSince(resetsAt) > UsageQuotaSnapshot.resetOverdueMinutes * 60 else { return false }
        return true
    }

    /// Relative reset labels are server-time labels and must not be replayed after expiry.
    func localResetLabel(snapshotIsStale: Bool, at now: Date) -> String {
        snapshotIsStale || hasOverdueReset(at: now) ? "" : resetLabel
    }

    var displayShortLabel: String {
        if let shortLabel, !shortLabel.isEmpty {
            return shortLabel.uppercased()
        }
        if windowMinutes >= 43_200 { return "MONTH" }
        if windowMinutes >= 10_080 { return "WEEK" }
        if windowMinutes >= 1_440 { return "\(Int(round(Double(windowMinutes) / 1440.0)))D" }
        if windowMinutes >= 60 { return "\(Int(round(Double(windowMinutes) / 60.0)))H" }
        return "\(max(1, windowMinutes))M"
    }

    func localResetInLabel(snapshotIsStale: Bool, at now: Date) -> String {
        if snapshotIsStale || hasOverdueReset(at: now) {
            return ""
        }
        if let resetInLabel, !resetInLabel.isEmpty {
            return resetInLabel
        }
        guard let resetsAt else { return "—" }
        let delta = resetsAt.timeIntervalSince(now)
        if delta <= 0 { return "attendu" }
        let seconds = max(0, delta)
        let minutes = Int(round(seconds / 60.0))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = Int(round(Double(minutes) / 60.0))
        if hours < 48 { return "in \(hours) h" }
        let days = Int(round(Double(hours) / 24.0))
        return "in \(days) j"
    }

    var displayResetAtLabel: String {
        if !resetAtLabel.isEmpty { return resetAtLabel }
        guard let resetsAt else { return "heure inconnue" }
        return Self.resetDateFormatter.string(from: resetsAt)
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()
}

private enum LocalUsageDateLabel {
    static func relative(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "à l’instant" }
        if seconds < 3_600 { return "relevé il y a \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "relevé il y a \(Int(seconds / 3_600)) h" }
        return "relevé il y a \(Int(seconds / 86_400)) j"
    }
}

public enum UsageQuotaState: Equatable, Sendable {
    case loading
    case ready(UsageQuotaSnapshot)
    case restored(UsageQuotaSnapshot)
    case unreachable(String)
    case disabled

    public var snapshot: UsageQuotaSnapshot? {
        if case let .ready(snapshot) = self { return snapshot }
        if case let .restored(snapshot) = self { return snapshot }
        return nil
    }
}

/// Modèle unifié d'affichage synthétique d'un compteur IA pour le Mini Cockpit HUD.
public struct MiniAICounterItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let shortName: String
    public let usedPercent: Double?
    public let spendAmount: Double?
    public let spendCurrency: String?
    public let tone: QuotaTone
    public let resetLabel: String?
    public let planType: String?
    public let isStale: Bool
    public let hasData: Bool

    public init(
        id: String,
        name: String,
        shortName: String,
        usedPercent: Double?,
        spendAmount: Double?,
        spendCurrency: String?,
        tone: QuotaTone,
        resetLabel: String?,
        planType: String?,
        isStale: Bool,
        hasData: Bool
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.usedPercent = usedPercent
        self.spendAmount = spendAmount
        self.spendCurrency = spendCurrency
        self.tone = tone
        self.resetLabel = resetLabel
        self.planType = planType
        self.isStale = isStale
        self.hasData = hasData
    }

    /// Résout les 4 modèles IA cibles (Claude, ChatGPT, Gemini, OpenAI API) depuis un snapshot de quotas.
    public static func resolveItems(from snapshot: UsageQuotaSnapshot?, at now: Date = Date()) -> [MiniAICounterItem] {
        let definitions: [(id: String, name: String, shortName: String, keywords: [String])] = [
            ("claude", "Claude", "Claude", ["claude", "anthropic"]),
            ("chatgpt", "ChatGPT", "ChatGPT", ["chatgpt", "codex"]),
            ("gemini", "Gemini", "Gemini", ["gemini", "antigravity", "google"]),
            ("openai", "OpenAI API", "OpenAI", ["openai", "openai-api"])
        ]
        
        return definitions.map { def in
            // 1. Recherche parmi les jauges de forfait
            if let gauge = snapshot?.gauges.first(where: { g in
                let idLower = g.provider.lowercased()
                let labelLower = g.label.lowercased()
                if def.id == "openai" && (idLower.contains("codex") || idLower.contains("chatgpt") || labelLower.contains("chatgpt") || labelLower.contains("codex")) {
                    return false
                }
                return def.keywords.contains { kw in idLower.contains(kw) || labelLower.contains(kw) }
            }) {
                let localStale = snapshot != nil ? gauge.isLocallyStale(snapshot: snapshot!, at: now) : false
                let reset = gauge.worst.localResetLabel(snapshotIsStale: localStale, at: now)
                return MiniAICounterItem(
                    id: def.id,
                    name: def.name,
                    shortName: def.shortName,
                    usedPercent: gauge.worst.usedPercent,
                    spendAmount: nil,
                    spendCurrency: nil,
                    tone: gauge.tone,
                    resetLabel: reset.isEmpty ? nil : reset,
                    planType: gauge.planType,
                    isStale: gauge.stale || localStale,
                    hasData: true
                )
            }
            
            // 2. Recherche parmi les dépenses API facturées à l'usage
            if let spend = snapshot?.paidApiMonthToDate.first(where: { s in
                let idLower = s.provider.lowercased()
                let labelLower = s.label.lowercased()
                if def.id == "openai" && (idLower.contains("codex") || idLower.contains("chatgpt") || labelLower.contains("chatgpt") || labelLower.contains("codex")) {
                    return false
                }
                return def.keywords.contains { kw in idLower.contains(kw) || labelLower.contains(kw) }
            }) {
                let amount = spend.balanceSpendUsd ?? spend.costUsd
                let currency = spend.balanceCurrency ?? "USD"
                let isCrit = spend.balanceAvailable == false
                return MiniAICounterItem(
                    id: def.id,
                    name: def.name,
                    shortName: def.shortName,
                    usedPercent: nil,
                    spendAmount: amount,
                    spendCurrency: currency,
                    tone: isCrit ? .critical : .ok,
                    resetLabel: nil,
                    planType: "API",
                    isStale: false,
                    hasData: true
                )
            }
            
            // 3. Fallback inactif (en attente de relevé)
            let isDefaultOpenAI = (def.id == "openai" && snapshot != nil)
            return MiniAICounterItem(
                id: def.id,
                name: def.name,
                shortName: def.shortName,
                usedPercent: nil,
                spendAmount: isDefaultOpenAI ? 0.0 : nil,
                spendCurrency: isDefaultOpenAI ? "USD" : nil,
                tone: .ok,
                resetLabel: nil,
                planType: isDefaultOpenAI ? "API" : nil,
                isStale: false,
                hasData: isDefaultOpenAI
            )
        }
    }

    /// Résout les modèles IA cibles depuis un snapshot de quotas et l'état Higgsfield.
    @MainActor
    public static func resolveItems(
        from snapshot: UsageQuotaSnapshot?,
        higgsfieldService: HiggsfieldCreditService?,
        at now: Date = Date()
    ) -> [MiniAICounterItem] {
        var items = resolveItems(from: snapshot, at: now)
        if let hfService = higgsfieldService {
            let hfItem = resolveHiggsfieldItem(from: hfService, at: now)
            items.append(hfItem)
        }
        return items
    }
    
    /// Résout un élément de tuile Mini Cockpit pour Higgsfield.
    @MainActor
    public static func resolveHiggsfieldItem(from service: HiggsfieldCreditService, at now: Date = Date()) -> MiniAICounterItem {
        switch service.state {
        case .live(let snapshot):
            return MiniAICounterItem(
                id: "higgsfield",
                name: "Higgsfield",
                shortName: "HF",
                usedPercent: nil,
                spendAmount: snapshot.credits,
                spendCurrency: "CR",
                tone: .ok,
                resetLabel: snapshot.formattedPlan,
                planType: snapshot.formattedPlan,
                isStale: false,
                hasData: snapshot.credits != nil
            )
        case .stale(let snapshot, _):
            return MiniAICounterItem(
                id: "higgsfield",
                name: "Higgsfield",
                shortName: "HF",
                usedPercent: nil,
                spendAmount: snapshot.credits,
                spendCurrency: "CR",
                tone: .warn,
                resetLabel: "Périmé",
                planType: snapshot.formattedPlan,
                isStale: true,
                hasData: snapshot.credits != nil
            )
        default:
            return MiniAICounterItem(
                id: "higgsfield",
                name: "Higgsfield",
                shortName: "HF",
                usedPercent: nil,
                spendAmount: nil,
                spendCurrency: "CR",
                tone: .ok,
                resetLabel: nil,
                planType: nil,
                isStale: false,
                hasData: false
            )
        }
    }
}

