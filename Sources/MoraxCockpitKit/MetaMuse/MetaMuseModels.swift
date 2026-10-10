import Foundation

/// Functional states for the Meta Muse local-activity provider.
///
/// Unlike Higgsfield (live credit balance via CLI) this provider reads the
/// on-disk Muse session logs, so there is no authentication state: either the
/// sessions directory exists and is readable, or it does not.
public enum MetaMuseState: Sendable, Equatable {
    case loading
    case live(MetaMuseSnapshot)
    case stale(MetaMuseSnapshot, reason: String)
    case unavailable(String)
    case error(String)

    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    public var snapshot: MetaMuseSnapshot? {
        switch self {
        case .live(let snapshot), .stale(let snapshot, _):
            return snapshot
        default:
            return nil
        }
    }

    public var statusBadgeText: String {
        switch self {
        case .loading: return "Chargement..."
        case .live: return "Live"
        case .stale: return "Périmé"
        case .unavailable: return "Indisponible"
        case .error: return "Erreur"
        }
    }
}

/// Immutable snapshot of local Muse Code activity over the trailing window,
/// including exact token totals resolved via `muse export`.
public struct MetaMuseSnapshot: Sendable, Equatable, Identifiable {
    public var id: String { "metamuse-snap-\(capturedAt.timeIntervalSince1970)" }
    public let sessionsCount: Int
    public let toolCallsCount: Int
    public let models: [String]
    public let lastActivityAt: Date?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let reasoningTokens: Int
    public let estimatedSpendUSD: Double
    public let capturedAt: Date
    public let isStale: Bool

    public init(
        sessionsCount: Int,
        toolCallsCount: Int,
        models: [String],
        lastActivityAt: Date?,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        reasoningTokens: Int = 0,
        estimatedSpendUSD: Double = 0,
        capturedAt: Date = Date(),
        isStale: Bool = false
    ) {
        self.sessionsCount = sessionsCount
        self.toolCallsCount = toolCallsCount
        self.models = models
        self.lastActivityAt = lastActivityAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
        self.estimatedSpendUSD = estimatedSpendUSD
        self.capturedAt = capturedAt
        self.isStale = isStale
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Share of input tokens served from cache, shown at the dial center.
    public var cachedShare: Double {
        guard inputTokens > 0 else { return 0 }
        return min(1, Double(cachedTokens) / Double(inputTokens))
    }

    public var formattedTotalTokens: String {
        Self.compact(totalTokens)
    }

    public var formattedSpendUSD: String {
        String(format: "$%.2f", estimatedSpendUSD)
    }

    public static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        return String(value)
    }

    public func staleCopy() -> MetaMuseSnapshot {
        MetaMuseSnapshot(
            sessionsCount: sessionsCount,
            toolCallsCount: toolCallsCount,
            models: models,
            lastActivityAt: lastActivityAt,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            reasoningTokens: reasoningTokens,
            estimatedSpendUSD: estimatedSpendUSD,
            capturedAt: capturedAt,
            isStale: true
        )
    }

    public var modelsLabel: String {
        guard !models.isEmpty else { return "—" }
        let short = models.map { $0.replacingOccurrences(of: "muse-", with: "") }
        let joined = short.joined(separator: ", ")
        return joined.count > 28 ? String(joined.prefix(27)) + "…" : joined
    }

    public func lastActivityLabel(at now: Date = Date()) -> String {
        guard let last = lastActivityAt else { return "Aucune session" }
        let seconds = max(0, now.timeIntervalSince(last))
        if seconds < 60 {
            return "à l’instant"
        } else if seconds < 3_600 {
            return "il y a \(Int(seconds / 60)) min"
        } else if seconds < 86_400 {
            return "il y a \(Int(seconds / 3_600)) h"
        } else {
            return "il y a \(Int(seconds / 86_400)) j"
        }
    }

    public var accessibilityDescription: String {
        "Muse Code : \(sessionsCount) sessions, \(Self.compact(totalTokens)) tokens, \(formattedSpendUSD) estimés sur 7 jours\(isStale ? ", relevé périmé" : "")"
    }
}

/// Manual subscription percentage shown as a gauge, Claude/Codex-style.
///
/// No endpoint serves Meta's subscription windows automatically (verified:
/// `api.meta.ai`, `api.llama.com`, Relay `graphqlbatch`, TUI scraping), so
/// the single % is entered by hand from `dev.meta.ai/usage` and stamped.
public struct MetaMuseManualQuota {
    public static let percentKey = "morax_metamuse_manual_percent"
    public static let updatedAtKey = "morax_metamuse_manual_updated_at"

    /// Value shown when nothing was entered yet.
    public static let unset: Double = -1

    public static func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    public static func formatted(_ value: Double) -> String {
        "\(Int(clamped(value).rounded())) %"
    }

    public static func updatedLabel(at date: Date?, now: Date = Date()) -> String {
        guard let date else { return "À renseigner dans Réglages" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 3_600 {
            return "Relevé manuel • il y a \(max(1, Int(seconds / 60))) min"
        } else if seconds < 86_400 {
            return "Relevé manuel • il y a \(Int(seconds / 3_600)) h"
        }
        return "Relevé manuel • il y a \(Int(seconds / 86_400)) j"
    }
}

/// Builder for the embedded Meta Model API Usage page.
///
/// The subscription gauges (Current usage / Weekly limit) are only served to
/// the browser cookie session, so the cockpit embeds the real page instead of
/// re-fetching its data: `LLMDCUsageQuery` (doc_id `28117303444603430`) via
/// `POST dev.meta.ai/api/graphqlbatch/` answers "Log in to continue" to any
/// non-cookie credential.
public struct MetaMuseUsagePage {
    public static func url(projectID: String, teamID: String) -> URL? {
        let project = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty, !team.isEmpty else { return nil }
        var components = URLComponents(string: "https://dev.meta.ai/usage/")
        components?.queryItems = [
            URLQueryItem(name: "project_id", value: project),
            URLQueryItem(name: "team_id", value: team)
        ]
        return components?.url
    }
}
