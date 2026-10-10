import XCTest
import Foundation
import os
@testable import MoraxCockpitKit

final class ProcessRunnerTests: XCTestCase {
    
    func testRunEchoCommand() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["Hello", "Morax"]
        )
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.standardOutput.contains("Hello Morax"))
    }
    
    func testStreamLinesEcho() async {
        let runner = ProcessRunner()
        let stream = runner.streamLines(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["Line1\nLine2\nLine3\n"]
        )
        
        var receivedLines: [String] = []
        for await line in stream {
            receivedLines.append(line)
        }
        
        XCTAssertTrue(receivedLines.contains("Line1"))
        XCTAssertTrue(receivedLines.contains("Line2"))
        XCTAssertTrue(receivedLines.contains("Line3"))
    }
    
    func testStreamLinesDeliversEveryLineInOrder() async {
        let runner = ProcessRunner()
        let stream = runner.streamLines(
            executableURL: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "20000"]
        )

        var receivedLines: [String] = []
        for await line in stream {
            receivedLines.append(line)
        }

        XCTAssertEqual(receivedLines, (1...20000).map(String.init))
    }

    func testProcessTimeout() async {
        let runner = ProcessRunner()
        do {
            _ = try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.2
            )
            XCTFail("Should have timed out or terminated")
        } catch {
            // Expected to terminate or error
        }
    }
    
    func testTerminateAllKillsActiveProcesses() async throws {
        let runner = ProcessRunner()
        let streamTask = Task {
            let stream = runner.streamLines(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"]
            )
            for await _ in stream {
                // Keep stream active
            }
        }
        
        // Wait briefly for process to spawn
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Terminate all processes
        runner.terminateAll()
        
        // Task should finish promptly because sleep was killed
        let completedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await streamTask.result
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return false
            }
            return await group.next() ?? false
        }
        
        XCTAssertTrue(completedInTime, "Stream task should complete quickly after terminateAll")
    }

    func testStreamProcessWaitsForExitAndKillsAProcessThatIgnoresSIGTERM() async throws {
        let runner = ProcessRunner()
        let process = runner.streamProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; echo ready; exec /bin/sleep 10"],
            terminationGracePeriod: 0.2
        )
        let isReady = OSAllocatedUnfairLock(initialState: false)
        let reader = Task {
            for await line in process.lines where line == "ready" {
                isReady.withLock { $0 = true }
            }
        }
        let readyDeadline = Date().addingTimeInterval(5)
        while !isReady.withLock({ $0 }) {
            guard Date() < readyDeadline else { return XCTFail("The process never printed ready") }
            try await Task.sleep(for: .milliseconds(10))
        }

        let start = Date()
        reader.cancel()
        await process.waitUntilExit()

        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
