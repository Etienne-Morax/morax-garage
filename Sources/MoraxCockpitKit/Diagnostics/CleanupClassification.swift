import Foundation

public enum CleanupClassification: String, CaseIterable, Codable, Sendable {
    case recoverableNow = "Recoverable now"
    case potentiallyRecoverable = "Potentially recoverable"
    case protectedInformational = "Protected / informational"
}

public extension FileItem {
    /// A presentation/safety classification only. It never authorizes deletion.
    var cleanupClassification: CleanupClassification {
        switch riskTier {
        case .safe: return .recoverableNow
        case .rebuildCost: return .potentiallyRecoverable
        case .destructive, .blocked: return .protectedInformational
        }
    }
}
