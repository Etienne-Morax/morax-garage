import Foundation

public struct OperationLogEntry: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let absolutePath: String
    public let action: String // "trash", "scan", "skip", "error"
    public let outcome: String // "success", "skipped", "error"
    public let details: String
    public let isError: Bool
    
    public init(
        timestamp: Date = Date(),
        absolutePath: String,
        action: String,
        outcome: String,
        details: String = "",
        isError: Bool = false
    ) {
        self.timestamp = timestamp
        self.absolutePath = absolutePath
        self.action = action
        self.outcome = outcome
        self.details = details
        self.isError = isError
    }
    
    public var formattedLine: String {
        let formatter = ISO8601DateFormatter()
        let ts = formatter.string(from: timestamp)
        return "[\(ts)] [\(action.uppercased())] [\(outcome.uppercased())] \(absolutePath) \(details)".trimmingCharacters(in: .whitespaces)
    }
    
    public static func parse(line: String) -> OperationLogEntry? {
        // [2026-08-16T15:00:00Z] [TRASH] [SUCCESS] /path/to/file details
        let parts = line.components(separatedBy: "] [")
        guard parts.count >= 3 else {
            return nil
        }
        let tsString = parts[0].replacingOccurrences(of: "[", with: "")
        let action = parts[1]
        let rest = parts[2]
        
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: tsString) ?? Date()
        
        let outcomeAndPath = rest.components(separatedBy: "] ")
        guard outcomeAndPath.count >= 2 else { return nil }
        let outcome = outcomeAndPath[0]
        let pathAndDetails = outcomeAndPath[1]
        
        let subparts = pathAndDetails.components(separatedBy: " ")
        let path = subparts.first ?? ""
        let details = subparts.dropFirst().joined(separator: " ")
        
        let upperOutcome = outcome.uppercased()
        let isErr = upperOutcome == "ERROR" || upperOutcome == "FAILED" || upperOutcome == "BLOCKED" || upperOutcome.contains("FAIL")
        return OperationLogEntry(
            timestamp: date,
            absolutePath: path,
            action: action,
            outcome: outcome,
            details: details,
            isError: isErr
        )
    }
}

public final class OperationLog: @unchecked Sendable {
    public static let shared = OperationLog()
    
    private let logDirectory: URL
    private let logFileURL: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    
    public init(customLogDirectory: URL? = nil) {
        if let custom = customLogDirectory {
            self.logDirectory = custom
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.logDirectory = home.appendingPathComponent("Library/Logs/MoraxGarage")
        }
        self.logFileURL = self.logDirectory.appendingPathComponent("operations.log")
        ensureLogDirectoryExists()
    }
    
    private func ensureLogDirectoryExists() {
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }
    
    public func append(entry: OperationLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        
        ensureLogDirectoryExists()
        let line = entry.formattedLine + "\n"
        guard let data = line.data(using: .utf8) else { return }
        
        if fileManager.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
    
    public func readEntries(errorsOnly: Bool = false) -> [OperationLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        guard fileManager.fileExists(atPath: logFileURL.path),
              let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }
        
        let lines = content.components(separatedBy: .newlines)
        var entries: [OperationLogEntry] = []
        
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if let entry = OperationLogEntry.parse(line: line) {
                if !errorsOnly || entry.isError {
                    entries.append(entry)
                }
            }
        }
        return entries.reversed() // newest first
    }
    
    public func readRawLog() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }
    
    public func pruneOlderThan(days: Int = 90) {
        lock.lock()
        defer { lock.unlock() }
        
        guard fileManager.fileExists(atPath: logFileURL.path),
              let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return
        }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let lines = content.components(separatedBy: .newlines)
        var keptLines: [String] = []
        
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if let entry = OperationLogEntry.parse(line: line) {
                if entry.timestamp >= cutoffDate {
                    keptLines.append(line)
                }
            } else {
                keptLines.append(line)
            }
        }
        
        let newContent = keptLines.joined(separator: "\n") + (keptLines.isEmpty ? "" : "\n")
        try? newContent.write(to: logFileURL, atomically: true, encoding: .utf8)
    }
    
    public var logFilePath: String {
        logFileURL.path
    }
}
