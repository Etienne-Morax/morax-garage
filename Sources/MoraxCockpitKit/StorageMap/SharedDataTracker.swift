import Foundation

/// Bytes a walk found under a second name and did not count again.
public struct StorageSharedDataSummary: Sendable, Codable, Equatable {
    /// Allocated bytes of hardlinks already counted under another name.
    public let hardlinkDuplicateBytes: Int64
    /// Allocated bytes of pure APFS clones whose data stream was already counted.
    public let cloneDuplicateBytes: Int64

    public init(hardlinkDuplicateBytes: Int64, cloneDuplicateBytes: Int64) {
        self.hardlinkDuplicateBytes = hardlinkDuplicateBytes
        self.cloneDuplicateBytes = cloneDuplicateBytes
    }

    public var totalBytes: Int64 {
        hardlinkDuplicateBytes + cloneDuplicateBytes
    }

    public static let none = StorageSharedDataSummary(hardlinkDuplicateBytes: 0, cloneDuplicateBytes: 0)
}

/// Decides whether a file's blocks were already counted during the walk.
///
/// Hardlinks are recognised for free from `st_nlink` and the inode. Pure clones need one
/// extra `getattrlist` per file, so only files large enough to matter are probed: the
/// syscall on every one of millions of small files would cost more than it could recover.
/// A clone that was modified after cloning gets its own clone id and is counted in full,
/// which leaves the total an upper bound rather than risking an undercount.
///
/// The first name the walk meets keeps the bytes; later names are counted at zero.
struct SharedDataTracker {
    /// Files below this size are never probed for a clone id.
    static let cloneProbeMinBytes: Int64 = 1 * 1024 * 1024

    private var seenHardlinkInodes = Set<UInt64>()
    private var seenCloneIDs = Set<UInt64>()
    private var hardlinkDuplicateBytes: Int64 = 0
    private var cloneDuplicateBytes: Int64 = 0

    /// `cloneID` is only evaluated for files at or above `cloneProbeMinBytes`.
    mutating func isDuplicate(
        inode: UInt64,
        linkCount: Int,
        allocatedBytes: Int64,
        cloneID: () -> UInt64?
    ) -> Bool {
        if linkCount > 1, !seenHardlinkInodes.insert(inode).inserted {
            hardlinkDuplicateBytes += allocatedBytes
            return true
        }
        guard allocatedBytes >= Self.cloneProbeMinBytes, let id = cloneID() else { return false }
        if seenCloneIDs.insert(id).inserted { return false }
        cloneDuplicateBytes += allocatedBytes
        return true
    }

    var summary: StorageSharedDataSummary {
        StorageSharedDataSummary(
            hardlinkDuplicateBytes: hardlinkDuplicateBytes,
            cloneDuplicateBytes: cloneDuplicateBytes
        )
    }
}
