import Foundation

public enum PhotoSyncCopyError: Error, LocalizedError, Equatable {
    case sourceMissing(String)
    case destinationParentMissing(String)
    case unsafeDestination(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "Dossier source introuvable : \(path)"
        case .destinationParentMissing(let path):
            return "Destination indisponible (disque débranché ?) : \(path)"
        case .unsafeDestination(let path):
            return "Destination refusée : \(path)"
        }
    }
}

/// An additive rsync copy of one project folder. It never passes `--delete`, so a
/// copy can only add or refresh files at the destination, never remove them.
public struct PhotoSyncCopyPlan: Equatable, Sendable {
    public static let rsyncURL = URL(fileURLWithPath: "/usr/bin/rsync")

    public let projectKey: String
    public let leg: PhotoSyncLeg
    public let source: URL
    public let destination: URL

    public init(projectKey: String, leg: PhotoSyncLeg, source: URL, destination: URL) {
        self.projectKey = projectKey
        self.leg = leg
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
    }

    /// `-r` recursive, `-t` keep modification times (exFAT and SMB reject owners and
    /// permissions), `-v` one line per transferred file to drive the progress bar,
    /// `--partial` so an unplugged disk resumes instead of restarting big RAW files.
    public var arguments: [String] {
        [
            "-rtv",
            "--partial",
            "--exclude=.DS_Store",
            "--exclude=._*",
            "--exclude=Thumbs.db",
            "--exclude=CaptureOne/Cache/",
            source.path + "/",
            destination.path
        ]
    }

    /// Checks the plan against the file system right before the copy starts.
    public func validate(fileManager: FileManager = .default) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PhotoSyncCopyError.sourceMissing(source.path)
        }
        let parent = destination.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PhotoSyncCopyError.destinationParentMissing(parent.path)
        }
        let sourcePath = source.path + "/"
        let destinationPath = destination.path + "/"
        // Copying a folder into itself (or the reverse) would recurse or clobber the source.
        if destinationPath.hasPrefix(sourcePath) || sourcePath.hasPrefix(destinationPath) {
            throw PhotoSyncCopyError.unsafeDestination(destination.path)
        }
    }

    /// `true` for rsync `-v` lines that name a transferred file (not a folder or a summary).
    public static func isTransferredFileLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasSuffix("/") else { return false }
        let summaryPrefixes = ["Transfer starting", "sent ", "total size", "building file list", "rsync:", "rsync error"]
        return !summaryPrefixes.contains { trimmed.hasPrefix($0) }
    }
}
