import Foundation
import os

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let isSuccess: Bool
    
    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.isSuccess = (exitCode == 0)
    }
}

public enum ProcessRunnerError: Error, LocalizedError {
    case processLaunchFailed(String)
    case timedOut(TimeInterval)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let msg):
            return "Process launch failed: \(msg)"
        case .timedOut(let seconds):
            return "Process timed out after \(seconds) seconds."
        case .cancelled:
            return "Process execution was cancelled."
        }
    }
}

public final class ProcessRunner: Sendable {
    public static let shared = ProcessRunner()
    
    public init() {}
    
    /// Terminates all currently active processes spawned by ProcessRunner.
    public func terminateAll() {
        ProcessRegistry.shared.terminateAll()
    }
    
    /// Executes a command and returns an AsyncStream of stdout/stderr lines.
    /// Does not buffer all lines in memory.
    public func streamLines(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) -> AsyncStream<String> {
        streamProcess(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL
        ).lines
    }

    /// Like `streamLines`, but also lets the caller wait until the process has exited.
    /// Ending the stream early sends SIGTERM, then SIGKILL after `terminationGracePeriod`.
    public func streamProcess(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        terminationGracePeriod: TimeInterval = StreamingProcess.defaultTerminationGracePeriod
    ) -> StreamingProcess {
        let exitSignal = ProcessExitSignal()
        let lines = AsyncStream<String> { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            if let env = environment {
                process.environment = env
            }
            if let cwd = currentDirectoryURL {
                process.currentDirectoryURL = cwd
            }
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            let fileHandle = pipe.fileHandleForReading

            // A single reader drains the pipe in order until EOF. Per-chunk Tasks could
            // reorder chunks and race the final flush, dropping lines.
            DispatchQueue.global(qos: .utility).async {
                var splitter = LineSplitter(continuation: continuation)
                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty { break }
                    splitter.append(data)
                }
                splitter.finish()
            }

            process.terminationHandler = { proc in
                ProcessRegistry.shared.unregister(proc)
                exitSignal.markExited()
            }

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + terminationGracePeriod) {
                        guard process.isRunning else { return }
                        TelemetryLogger.process.warning("Streaming process \(executableURL.lastPathComponent, privacy: .public) ignored SIGTERM, killing it")
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                ProcessRegistry.shared.unregister(process)
            }
            
            do {
                ProcessRegistry.shared.register(process)
                try process.run()
            } catch {
                ProcessRegistry.shared.unregister(process)
                // No child holds the write end, so close ours to give the reader its EOF.
                try? pipe.fileHandleForWriting.close()
                TelemetryLogger.process.error("Failed to run streaming process \(executableURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                exitSignal.markExited()
                continuation.finish()
            }
        }
        return StreamingProcess(lines: lines, waitUntilExit: { await exitSignal.wait() })
    }
    
    /// Executes a command synchronously within an async context, with timeout and cancellation support.
    public func run(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval = 120.0
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        if let cwd = currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        let timeoutBox = ProcessTimeoutBox()
        
        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { proc in
                        ProcessRegistry.shared.unregister(proc)
                        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        
                        let stdout = String(data: outData, encoding: .utf8) ?? ""
                        let stderr = String(data: errData, encoding: .utf8) ?? ""
                        
                        continuation.resume(returning: ProcessResult(
                            exitCode: proc.terminationStatus,
                            standardOutput: stdout,
                            standardError: stderr
                        ))
                    }
                    
                    do {
                        ProcessRegistry.shared.register(process)
                        try process.run()
                    } catch {
                        ProcessRegistry.shared.unregister(process)
                        continuation.resume(throwing: ProcessRunnerError.processLaunchFailed(error.localizedDescription))
                    }
                }
            }
            
            group.addTask {
                let nanoseconds = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                timeoutBox.markTimedOut()
                if process.isRunning {
                    TelemetryLogger.process.warning("Process \(executableURL.lastPathComponent, privacy: .public) timed out after \(timeout)s, terminating...")
                    process.terminate()
                }
                throw ProcessRunnerError.timedOut(timeout)
            }
            
            do {
                let result = try await group.next()!
                group.cancelAll()
                if timeoutBox.isTimedOut {
                    throw ProcessRunnerError.timedOut(timeout)
                }
                if !result.isSuccess {
                    TelemetryLogger.process.warning("Process \(executableURL.lastPathComponent, privacy: .public) exited with code \(result.exitCode)")
                }
                return result
            } catch {
                if process.isRunning {
                    process.terminate()
                }
                group.cancelAll()
                throw error
            }
        }
    }
}

/// A running process's output lines plus a way to wait for the process itself to exit.
public struct StreamingProcess: Sendable {
    public static let defaultTerminationGracePeriod: TimeInterval = 5

    public let lines: AsyncStream<String>
    /// Returns once the process has exited (immediately if it never launched).
    /// Not cancellable: a caller that must not overlap the process waits it out.
    public let waitUntilExit: @Sendable () async -> Void

    public init(lines: AsyncStream<String>, waitUntilExit: @escaping @Sendable () async -> Void) {
        self.lines = lines
        self.waitUntilExit = waitUntilExit
    }
}

/// Resumes every waiter once the process has exited, including waiters that arrive later.
private final class ProcessExitSignal: Sendable {
    private struct State {
        var hasExited = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    func markExited() {
        let waiters = state.withLockUnchecked { state -> [CheckedContinuation<Void, Never>] in
            state.hasExited = true
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let hasExited = state.withLockUnchecked { state -> Bool in
                if !state.hasExited { state.waiters.append(continuation) }
                return state.hasExited
            }
            if hasExited { continuation.resume() }
        }
    }
}

private final class ProcessTimeoutBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _timedOut = false
    
    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _timedOut
    }
    
    func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        _timedOut = true
    }
}

private final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var processes: Set<Process> = []
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NSApplicationWillTerminateNotification"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.terminateAll()
        }
        
        atexit {
            ProcessRegistry.shared.terminateAll()
        }
    }
    
    func register(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processes.insert(process)
    }
    
    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processes.remove(process)
    }
    
    func terminateAll() {
        lock.lock()
        let toTerminate = Array(processes)
        processes.removeAll()
        lock.unlock()
        
        for proc in toTerminate {
            if proc.isRunning {
                proc.terminate()
            }
        }
    }
}

/// Splits a byte stream into lines. Owned by one reader, so it needs no isolation.
private struct LineSplitter {
    private var buffer = Data()
    private let continuation: AsyncStream<String>.Continuation

    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    mutating func append(_ data: Data) {
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) { // '\n'
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            if let line = Self.decode(lineData) {
                continuation.yield(line)
            }
        }
    }

    mutating func finish() {
        if let line = Self.decode(buffer), !line.isEmpty {
            continuation.yield(line)
        }
        buffer.removeAll()
        continuation.finish()
    }

    private static func decode(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.hasSuffix("\r") ? String(text.dropLast()) : text
    }
}
