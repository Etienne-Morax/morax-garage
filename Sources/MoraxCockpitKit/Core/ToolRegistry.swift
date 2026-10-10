import Foundation

public struct ToolInfo: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let roleDescription: String
    public let isInstalled: Bool
    public let resolvedPath: String?
    public let version: String?
    public let installCommand: String
    public let isPrerequisite: Bool
    
    public init(
        id: String,
        displayName: String,
        roleDescription: String,
        isInstalled: Bool,
        resolvedPath: String?,
        version: String?,
        installCommand: String,
        isPrerequisite: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.roleDescription = roleDescription
        self.isInstalled = isInstalled
        self.resolvedPath = resolvedPath
        self.version = version
        self.installCommand = installCommand
        self.isPrerequisite = isPrerequisite
    }
}

public final class ToolRegistry: @unchecked Sendable {
    public static let shared = ToolRegistry()
    
    private let fileManager = FileManager.default
    private let processRunner = ProcessRunner.shared
    private let managedToolsDirectory: String
    
    public init(managedToolsDirectory: String? = nil) {
        self.managedToolsDirectory = managedToolsDirectory ??
            ("~/Library/Application Support/Morax Garage/bin" as NSString).expandingTildeInPath
    }
    
    /// Returns the active Homebrew prefix by checking standard locations
    public func detectBrewPrefix() -> String? {
        if fileManager.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew"
        }
        if fileManager.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local"
        }
        return nil
    }
    
    /// Resolves an executable binary path
    public func resolveBinaryPath(name: String) -> String? {
        let brewPrefix = detectBrewPrefix()
        var candidatePaths = [(managedToolsDirectory as NSString).appendingPathComponent(name)]
        
        if let prefix = brewPrefix {
            candidatePaths.append("\(prefix)/bin/\(name)")
        }
        candidatePaths.append("/opt/homebrew/bin/\(name)")
        candidatePaths.append("/usr/local/bin/\(name)")
        candidatePaths.append(("/usr/local/share/npm/bin/\(name)"))
        candidatePaths.append(("~/.local/bin/\(name)" as NSString).expandingTildeInPath)
        candidatePaths.append(("~/.cargo/bin/\(name)" as NSString).expandingTildeInPath)
        candidatePaths.append(("~/.npm-global/bin/\(name)" as NSString).expandingTildeInPath)
        candidatePaths.append("/usr/bin/\(name)")
        candidatePaths.append("/bin/\(name)")
        
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathEnv.components(separatedBy: ":") where !directory.isEmpty {
                candidatePaths.append((directory as NSString).appendingPathComponent(name))
            }
        }
        
        for path in candidatePaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    /// Resolves an application bundle path
    public func resolveAppPath(name: String) -> String? {
        let homeAppPath = ("~/Applications/\(name).app" as NSString).expandingTildeInPath
        let systemAppPath = "/Applications/\(name).app"
        
        if fileManager.fileExists(atPath: systemAppPath) {
            return systemAppPath
        }
        if fileManager.fileExists(atPath: homeAppPath) {
            return homeAppPath
        }
        return nil
    }
    
    /// Discovers all supported tools and returns their statuses
    public func discoverAll() async -> [ToolInfo] {
        async let brew = detectHomebrew()
        async let macmon = detectMacmon()
        async let mole = detectMole()
        async let pearcleaner = detectPearcleaner()
        async let stats = detectStats()
        async let higgsfield = detectHiggsfield()
        
        return await [brew, macmon, mole, pearcleaner, stats, higgsfield]
    }
    
    public func detectHiggsfield() async -> ToolInfo {
        let path = resolveBinaryPath(name: "higgsfield") ?? resolveBinaryPath(name: "hf")
        var version: String? = nil
        if let path = path {
            version = await getCommandVersion(path: path, args: ["--version"], linePrefix: "")
        }
        return ToolInfo(
            id: "higgsfield",
            displayName: "Higgsfield CLI",
            roleDescription: "Official Higgsfield AI account and credit provider",
            isInstalled: path != nil,
            resolvedPath: path,
            version: version,
            installCommand: "brew install higgsfield"
        )
    }
    
    public func detectHomebrew() async -> ToolInfo {
        let path = resolveBinaryPath(name: "brew")
        var version: String? = nil
        if let path = path {
            version = await getCommandVersion(path: path, args: ["--version"], linePrefix: "Homebrew ")
        }
        return ToolInfo(
            id: "brew",
            displayName: "Homebrew",
            roleDescription: "Package manager and dependency provider",
            isInstalled: path != nil,
            resolvedPath: path,
            version: version,
            installCommand: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            isPrerequisite: true
        )
    }
    
    public func detectMacmon() async -> ToolInfo {
        let path = resolveBinaryPath(name: "macmon")
        var version: String? = nil
        if let path = path {
            version = await getCommandVersion(path: path, args: ["--version"], linePrefix: "macmon ")
        }
        return ToolInfo(
            id: "macmon",
            displayName: "macmon",
            roleDescription: "Live power, thermal & cluster CPU telemetry",
            isInstalled: path != nil,
            resolvedPath: path,
            version: version,
            installCommand: "brew install vladkens/tap/macmon"
        )
    }
    
    public func detectMole() async -> ToolInfo {
        let path = resolveBinaryPath(name: "mo")
        var version: String? = nil
        if let path = path {
            let res = try? await processRunner.run(executableURL: URL(fileURLWithPath: path), arguments: ["--version"], timeout: 3.0)
            if let output = res?.standardOutput {
                // Look for "Mole version X.Y.Z"
                for line in output.components(separatedBy: .newlines) {
                    if line.contains("Mole version") {
                        version = line.replacingOccurrences(of: "Mole version", with: "").trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }
        }
        return ToolInfo(
            id: "mole",
            displayName: "Mole (mo)",
            roleDescription: "Advanced system cleanup via terminal",
            isInstalled: path != nil,
            resolvedPath: path,
            version: version,
            installCommand: "brew install tw93/tap/mole"
        )
    }
    
    public func detectPearcleaner() async -> ToolInfo {
        let path = resolveAppPath(name: "Pearcleaner")
        var version: String? = nil
        if let path = path {
            version = getAppVersion(bundlePath: path)
        }
        return ToolInfo(
            id: "pearcleaner",
            displayName: "Pearcleaner",
            roleDescription: "Application uninstallation engine",
            isInstalled: path != nil,
            resolvedPath: path,
            version: version,
            installCommand: "brew install --cask pearcleaner"
        )
    }
    
    public func detectStats() async -> ToolInfo {
        let path = resolveAppPath(name: "Stats")
        var version: String? = nil
        if let path = path {
            version = getAppVersion(bundlePath: path)
        }
        return ToolInfo(
            id: "stats",
            displayName: "Stats",
            roleDescription: "Menu bar sensor suite (standalone)",
            isInstalled: path != nil,
            resolvedPath: path,
            version: version,
            installCommand: "brew install --cask stats"
        )
    }
    
    private func getCommandVersion(path: String, args: [String], linePrefix: String) async -> String? {
        do {
            let res = try await processRunner.run(executableURL: URL(fileURLWithPath: path), arguments: args, timeout: 3.0)
            let lines = res.standardOutput.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: linePrefix) {
                    return trimmed.replacingOccurrences(of: linePrefix, with: "").trimmingCharacters(in: .whitespaces)
                }
                if !trimmed.isEmpty && !linePrefix.isEmpty && linePrefix == "" {
                    return trimmed
                }
            }
            return lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?.trimmingCharacters(in: .whitespaces)
        } catch {
            return nil
        }
    }
    
    private func getAppVersion(bundlePath: String) -> String? {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        if let bundle = Bundle(url: bundleURL),
           let info = bundle.infoDictionary,
           let version = info["CFBundleShortVersionString"] as? String {
            return version
        }
        
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let version = plist["CFBundleShortVersionString"] as? String {
            return version
        }
        return nil
    }
}
