import Foundation

/// Functional states for the Higgsfield AI credit provider.
public enum HiggsfieldCreditState: Sendable, Equatable {
    case loading
    case live(HiggsfieldCreditSnapshot)
    case stale(HiggsfieldCreditSnapshot, reason: String)
    case unauthenticated(String)
    case workspaceRequired(String)
    case cliUnavailable(String)
    case timeout
    case malformedResponse(String)
    case disabled
    case error(String)
    
    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }
    
    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
    
    public var snapshot: HiggsfieldCreditSnapshot? {
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
        case .unauthenticated: return "Non authentifié"
        case .workspaceRequired: return "Workspace requis"
        case .cliUnavailable: return "CLI Indisponible"
        case .timeout: return "Délai dépassé"
        case .malformedResponse: return "Réponse invalide"
        case .disabled: return "Désactivé"
        case .error: return "Erreur"
        }
    }
}

/// Raw parsed structure from `higgsfield account status --json`
public struct HiggsfieldAccountStatus: Codable, Sendable, Equatable {
    public let credits: Double?
    public let subscriptionPlanType: String?
    public let email: String?
    
    enum CodingKeys: String, CodingKey {
        case credits
        case subscriptionPlanType = "subscription_plan_type"
        case subscriptionPlanTypeCamel = "subscriptionPlanType"
        case planType = "plan_type"
        case plan
        case email
    }
    
    public init(credits: Double?, subscriptionPlanType: String? = nil, email: String? = nil) {
        self.credits = credits
        self.subscriptionPlanType = subscriptionPlanType
        self.email = email
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle credits as Double, Int, or String representation
        if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .credits) {
            self.credits = doubleVal
        } else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .credits) {
            self.credits = Double(intVal)
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .credits),
                  let parsed = Double(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.credits = parsed
        } else {
            self.credits = nil
        }
        
        // Handle plan across key variants
        if let plan = try? container.decodeIfPresent(String.self, forKey: .subscriptionPlanType) {
            self.subscriptionPlanType = plan
        } else if let plan = try? container.decodeIfPresent(String.self, forKey: .subscriptionPlanTypeCamel) {
            self.subscriptionPlanType = plan
        } else if let plan = try? container.decodeIfPresent(String.self, forKey: .planType) {
            self.subscriptionPlanType = plan
        } else if let plan = try? container.decodeIfPresent(String.self, forKey: .plan) {
            self.subscriptionPlanType = plan
        } else {
            self.subscriptionPlanType = nil
        }
        
        // Email is parsed if present but not displayed or persisted for privacy
        self.email = try? container.decodeIfPresent(String.self, forKey: .email)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(credits, forKey: .credits)
        try container.encodeIfPresent(subscriptionPlanType, forKey: .subscriptionPlanType)
        // deliberately omit email when serializing
    }
}

/// Item structure representing a workspace returned by `higgsfield workspace list --json`.
public struct HiggsfieldWorkspaceItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let planType: String?
    public let credits: Double?
    public let isSelected: Bool?
    public let userRole: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case planType = "plan_type"
        case credits
        case isSelected = "is_selected"
        case userRole = "user_role"
    }
    
    public init(
        id: String,
        name: String? = nil,
        planType: String? = nil,
        credits: Double? = nil,
        isSelected: Bool? = nil,
        userRole: String? = nil
    ) {
        self.id = id
        self.name = name
        self.planType = planType
        self.credits = credits
        self.isSelected = isSelected
        self.userRole = userRole
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try? container.decodeIfPresent(String.self, forKey: .name)
        self.planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        
        if let dVal = try? container.decodeIfPresent(Double.self, forKey: .credits) {
            self.credits = dVal
        } else if let iVal = try? container.decodeIfPresent(Int.self, forKey: .credits) {
            self.credits = Double(iVal)
        } else if let sVal = try? container.decodeIfPresent(String.self, forKey: .credits),
                  let parsed = Double(sVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.credits = parsed
        } else {
            self.credits = nil
        }
        
        self.isSelected = try? container.decodeIfPresent(Bool.self, forKey: .isSelected)
        self.userRole = try? container.decodeIfPresent(String.self, forKey: .userRole)
    }
}

/// Immutable snapshot representing the state of Higgsfield credits at a point in time.
public struct HiggsfieldCreditSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "hf-snap-\(capturedAt.timeIntervalSince1970)" }
    public let credits: Double?
    public let plan: String?
    public let capturedAt: Date
    public let isStale: Bool
    
    public init(
        credits: Double?,
        plan: String?,
        capturedAt: Date = Date(),
        isStale: Bool = false
    ) {
        self.credits = credits
        self.plan = plan
        self.capturedAt = capturedAt
        self.isStale = isStale
    }
    
    public var formattedCredits: String {
        guard let credits = credits else { return "—" }
        if credits.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", credits)
        } else {
            return String(format: "%.1f", credits)
        }
    }
    
    public var formattedPlan: String {
        guard let plan = plan, !plan.isEmpty else { return "Standard" }
        return plan.capitalized
    }
    
    public var accessibilityDescription: String {
        if credits != nil {
            let formatted = formattedCredits
            let planStr = plan.map { ", Plan \($0.capitalized)" } ?? ""
            return "Higgsfield : \(formatted) crédits restants\(planStr)\(isStale ? ", relevé périmé" : "")"
        } else {
            return "Higgsfield : crédits indisponibles"
        }
    }
    
    public func relativeTimeLabel(at now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(capturedAt))
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
}
