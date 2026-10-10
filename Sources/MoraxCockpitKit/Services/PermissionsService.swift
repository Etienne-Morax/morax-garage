import Foundation
import AppKit
import Observation

public enum PermissionType: String, CaseIterable, Identifiable, Sendable {
    case fullDiskAccess = "Full Disk Access"
    case downloadsFolder = "Downloads Folder"
    case desktopFolder = "Desktop Folder"
    case documentsFolder = "Documents & Projects"
    case removableVolumes = "External Volumes & Media"
    case automation = "App Automation & Handoff"
    case accessibility = "Accessibility"
    
    public var id: String { rawValue }
    
    public var isCritical: Bool {
        switch self {
        case .fullDiskAccess, .downloadsFolder, .desktopFolder:
            return true
        case .documentsFolder, .removableVolumes, .automation, .accessibility:
            return false
        }
    }
    
    public var iconName: String {
        switch self {
        case .fullDiskAccess: return "externaldrive.fill.badge.checkmark"
        case .downloadsFolder: return "arrow.down.circle.fill"
        case .desktopFolder: return "menubar.dock.rectangle"
        case .documentsFolder: return "folder.fill.badge.gearshape"
        case .removableVolumes: return "opticaldiscdrive.fill"
        case .automation: return "bolt.horizontal.fill"
        case .accessibility: return "figure.roll"
        }
    }
    
    public var roleDescription: String {
        switch self {
        case .fullDiskAccess:
            return "Required to scan DaVinci Resolve caches, Photo App libraries (Lightroom, Capture One), user LaunchAgents, and Claude Code worktrees."
        case .downloadsFolder:
            return "Required by InstallerScanner to identify old .dmg, .pkg, and large archives taking up space."
        case .desktopFolder:
            return "Required by InstallerScanner to clean leftover installer disk images on the Desktop."
        case .documentsFolder:
            return "Required by DevArtefactScanner to clean node_modules, .next, and target build directories."
        case .removableVolumes:
            return "Required to scan external scratch disks and render caches used by DaVinci Resolve."
        case .automation:
            return "Used for seamless handoff to Pearcleaner and revealing files in Finder."
        case .accessibility:
            return "Allows enhanced window and menu bar integration on macOS."
        }
    }
    
    public var settingsURLString: String {
        switch self {
        case .fullDiskAccess:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .downloadsFolder, .desktopFolder, .documentsFolder:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .removableVolumes:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_RemovableVolumes"
        case .automation:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

public enum PermissionStatus: String, Sendable {
    case granted = "Granted"
    case notDetermined = "Needs Permission"
    case denied = "Restricted"
    case notRequired = "Optional"
}

public struct PermissionRecord: Identifiable, Sendable {
    public let type: PermissionType
    public let status: PermissionStatus
    public let details: String
    
    public var id: String { type.id }
}

@Observable
@MainActor
public final class PermissionsService {
    public static let shared = PermissionsService()
    
    public private(set) var permissions: [PermissionRecord] = []
    public private(set) var isChecking: Bool = false
    public private(set) var hasFullDiskAccess: Bool = false
    public private(set) var criticalPermissionsGranted: Bool = false
    
    public init() {
        checkAllPermissions()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllPermissions()
            }
        }
    }
    
    /// Incremented per check so a slow, stale probe never overwrites a newer result.
    private var checkGeneration = 0
    private var appliedGeneration = 0

    /// Re-probes every permission off the main actor.
    ///
    /// Listing Downloads/Desktop/Documents can trigger a TCC consent prompt (for instance
    /// after the app's signature changed), and `open()` then blocks until the user answers.
    /// Run on the main actor at launch, that froze the app before its first window.
    public func checkAllPermissions() {
        Task { await refreshPermissions() }
    }

    /// Awaitable form of `checkAllPermissions()`, for callers that need the result.
    public func refreshPermissions() async {
        checkGeneration += 1
        let generation = checkGeneration
        isChecking = true
        let records = await Task.detached(priority: .userInitiated) {
            PermissionType.allCases.map { type in
                let (status, details) = PermissionsService.probePermission(type)
                return PermissionRecord(type: type, status: status, details: details)
            }
        }.value
        // Apply unless a newer check already landed, so an awaited refresh always
        // returns with results even while another check is still in flight.
        guard generation > appliedGeneration else { return }
        appliedGeneration = generation
        apply(records)
    }

    private func apply(_ records: [PermissionRecord]) {
        permissions = records
        let fdaRecord = records.first(where: { $0.type == .fullDiskAccess })
        hasFullDiskAccess = fdaRecord?.status == .granted

        let criticalMissing = records.filter { $0.type.isCritical && $0.status != .granted }
        criticalPermissionsGranted = criticalMissing.isEmpty
        isChecking = false
    }

    nonisolated public func checkPermission(_ type: PermissionType) -> (PermissionStatus, String) {
        Self.probePermission(type)
    }

    nonisolated static func probePermission(_ type: PermissionType) -> (PermissionStatus, String) {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        switch type {
        case .fullDiskAccess:
            if PermissionsService.probeFullDiskAccess() {
                return (.granted, "Full Disk Access is active. All system caches and libraries are accessible.")
            }
            return (.notDetermined, "Full Disk Access is required for DaVinci Resolve caches, Photo apps, and LaunchAgents.")
            
        case .downloadsFolder:
            let downloadsPath = home + "/Downloads"
            if fm.isReadableFile(atPath: downloadsPath) {
                if (try? fm.contentsOfDirectory(atPath: downloadsPath)) != nil {
                    return (.granted, "Downloads folder is readable.")
                }
            }
            return (.notDetermined, "Access to Downloads is needed to scan old installers and large disk images.")
            
        case .desktopFolder:
            let desktopPath = home + "/Desktop"
            if fm.isReadableFile(atPath: desktopPath) {
                if (try? fm.contentsOfDirectory(atPath: desktopPath)) != nil {
                    return (.granted, "Desktop folder is readable.")
                }
            }
            return (.notDetermined, "Access to Desktop is needed to find leftover .dmg and .pkg files.")
            
        case .documentsFolder:
            let docsPath = home + "/Documents"
            if fm.isReadableFile(atPath: docsPath) {
                if (try? fm.contentsOfDirectory(atPath: docsPath)) != nil {
                    return (.granted, "Documents & Projects folders are readable.")
                }
            }
            return (.notDetermined, "Access to Documents and code directories is needed for dev artifact cleaning.")
            
        case .removableVolumes:
            let volumesPath = "/Volumes"
            if fm.isReadableFile(atPath: volumesPath) {
                if let vols = try? fm.contentsOfDirectory(atPath: volumesPath), !vols.isEmpty {
                    return (.granted, "External volumes and scratch disks are accessible.")
                }
            }
            return (.notDetermined, "Access to external drives is needed for external DaVinci Resolve scratch disks.")
            
        case .automation:
            return (.granted, "AppleEvents and tool handoff ready.")
            
        case .accessibility:
            let trusted = AXIsProcessTrusted()
            if trusted {
                return (.granted, "Accessibility is trusted.")
            } else {
                return (.notRequired, "Optional: Not strictly required for standard maintenance tasks.")
            }
        }
    }
    
    /// Probes Full Disk Access by reading paths that TCC protects unconditionally.
    ///
    /// Only an actual read proves the grant: `isReadableFile` returns true for paths the
    /// sandbox would still refuse, which previously made the app believe it could see the
    /// whole disk while the walker was being denied hundreds of directories.
    nonisolated public static func probeFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let protectedFiles = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        for path in protectedFiles {
            if let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) {
                try? handle.close()
                return true
            }
        }
        
        // Fallback for machines where TCC.db is absent: these directories are readable
        // only with the grant, and an empty listing is not proof, so contents are required.
        let protectedDirectories = [
            home + "/Library/Safari",
            home + "/Library/Application Support/MobileSync",
            home + "/Library/Containers/com.apple.mail"
        ]
        for path in protectedDirectories {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: path), !contents.isEmpty {
                return true
            }
        }
        return false
    }
    
    public func openSystemSettings(for type: PermissionType) {
        if let url = URL(string: type.settingsURLString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func openAllFilesSettings() {
        openSystemSettings(for: .fullDiskAccess)
    }
    
    public func triggerFolderAccessPrompt(for type: PermissionType) {
        let home = NSHomeDirectory()
        
        let path: String
        switch type {
        case .downloadsFolder: path = home + "/Downloads"
        case .desktopFolder: path = home + "/Desktop"
        case .documentsFolder: path = home + "/Documents"
        case .removableVolumes: path = "/Volumes"
        default:
            openSystemSettings(for: type)
            checkAllPermissions()
            return
        }
        // The listing shows the consent prompt and blocks until it is answered.
        Task {
            await Task.detached(priority: .userInitiated) {
                _ = try? FileManager.default.contentsOfDirectory(atPath: path)
            }.value
            await refreshPermissions()
        }
    }
}
