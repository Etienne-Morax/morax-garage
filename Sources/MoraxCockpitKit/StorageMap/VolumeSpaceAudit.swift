import Foundation

/// A volume that shares the scanned volume's APFS container.
///
/// Free space is pooled inside a container, so these volumes eat into the same capacity
/// as the one being scanned even though the walk never enters them.
public struct SiblingVolume: Sendable, Codable, Equatable, Identifiable {
    public let mountPoint: String
    public let deviceNode: String
    public let usedBytes: Int64
    public let isReadable: Bool
    
    public var id: String { mountPoint }
    
    public init(mountPoint: String, deviceNode: String, usedBytes: Int64, isReadable: Bool) {
        self.mountPoint = mountPoint
        self.deviceNode = deviceNode
        self.usedBytes = usedBytes
        self.isReadable = isReadable
    }
    
    public var displayName: String {
        mountPoint == "/" ? "Système" : (mountPoint as NSString).lastPathComponent
    }
}

/// Everything the filesystem reports about the space around a scan.
///
/// A walk can only ever see files. This fills in what it structurally cannot: volumes
/// sharing the container, and space macOS holds as purgeable (local snapshots, caches it
/// will reclaim under pressure). Without those lines a complete scan still looks short of
/// the disk and the user has no way to tell why.
public struct VolumeSpaceAudit: Sendable, Codable, Equatable {
    public let mountPoint: String
    public let deviceNode: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    /// Free space macOS would hand to an application that really needs it, which includes
    /// what it can purge. The difference with `availableBytes` is the purgeable amount.
    public let availableForImportantUsageBytes: Int64
    public let siblingVolumes: [SiblingVolume]
    
    public init(
        mountPoint: String,
        deviceNode: String,
        totalBytes: Int64,
        availableBytes: Int64,
        availableForImportantUsageBytes: Int64,
        siblingVolumes: [SiblingVolume]
    ) {
        self.mountPoint = mountPoint
        self.deviceNode = deviceNode
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
        self.siblingVolumes = siblingVolumes
    }
    
    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }
    
    public var purgeableBytes: Int64 {
        max(0, availableForImportantUsageBytes - availableBytes)
    }
    
    public var siblingVolumeBytes: Int64 {
        siblingVolumes.reduce(0) { $0 + $1.usedBytes }
    }
    
    // MARK: - Probing
    
    /// Reads the mount table and builds the audit for the volume holding `path`.
    public static func audit(pathOnVolume path: String, reachableMountPoints: Set<String>) -> VolumeSpaceAudit? {
        let mounts = mountedFilesystems()
        // `volumeURLKey` is the reliable answer: firmlinks mean `/Users` is textually under
        // `/` while its bytes live on the Data volume, so a prefix match on the mount table
        // would credit the wrong volume.
        let hostMountPath = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeURLKey]))?
            .volume?.path ?? mountPoint(forPath: path)
        guard let host = mounts.first(where: { $0.mountPoint == hostMountPath })
                ?? mounts.first(where: { $0.mountPoint == "/" }) else {
            return nil
        }
        
        let container = containerIdentifier(ofDeviceNode: host.deviceNode)
        let siblings = mounts
            .filter { candidate in
                candidate.mountPoint != host.mountPoint
                    && !reachableMountPoints.contains(candidate.mountPoint)
                    && containerIdentifier(ofDeviceNode: candidate.deviceNode) == container
                    && container != nil
            }
            .map {
                SiblingVolume(
                    mountPoint: $0.mountPoint,
                    deviceNode: $0.deviceNode,
                    usedBytes: $0.usedBytes,
                    isReadable: FileManager.default.isReadableFile(atPath: $0.mountPoint)
                )
            }
            .sorted { $0.usedBytes > $1.usedBytes }
        
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let values = try? URL(fileURLWithPath: host.mountPoint).resourceValues(forKeys: keys)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = Int64(values?.volumeAvailableCapacity ?? 0)
        let important = values?.volumeAvailableCapacityForImportantUsage ?? available
        
        guard total > 0 else { return nil }
        
        return VolumeSpaceAudit(
            mountPoint: host.mountPoint,
            deviceNode: host.deviceNode,
            totalBytes: total,
            availableBytes: available,
            availableForImportantUsageBytes: max(available, important),
            siblingVolumes: siblings
        )
    }
    
    struct MountedFilesystem: Sendable, Equatable {
        let mountPoint: String
        let deviceNode: String
        let fileSystemType: String
        let usedBytes: Int64
    }
    
    /// `getmntinfo` is the only way to see every mount at once. The `statfs` *function* is
    /// unreachable from Swift (the C struct shadows it), but the struct itself is readable,
    /// which is all this needs.
    static func mountedFilesystems() -> [MountedFilesystem] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let entries = buffer else { return [] }
        
        return (0..<Int(count)).compactMap { index in
            var entry = entries[index]
            let mountPoint = withUnsafePointer(to: &entry.f_mntonname) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let deviceNode = withUnsafePointer(to: &entry.f_mntfromname) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let fileSystemType = withUnsafePointer(to: &entry.f_fstypename) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
            }
            // On APFS every volume of a container reports the container's block counts, so
            // `f_blocks - f_bfree` would credit each sibling with the whole disk. The only
            // per-volume figure is the one `getattrlist` exposes, which is what `df` reads.
            let blockSize = Int64(entry.f_bsize)
            let used = volumeSpaceUsed(atPath: mountPoint)
                ?? max(0, Int64(entry.f_blocks) - Int64(entry.f_bfree)) * blockSize
            
            return MountedFilesystem(
                mountPoint: mountPoint,
                deviceNode: deviceNode,
                fileSystemType: fileSystemType,
                usedBytes: used
            )
        }
    }
    
    /// Bytes this single volume occupies, via `ATTR_VOL_SPACEUSED`.
    ///
    /// The reply is a 4-byte length followed by an unaligned `off_t`, hence the raw buffer.
    static func volumeSpaceUsed(atPath path: String) -> Int64? {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        
        var buffer = [UInt8](repeating: 0, count: 16)
        let status = path.withCString { cPath in
            buffer.withUnsafeMutableBytes { raw in
                getattrlist(cPath, &attributes, raw.baseAddress, raw.count, 0)
            }
        }
        guard status == 0 else { return nil }
        
        let used = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
        return used >= 0 ? used : nil
    }
    
    /// `/dev/disk3s5s1` and `/dev/disk3s1` live in the same container, `disk3`.
    static func containerIdentifier(ofDeviceNode deviceNode: String) -> String? {
        let name = (deviceNode as NSString).lastPathComponent
        guard name.hasPrefix("disk") else { return nil }
        guard let sliceIndex = name.dropFirst("disk".count).firstIndex(of: "s") else { return name }
        return String(name[name.startIndex..<sliceIndex])
    }
    
    static func mountPoint(forPath path: String) -> String {
        mountedFilesystems()
            .map(\.mountPoint)
            .filter { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
            .max(by: { $0.count < $1.count }) ?? "/"
    }
}
