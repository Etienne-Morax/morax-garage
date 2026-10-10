import Foundation

/// Where client photo projects live along the Mac → SSD → NAS workflow.
public struct PhotoSyncConfiguration: Codable, Equatable, Sendable {
    /// Folder on the Mac where a finished job is created (one sub-folder per project).
    public var macRoot: String
    /// Folder on the external SSD holding one sub-folder per project.
    public var ssdRoot: String
    /// NAS share root; projects are filed below category / sub-category folders.
    public var nasRoot: String
    /// How long a project stays on the SSD after being archived to the NAS.
    public var ssdRetentionDays: Int
    /// Project folder names the user chose to hide (normalized keys).
    public var ignoredProjectKeys: [String]

    public static let defaultRetentionDays = 60

    public static let `default` = PhotoSyncConfiguration(
        macRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures").path,
        ssdRoot: ProcessInfo.processInfo.environment["MORAX_PHOTOSYNC_SSD_ROOT"] ?? "/Volumes/SSD/Photos",
        nasRoot: ProcessInfo.processInfo.environment["MORAX_PHOTOSYNC_NAS_ROOT"] ?? "/Volumes/NAS",
        ssdRetentionDays: defaultRetentionDays,
        ignoredProjectKeys: []
    )

    public init(macRoot: String, ssdRoot: String, nasRoot: String, ssdRetentionDays: Int, ignoredProjectKeys: [String]) {
        self.macRoot = macRoot
        self.ssdRoot = ssdRoot
        self.nasRoot = nasRoot
        self.ssdRetentionDays = ssdRetentionDays
        self.ignoredProjectKeys = ignoredProjectKeys
    }
}

/// Ceilings on blocking file-system work, so a stale SMB mount or a hung USB disk
/// degrades to "offline / not verified" instead of freezing the tab or the job queue.
public struct PhotoSyncTimeouts: Sendable {
    /// Checking that a volume root is mounted: a healthy mount answers instantly.
    public var volumeProbe: TimeInterval
    /// Listing the SSD projects or indexing the NAS category tree.
    public var listing: TimeInterval
    /// Fingerprinting every copy of one project (a big shoot over SMB takes a while).
    public var projectCheck: TimeInterval
    /// Interval between checks that the source and destination still answer during a copy.
    public var volumeWatch: TimeInterval

    public static let `default` = PhotoSyncTimeouts(volumeProbe: 5, listing: 120, projectCheck: 600, volumeWatch: 30)

    public init(volumeProbe: TimeInterval, listing: TimeInterval, projectCheck: TimeInterval, volumeWatch: TimeInterval) {
        self.volumeProbe = volumeProbe
        self.listing = listing
        self.projectCheck = projectCheck
        self.volumeWatch = volumeWatch
    }
}

/// Aggregate content of one copy of a project folder.
public struct FolderFingerprint: Equatable, Sendable {
    /// Normalized relative path → file size in bytes.
    public let files: [String: Int64]
    /// `false` when part of the folder could not be read (permission or I/O error,
    /// volume unmounted mid-walk): `files` is then a subset and proves nothing.
    public let isComplete: Bool

    public init(files: [String: Int64], isComplete: Bool = true) {
        self.files = files
        self.isComplete = isComplete
    }

    /// A copy known to exist that could not be read at all.
    public static let unreadable = FolderFingerprint(files: [:], isComplete: false)

    public var fileCount: Int { files.count }
    public var totalBytes: Int64 { files.values.reduce(0, +) }
}

/// Result of comparing a destination copy against its reference copy.
public enum CopyStatus: Codable, Equatable, Sendable {
    /// The destination volume is not mounted, so nothing could be checked.
    case volumeOffline
    /// There is no reference copy to compare against.
    case noSource
    /// The project folder does not exist at the destination.
    case missing
    /// Some files are absent or differ in size at the destination.
    case incomplete(missingFiles: Int, missingBytes: Int64)
    /// Every reference file exists at the destination with the same size.
    case synced
    /// One of the copies could only be read partially (permission or I/O error, volume
    /// gone mid-walk), so the comparison proves nothing either way.
    case unverifiable

    public var isSynced: Bool { self == .synced }

    /// `true` when a copy job would bring the destination up to date.
    public var needsSync: Bool {
        switch self {
        case .missing, .incomplete: return true
        case .volumeOffline, .noSource, .synced, .unverifiable: return false
        }
    }
}

/// Where the project currently stands in the workflow, most urgent first.
public enum PhotoSyncStage: Int, Codable, Comparable, Sendable {
    case needsSSDCopy = 0
    case needsNASArchive = 1
    case readyToFreeSSD = 2
    case retainedOnSSD = 3
    case archivedOnly = 4
    case unknown = 5

    public static func < (lhs: PhotoSyncStage, rhs: PhotoSyncStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Full sync picture for one client project.
public struct PhotoProjectStatus: Codable, Identifiable, Equatable, Sendable {
    public var id: String { key }

    /// Normalized folder name used to match copies across volumes.
    public let key: String
    public let name: String
    public let macPath: String?
    public let ssdPath: String?
    public let nasPath: String?
    /// Size of the most complete known copy (Mac first, then SSD).
    public let referenceBytes: Int64
    public let referenceFileCount: Int
    public let macToSSD: CopyStatus
    public let ssdToNAS: CopyStatus
    /// When the project landed on the SSD, used for the retention countdown.
    public let ssdCopyDate: Date?
    public let lastModified: Date?
    public let checkedAt: Date

    public init(
        key: String,
        name: String,
        macPath: String?,
        ssdPath: String?,
        nasPath: String?,
        referenceBytes: Int64,
        referenceFileCount: Int,
        macToSSD: CopyStatus,
        ssdToNAS: CopyStatus,
        ssdCopyDate: Date?,
        lastModified: Date?,
        checkedAt: Date
    ) {
        self.key = key
        self.name = name
        self.macPath = macPath
        self.ssdPath = ssdPath
        self.nasPath = nasPath
        self.referenceBytes = referenceBytes
        self.referenceFileCount = referenceFileCount
        self.macToSSD = macToSSD
        self.ssdToNAS = ssdToNAS
        self.ssdCopyDate = ssdCopyDate
        self.lastModified = lastModified
        self.checkedAt = checkedAt
    }

    /// Whole days the project has been sitting on the SSD.
    public func daysOnSSD(now: Date = Date()) -> Int? {
        guard let ssdCopyDate, ssdPath != nil else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: ssdCopyDate, to: now).day ?? 0)
    }

    /// `true` when a copy could only be read partially, so the project cannot be trusted.
    public var hasUnverifiableCopy: Bool {
        macToSSD == .unverifiable || ssdToNAS == .unverifiable
    }

    public func stage(retentionDays: Int, now: Date = Date()) -> PhotoSyncStage {
        if macToSSD.needsSync { return .needsSSDCopy }
        if ssdToNAS.needsSync { return .needsNASArchive }
        guard ssdToNAS.isSynced, !hasUnverifiableCopy else { return .unknown }
        guard ssdPath != nil else { return .archivedOnly }
        if let days = daysOnSSD(now: now), days >= retentionDays {
            return .readyToFreeSSD
        }
        return .retainedOnSSD
    }
}

/// Which leg of the workflow a copy job covers.
public enum PhotoSyncLeg: String, Codable, Sendable {
    case macToSSD
    case ssdToNAS
}

/// Normalization shared by every comparison so that NFD names coming back from
/// SMB / exFAT match the NFC names written by Finder, and trailing spaces or case
/// differences do not split one project into two.
public enum PhotoSyncNaming {
    public static func projectKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func relativePathKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }
}
