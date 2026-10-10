import Foundation

public struct BrewOutdatedItem: Identifiable, Sendable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let installed_versions: [String]
    public let current_version: String
    public let pinned: Bool?
    public let isCask: Bool
    
    public init(
        name: String,
        installed_versions: [String],
        current_version: String,
        pinned: Bool? = false,
        isCask: Bool = false
    ) {
        self.name = name
        self.installed_versions = installed_versions
        self.current_version = current_version
        self.pinned = pinned
        self.isCask = isCask
    }
    
    public var installedVersionString: String {
        installed_versions.joined(separator: ", ")
    }
    
    public var upgradeCommand: String {
        isCask ? "brew upgrade --cask \(name)" : "brew upgrade \(name)"
    }
}

public struct BrewOutdatedV2Raw: Codable, Sendable {
    public struct RawFormula: Codable, Sendable {
        public let name: String
        public let installed_versions: [String]
        public let current_version: String
        public let pinned: Bool?
    }
    
    public struct RawCask: Codable, Sendable {
        public let name: String
        public let installed_versions: [String]
        public let current_version: String
        public let pinned: Bool?
    }
    
    public let formulae: [RawFormula]
    public let casks: [RawCask]
}

public struct BrewOutdatedReport: Sendable {
    public let formulae: [BrewOutdatedItem]
    public let casks: [BrewOutdatedItem]
    public let totalCount: Int
    
    public var combinedUpgradeCommand: String {
        "brew upgrade"
    }
}

public final class BrewService: Sendable {
    public static let shared = BrewService()
    private let processRunner = ProcessRunner.shared
    
    public init() {}
    
    public func fetchOutdated() async throws -> BrewOutdatedReport {
        let brewPath = ToolRegistry.shared.resolveBinaryPath(name: "brew")
        guard let brewPath = brewPath else {
            throw ProcessRunnerError.processLaunchFailed("Homebrew binary not found on system.")
        }
        
        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: brewPath),
            arguments: ["outdated", "--json=v2"],
            timeout: 60.0
        )
        
        guard let data = result.standardOutput.data(using: .utf8) else {
            return BrewOutdatedReport(formulae: [], casks: [], totalCount: 0)
        }
        
        let raw = try JSONDecoder().decode(BrewOutdatedV2Raw.self, from: data)
        
        let formulae = raw.formulae.map {
            BrewOutdatedItem(
                name: $0.name,
                installed_versions: $0.installed_versions,
                current_version: $0.current_version,
                pinned: $0.pinned,
                isCask: false
            )
        }
        
        let casks = raw.casks.map {
            BrewOutdatedItem(
                name: $0.name,
                installed_versions: $0.installed_versions,
                current_version: $0.current_version,
                pinned: $0.pinned,
                isCask: true
            )
        }
        
        return BrewOutdatedReport(
            formulae: formulae,
            casks: casks,
            totalCount: formulae.count + casks.count
        )
    }
}
