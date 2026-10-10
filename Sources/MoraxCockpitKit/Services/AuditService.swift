import Foundation

public enum PersistenceLocation: String, CaseIterable, Identifiable, Codable, Sendable {
    case userLaunchAgents = "User Launch Agents (~/Library/LaunchAgents)"
    case systemLaunchAgents = "System Launch Agents (/Library/LaunchAgents)"
    case systemLaunchDaemons = "System Launch Daemons (/Library/LaunchDaemons)"
    
    public var id: String { rawValue }
    
    public var directoryURL: URL {
        switch self {
        case .userLaunchAgents:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        case .systemLaunchAgents:
            return URL(fileURLWithPath: "/Library/LaunchAgents")
        case .systemLaunchDaemons:
            return URL(fileURLWithPath: "/Library/LaunchDaemons")
        }
    }
}

public struct PersistenceItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { plistURL.path }
    public let label: String
    public let plistURL: URL
    public let location: PersistenceLocation
    public let programPath: String?
    public let binaryExists: Bool
    public let isOrphaned: Bool
    public let runAtLoad: Bool
    public let keepAlive: Bool
    
    public init(
        label: String,
        plistURL: URL,
        location: PersistenceLocation,
        programPath: String?,
        binaryExists: Bool,
        isOrphaned: Bool,
        runAtLoad: Bool = false,
        keepAlive: Bool = false
    ) {
        self.label = label
        self.plistURL = plistURL
        self.location = location
        self.programPath = programPath
        self.binaryExists = binaryExists
        self.isOrphaned = isOrphaned
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
    }
}

public struct AuditService: Sendable {
    public static let shared = AuditService()
    
    public init() {}
    
    public func auditPersistence() -> [PersistenceItem] {
        var items: [PersistenceItem] = []
        let fileManager = FileManager.default
        
        for location in PersistenceLocation.allCases {
            let dir = location.directoryURL
            guard fileManager.fileExists(atPath: dir.path),
                  let plists = try? fileManager.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }
            
            for plistURL in plists where plistURL.pathExtension == "plist" {
                if let item = parsePlist(at: plistURL, location: location) {
                    items.append(item)
                }
            }
        }
        
        return items.sorted {
            if $0.isOrphaned != $1.isOrphaned {
                return $0.isOrphaned && !$1.isOrphaned // Orphans at top
            }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }
    
    public func parsePlist(at plistURL: URL, location: PersistenceLocation) -> PersistenceItem? {
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        
        let label = (dict["Label"] as? String) ?? plistURL.deletingPathExtension().lastPathComponent
        
        var programPath: String? = dict["Program"] as? String
        if programPath == nil, let args = dict["ProgramArguments"] as? [String], let first = args.first {
            programPath = first
        }
        
        let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false
        let keepAlive = (dict["KeepAlive"] as? Bool) ?? false
        
        var binaryExists = true
        var isOrphaned = false
        
        if let path = programPath {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            binaryExists = FileManager.default.fileExists(atPath: path) || FileManager.default.fileExists(atPath: resolved)
            isOrphaned = !binaryExists
        }
        
        return PersistenceItem(
            label: label,
            plistURL: plistURL,
            location: location,
            programPath: programPath,
            binaryExists: binaryExists,
            isOrphaned: isOrphaned,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive
        )
    }
}
