import Foundation
import AppKit

/// Reports whether the application owning a cache is currently running.
///
/// Cache directories are only safe to move to the Trash while the owning process is
/// not writing to them. Browsers rebuild a deleted cache on the next launch but can
/// corrupt an open profile, and creative applications keep working state in what
/// looks, from the outside, like a plain cache folder.
public protocol RunningAppChecking: Sendable {
    /// `true` when a running application matches one of the bundle identifiers or
    /// localized names supplied, compared case-insensitively as prefixes.
    func isRunning(bundleIdentifiers: [String], names: [String]) -> Bool
}

public struct DefaultRunningAppChecker: RunningAppChecking {
    public init() {}

    public func isRunning(bundleIdentifiers: [String], names: [String]) -> Bool {
        let wantedIds = bundleIdentifiers.map { $0.lowercased() }
        let wantedNames = names.map { $0.lowercased() }

        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier?.lowercased(),
               wantedIds.contains(where: { bundleId == $0 || bundleId.hasPrefix($0) }) {
                return true
            }
            if let name = app.localizedName?.lowercased(),
               wantedNames.contains(where: { name.contains($0) }) {
                return true
            }
        }
        return false
    }
}

/// Always reports applications as stopped. Used by the scanner tests, which run
/// against fixture directories rather than against real application state.
public struct NeverRunningAppChecker: RunningAppChecking {
    public init() {}
    public func isRunning(bundleIdentifiers: [String], names: [String]) -> Bool { false }
}
