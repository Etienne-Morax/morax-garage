import Foundation

/// Why a path could not be walked, or was deliberately left out of the walk.
public enum StorageScanIssueKind: String, Sendable, Codable, CaseIterable {
    /// macOS privacy protection (TCC) refused the read (`EPERM`): Full Disk Access fixes it.
    case permissionDenied
    /// POSIX permissions refused the read (`EACCES`) on an item the current user owns:
    /// Full Disk Access cannot help, a `chmod` can.
    case posixDenied
    /// POSIX permissions refused the read (`EACCES`) on an item owned by root or a system
    /// account. No unprivileged app can read it, Full Disk Access included, so it is
    /// reported for transparency without marking the scan incomplete; any sizeable bytes
    /// hidden there still surface through the volume reconciliation.
    case systemProtected
    /// The entry could not be stat'ed at all.
    case unreadable
    /// The entry lives on another volume than the scan root.
    case volumeBoundary
    /// The entry is a pseudo filesystem (devfs, autofs, ...) with no meaningful on-disk size.
    case pseudoFilesystem
    /// Hardlink / alias recursion guard.
    case recursionLoop
    /// Symlink pointing outside the scan root.
    case symlinkEscape

    /// Issues that mean "bytes are missing from the total", as opposed to a deliberate,
    /// harmless exclusion.
    public var undercountsTotal: Bool {
        switch self {
        case .permissionDenied, .posixDenied, .unreadable:
            return true
        case .systemProtected, .volumeBoundary, .pseudoFilesystem, .recursionLoop, .symlinkEscape:
            return false
        }
    }
}

public struct StorageScanIssue: Sendable, Codable, Equatable, Identifiable {
    public let path: String
    public let kind: StorageScanIssueKind
    public let message: String

    public var id: String { "\(kind.rawValue):\(path)" }

    public init(path: String, kind: StorageScanIssueKind, message: String) {
        self.path = path
        self.kind = kind
        self.message = message
    }
}

/// Compares the walked total with what the filesystem itself reports for the volume, and
/// names every bucket of space the walk structurally cannot enter.
///
/// The point is that the lines add up: scanned + sibling volumes + purgeable + residual
/// equals what the volume says it is using. A residual above the tolerance is the honest
/// admission that something is still unexplained.
public struct StorageScanReconciliation: Sendable, Codable, Equatable {
    /// Above this relative gap the scan is flagged as incomplete in the UI.
    public static let toleranceRatio: Double = 0.05

    public let volumePath: String
    public let volumeTotalBytes: Int64
    /// APFS "Capacity In Use By Volumes" equivalent: total - available.
    public let volumeUsedBytes: Int64
    public let scannedAllocatedBytes: Int64
    /// True only when the scan root is the mount point itself; otherwise the comparison
    /// is informational (a subfolder is obviously smaller than its volume).
    public let coversWholeVolume: Bool
    /// Volumes sharing the same APFS container: they consume the same pool of free space
    /// but are outside the scan root.
    public let siblingVolumes: [SiblingVolume]
    /// Space macOS is holding but would reclaim under pressure — local Time Machine
    /// snapshots above all. No walk can see it, and the volume already counts it as used,
    /// so it explains part of the residual rather than adding to the total.
    public let purgeableBytes: Int64
    /// Logical size of cloud placeholders, reported for context only: these bytes are not
    /// on this disk and must never be added to the used total.
    public let datalessLogicalBytes: Int64

    public init(
        volumePath: String,
        volumeTotalBytes: Int64,
        volumeUsedBytes: Int64,
        scannedAllocatedBytes: Int64,
        coversWholeVolume: Bool,
        siblingVolumes: [SiblingVolume] = [],
        purgeableBytes: Int64 = 0,
        datalessLogicalBytes: Int64 = 0
    ) {
        self.volumePath = volumePath
        self.volumeTotalBytes = volumeTotalBytes
        self.volumeUsedBytes = volumeUsedBytes
        self.scannedAllocatedBytes = scannedAllocatedBytes
        self.coversWholeVolume = coversWholeVolume
        self.siblingVolumes = siblingVolumes
        self.purgeableBytes = purgeableBytes
        self.datalessLogicalBytes = datalessLogicalBytes
    }
    
    public var siblingVolumeBytes: Int64 {
        siblingVolumes.reduce(0) { $0 + $1.usedBytes }
    }
    
    /// Everything the scan can point at: files it walked, plus volumes it knowingly left
    /// out. Purgeable space is deliberately excluded — the volume counts those bytes as
    /// used, so adding them would explain the same space twice.
    public var accountedBytes: Int64 {
        scannedAllocatedBytes + siblingVolumeBytes
    }

    public var unaccountedBytes: Int64 {
        max(0, volumeUsedBytes - accountedBytes)
    }

    public var discrepancyRatio: Double {
        guard volumeUsedBytes > 0 else { return 0 }
        return Double(unaccountedBytes) / Double(volumeUsedBytes)
    }

    public var exceedsTolerance: Bool {
        coversWholeVolume && discrepancyRatio > Self.toleranceRatio
    }

    public var formattedUnaccounted: String {
        ByteCountFormatter.string(fromByteCount: unaccountedBytes, countStyle: .file)
    }
}

/// Collects issues during a walk under a bounded memory budget.
///
/// A whole-disk walk reports hundreds of thousands of harmless recursion loops. Retaining
/// issues first-come-first-served let those fill the budget, so a real refusal met later
/// was dropped and the scan could claim completeness. Informational kinds now get a small
/// share of the budget, and every kind is counted exactly whatever is retained.
public struct StorageScanIssueLog: Sendable {
    /// Retained issues whose kind never removes bytes from the total.
    public static let maxRetainedInformationalIssues = 100

    public private(set) var issues: [StorageScanIssue] = []
    public private(set) var totalCount = 0
    public private(set) var countsByKind: [StorageScanIssueKind: Int] = [:]
    private var retainedInformationalCount = 0

    public init() {}

    public mutating func record(_ kind: StorageScanIssueKind, path: String, message: String) {
        totalCount += 1
        countsByKind[kind, default: 0] += 1
        guard issues.count < StorageScanReport.maxRetainedIssues else { return }
        if StorageScanReport.isInformational(kind) {
            guard retainedInformationalCount < Self.maxRetainedInformationalIssues else { return }
            retainedInformationalCount += 1
        }
        issues.append(StorageScanIssue(path: path, kind: kind, message: message))
    }
}

/// Everything a scan knows about its own completeness. A scan that hit walls must never
/// present itself as complete, so this travels with the tree and is persisted with it.
public struct StorageScanReport: Sendable, Codable, Equatable {
    /// Hard cap so a fully denied scan cannot balloon the snapshot on disk.
    public static let maxRetainedIssues = 500

    /// Kinds shown to the user only as context: neither missing bytes nor protected items.
    static func isInformational(_ kind: StorageScanIssueKind) -> Bool {
        !kind.undercountsTotal && kind != .systemProtected
    }

    public let issues: [StorageScanIssue]
    /// Total number of issues encountered, which can exceed `issues.count`.
    public let totalIssueCount: Int
    /// Exact count per kind (raw value), independent of how many issues were retained.
    /// Absent from snapshots written before it existed; counts then fall back to `issues`.
    public let issueCountsByKind: [String: Int]?
    public let scannedItemCount: Int
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    /// Logical bytes held by dataless placeholders (cloud files never downloaded).
    public let datalessLogicalBytes: Int64
    public let reconciliation: StorageScanReconciliation?
    /// Hardlink and clone bytes left out of the totals because another name already
    /// counted them. Absent from snapshots written before deduplication existed.
    public let sharedData: StorageSharedDataSummary?

    public init(
        issues: [StorageScanIssue],
        totalIssueCount: Int,
        issueCountsByKind: [StorageScanIssueKind: Int]? = nil,
        scannedItemCount: Int,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        datalessLogicalBytes: Int64,
        reconciliation: StorageScanReconciliation?,
        sharedData: StorageSharedDataSummary? = nil
    ) {
        self.sharedData = sharedData
        self.issues = issues
        self.totalIssueCount = totalIssueCount
        self.issueCountsByKind = issueCountsByKind.map { counts in
            Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
        }
        self.scannedItemCount = scannedItemCount
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.datalessLogicalBytes = datalessLogicalBytes
        self.reconciliation = reconciliation
    }

    public init(
        issueLog: StorageScanIssueLog,
        sharedData: StorageSharedDataSummary? = nil,
        scannedItemCount: Int,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        datalessLogicalBytes: Int64,
        reconciliation: StorageScanReconciliation?
    ) {
        self.init(
            issues: issueLog.issues,
            totalIssueCount: issueLog.totalCount,
            issueCountsByKind: issueLog.countsByKind,
            scannedItemCount: scannedItemCount,
            allocatedBytes: allocatedBytes,
            logicalBytes: logicalBytes,
            datalessLogicalBytes: datalessLogicalBytes,
            reconciliation: reconciliation,
            sharedData: sharedData
        )
    }

    /// Exact number of issues of `kind`, including those not retained.
    public func count(of kind: StorageScanIssueKind) -> Int {
        if let issueCountsByKind {
            return issueCountsByKind[kind.rawValue] ?? 0
        }
        return issues.reduce(0) { $0 + ($1.kind == kind ? 1 : 0) }
    }

    /// Only the retained issues that actually remove bytes from the total.
    public var blockingIssues: [StorageScanIssue] {
        issues.filter { $0.kind.undercountsTotal }
    }

    /// Retained items no unprivileged process can read, shown apart from the blocking issues.
    public var systemProtectedIssues: [StorageScanIssue] {
        issues.filter { $0.kind == .systemProtected }
    }

    public var systemProtectedCount: Int {
        count(of: .systemProtected)
    }

    /// True only when granting Full Disk Access would let a rescan read more.
    public var needsFullDiskAccess: Bool {
        count(of: .permissionDenied) > 0
    }

    /// Exact number of issues that remove bytes from the total.
    public var unreadableCount: Int {
        StorageScanIssueKind.allCases
            .filter(\.undercountsTotal)
            .reduce(0) { $0 + count(of: $1) }
    }

    public var isComplete: Bool {
        unreadableCount == 0 && !(reconciliation?.exceedsTolerance ?? false)
    }

    /// Re-evaluates issues against current Full Disk Access and Data Vault rules.
    /// Older snapshots may have recorded system Data Vaults as `permissionDenied` because
    /// the kernel returned `EPERM`.
    public func reclassifyingSystemDataVaults(hasFullDiskAccess: Bool? = nil) -> StorageScanReport {
        guard (issueCountsByKind?[StorageScanIssueKind.permissionDenied.rawValue] ?? 0) > 0 || issues.contains(where: { $0.kind == .permissionDenied }) else {
            return self
        }
        
        let effectiveFDA = hasFullDiskAccess ?? PermissionsService.probeFullDiskAccess()
        var newCounts = issueCountsByKind ?? [:]
        var updatedIssues: [StorageScanIssue] = []
        var reclassifiedCount = 0
        
        for issue in issues {
            if issue.kind == .permissionDenied && (effectiveFDA || StorageScanner.isSystemProtectedDataVault(path: issue.path)) {
                updatedIssues.append(StorageScanIssue(path: issue.path, kind: .systemProtected, message: issue.message))
                reclassifiedCount += 1
            } else {
                updatedIssues.append(issue)
            }
        }
        
        if reclassifiedCount > 0 || effectiveFDA {
            let oldPerm = newCounts[StorageScanIssueKind.permissionDenied.rawValue] ?? reclassifiedCount
            let permToShift = effectiveFDA ? oldPerm : min(oldPerm, reclassifiedCount)
            newCounts[StorageScanIssueKind.permissionDenied.rawValue] = max(0, oldPerm - permToShift)
            newCounts[StorageScanIssueKind.systemProtected.rawValue, default: 0] += permToShift
        }
        
        return StorageScanReport(
            issues: updatedIssues,
            totalIssueCount: totalIssueCount,
            issueCountsByKind: Dictionary(uniqueKeysWithValues: newCounts.compactMap { (k, v) in
                guard let kind = StorageScanIssueKind(rawValue: k) else { return nil }
                return (kind, v)
            }),
            scannedItemCount: scannedItemCount,
            allocatedBytes: allocatedBytes,
            logicalBytes: logicalBytes,
            datalessLogicalBytes: datalessLogicalBytes,
            reconciliation: reconciliation,
            sharedData: sharedData
        )
    }

    public static let empty = StorageScanReport(
        issues: [],
        totalIssueCount: 0,
        scannedItemCount: 0,
        allocatedBytes: 0,
        logicalBytes: 0,
        datalessLogicalBytes: 0,
        reconciliation: nil
    )
}

public struct StorageScanResult: Sendable {
    public let rootNode: StorageNode
    public let report: StorageScanReport

    public init(rootNode: StorageNode, report: StorageScanReport) {
        self.rootNode = rootNode
        self.report = report
    }
}
