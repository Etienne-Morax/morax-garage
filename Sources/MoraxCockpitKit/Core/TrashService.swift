import Foundation

public struct TrashItemResult: Sendable, Equatable {
    public let sourceURL: URL
    public let trashedURL: URL?
    public let sizeBytes: Int64
    public let isSuccess: Bool
    public let error: String?
}

public struct TrashBatchResult: Sendable, Equatable {
    public let attemptedCount: Int
    public let succeededCount: Int
    public let skippedCount: Int
    public let totalReclaimedBytes: Int64
    public let items: [TrashItemResult]
    public let errors: [String]
    
    public init(
        attemptedCount: Int,
        succeededCount: Int,
        skippedCount: Int,
        totalReclaimedBytes: Int64,
        items: [TrashItemResult],
        errors: [String]
    ) {
        self.attemptedCount = attemptedCount
        self.succeededCount = succeededCount
        self.skippedCount = skippedCount
        self.totalReclaimedBytes = totalReclaimedBytes
        self.items = items
        self.errors = errors
    }
}

/// One item of a trash batch, validated against its own containment root.
public struct TrashRequest: Sendable, Equatable {
    public let url: URL
    /// Directory the item must still resolve inside; `nil` skips the containment check.
    public let scanRoot: URL?

    public init(url: URL, scanRoot: URL?) {
        self.url = url
        self.scanRoot = scanRoot
    }
}

public final class TrashService: Sendable {
    public static let shared = TrashService()

    /// Moves one item to the Trash and returns where it landed.
    public typealias FileTrasher = @Sendable (URL) throws -> URL?

    /// Production trasher: `FileManager.trashItem`, the only removal primitive allowed.
    public static let systemTrasher: FileTrasher = { url in
        var resultingURL: NSURL? = nil
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    private let operationLog: OperationLog
    private let fileTrasher: FileTrasher

    /// - Parameter fileTrasher: injection point for tests, so fixtures never reach the user's Trash.
    public init(operationLog: OperationLog = .shared, fileTrasher: FileTrasher? = nil) {
        self.operationLog = operationLog
        self.fileTrasher = fileTrasher ?? Self.systemTrasher
    }
    
    private var fileManager: FileManager {
        FileManager.default
    }
    
    /// Trashes a single file safely through SafetyGate and FileManager.trashItem.
    public func trashItem(url: URL, scanRoot: URL? = nil) throws -> TrashItemResult {
        // TOCTOU validation immediately before trashing
        do {
            try SafetyGate.validateForTrash(url: url, scanRoot: scanRoot)
        } catch {
            operationLog.append(entry: OperationLogEntry(
                absolutePath: url.path,
                action: "trash",
                outcome: "blocked",
                details: error.localizedDescription,
                isError: true
            ))
            throw error
        }
        
        let size = calculateSize(url: url)

        do {
            // Rule 1: Always FileManager.trashItem (through the injected trasher)
            let trashed = try fileTrasher(url)
            operationLog.append(entry: OperationLogEntry(
                absolutePath: url.path,
                action: "trash",
                outcome: "success",
                details: "trashedTo=\(trashed?.path ?? "Trash") sizeBytes=\(size)"
            ))
            
            return TrashItemResult(
                sourceURL: url,
                trashedURL: trashed,
                sizeBytes: size,
                isSuccess: true,
                error: nil
            )
        } catch {
            operationLog.append(entry: OperationLogEntry(
                absolutePath: url.path,
                action: "trash",
                outcome: "failed",
                details: error.localizedDescription,
                isError: true
            ))
            return TrashItemResult(
                sourceURL: url,
                trashedURL: nil,
                sizeBytes: size,
                isSuccess: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Trashes a batch of files in chunks of 5,000, honoring Task cancellation.
    ///
    /// The whole batch is validated up front against `scanRoot`: one refused item aborts it.
    public func trashBatch(
        urls: [URL],
        scanRoot: URL? = nil,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> TrashBatchResult {
        try SafetyGate.validateBatch(urls: urls, scanRoot: scanRoot)
        let requests = urls.map { TrashRequest(url: $0, scanRoot: scanRoot) }
        return try processBatch(requests, progressHandler: progressHandler)
    }

    /// Trashes a batch where every item carries its own containment root.
    ///
    /// Only the batch-wide caps abort the call. Each item is then validated on its own
    /// immediately before trashing; a refused item is reported as skipped (with its
    /// error) and the rest of the batch proceeds.
    public func trashBatch(
        requests: [TrashRequest],
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> TrashBatchResult {
        try SafetyGate.validateBatchLimits(urls: requests.map(\.url))
        return try processBatch(requests, progressHandler: progressHandler)
    }

    private func processBatch(
        _ requests: [TrashRequest],
        progressHandler: (@Sendable (Int, Int) -> Void)?
    ) throws -> TrashBatchResult {
        var results: [TrashItemResult] = []
        var errors: [String] = []
        var succeededCount = 0
        var skippedCount = 0
        var totalReclaimed: Int64 = 0
        
        let chunkSize = 5_000
        let chunks = stride(from: 0, to: requests.count, by: chunkSize).map {
            Array(requests[$0..<min($0 + chunkSize, requests.count)])
        }

        var processedSoFar = 0

        for chunk in chunks {
            try Task.checkCancellation()

            for request in chunk {
                try Task.checkCancellation()
                let url = request.url

                do {
                    let result = try trashItem(url: url, scanRoot: request.scanRoot)
                    results.append(result)
                    if result.isSuccess {
                        succeededCount += 1
                        totalReclaimed += result.sizeBytes
                    } else {
                        skippedCount += 1
                        if let err = result.error {
                            errors.append("\(url.path): \(err)")
                        }
                    }
                } catch {
                    skippedCount += 1
                    errors.append("\(url.path): \(error.localizedDescription)")
                }
                
                processedSoFar += 1
                progressHandler?(processedSoFar, requests.count)
            }
        }

        return TrashBatchResult(
            attemptedCount: requests.count,
            succeededCount: succeededCount,
            skippedCount: skippedCount,
            totalReclaimedBytes: totalReclaimed,
            items: results,
            errors: errors
        )
    }
    
    /// Computes recursive size of a file or directory on disk
    public func calculateSize(url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return 0
        }
        
        if !isDir.boolValue {
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }
        
        var totalSize: Int64 = 0
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let isDirectory = values.isDirectory,
                  !isDirectory else {
                continue
            }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            totalSize += size
        }
        return totalSize
    }
}
