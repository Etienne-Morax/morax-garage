import Foundation
import Observation
import Testing
@testable import MoraxCockpitKit

/// Mock executor to simulate Higgsfield CLI responses and errors without spawning subprocesses.
private final class MockHiggsfieldCommandExecutor: HiggsfieldCommandExecuting, @unchecked Sendable {
    var executablePath: String? = "/opt/homebrew/bin/higgsfield"
    var resultStub: Result<ProcessResult, Error> = .success(
        ProcessResult(
            exitCode: 0,
            standardOutput: """
            {
              "email": "user@domain.com",
              "credits": 230.2,
              "subscription_plan_type": "creator"
            }
            """,
            standardError: ""
        )
    )
    
    var executionCount = 0
    var executedArguments: [[String]] = []
    var delayNanoseconds: UInt64 = 0
    var customHandler: (([String]) throws -> ProcessResult)?
    
    func resolveExecutablePath() -> String? {
        executablePath
    }
    
    func execute(arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        executionCount += 1
        executedArguments.append(arguments)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let handler = customHandler {
            return try handler(arguments)
        }
        return try resultStub.get()
    }
}

@Suite("Higgsfield AI Credit Gauge & Service Tests")
struct HiggsfieldCreditServiceTests {
    
    @Test("1. Parsing valid standard JSON snapshot")
    @MainActor
    func testValidJSONParsing() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                {
                  "email": "creator@higgsfield.ai",
                  "credits": 230.2,
                  "subscription_plan_type": "creator"
                }
                """,
                standardError: ""
            )
        )
        
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let service = HiggsfieldCreditService(executor: mock, now: { fixedDate })
        
        let snapshot = await service.refresh()
        #expect(snapshot != nil)
        #expect(snapshot?.credits == 230.2)
        #expect(snapshot?.plan == "creator")
        #expect(snapshot?.formattedCredits == "230.2")
        #expect(snapshot?.formattedPlan == "Creator")
        #expect(snapshot?.isStale == false)
        
        if case .live(let liveSnap) = service.state {
            #expect(liveSnap.credits == 230.2)
        } else {
            Issue.record("Expected .live state but got \(service.state)")
        }
    }
    
    @Test("2. Parsing integer and fractional decimal credits")
    @MainActor
    func testDecimalAndIntegerCredits() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                {
                  "credits": 1500,
                  "subscription_plan_type": "pro"
                }
                """,
                standardError: ""
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot?.credits == 1500.0)
        #expect(snapshot?.formattedCredits == "1500")
        #expect(snapshot?.formattedPlan == "Pro")
    }
    
    @Test("3. Zero credits is a valid 0.0 value, not nil")
    @MainActor
    func testZeroCreditsParsing() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                {
                  "credits": 0,
                  "subscription_plan_type": "free"
                }
                """,
                standardError: ""
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot != nil)
        #expect(snapshot?.credits == 0.0)
        #expect(snapshot?.formattedCredits == "0")
        #expect(snapshot?.accessibilityDescription.contains("0 crédits restants") == true)
    }
    
    @Test("4. Missing credits field is treated as malformed, not zero")
    @MainActor
    func testMissingCreditsField() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                {
                  "subscription_plan_type": "creator"
                }
                """,
                standardError: ""
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot == nil)
        
        if case .malformedResponse(let reason) = service.state {
            #expect(reason.contains("credits"))
        } else {
            Issue.record("Expected .malformedResponse but got \(service.state)")
        }
    }
    
    @Test("5. Invalid JSON response produces malformedResponse")
    @MainActor
    func testInvalidJSONParsing() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: "502 Bad Gateway: nginx",
                standardError: ""
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot == nil)
        
        if case .malformedResponse = service.state {
            #expect(true)
        } else {
            Issue.record("Expected .malformedResponse but got \(service.state)")
        }
    }
    
    @Test("6. CLI unavailable when binary cannot be resolved")
    @MainActor
    func testCLIUnavailable() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.executablePath = nil
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot == nil)
        
        if case .cliUnavailable = service.state {
            #expect(true)
        } else {
            Issue.record("Expected .cliUnavailable but got \(service.state)")
        }
    }
    
    @Test("7. Process timeout produces timeout state")
    @MainActor
    func testProcessTimeout() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .failure(ProcessRunnerError.timedOut(8.0))
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot == nil)
        
        if case .timeout = service.state {
            #expect(true)
        } else {
            Issue.record("Expected .timeout but got \(service.state)")
        }
    }
    
    @Test("8. Unauthenticated CLI error classification")
    @MainActor
    func testUnauthenticatedError() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "Error: Not logged in. Please run `higgsfield login` to authenticate."
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot == nil)
        
        if case .unauthenticated(let msg) = service.state {
            #expect(msg.contains("login"))
        } else {
            Issue.record("Expected .unauthenticated but got \(service.state)")
        }
    }
    
    @Test("9. Workspace required CLI error classification")
    @MainActor
    func testWorkspaceRequiredError() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "Error: No workspace selected. Run `higgsfield workspace set <id>`."
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        #expect(snapshot == nil)
        
        if case .workspaceRequired(let msg) = service.state {
            #expect(msg.contains("workspace"))
        } else {
            Issue.record("Expected .workspaceRequired but got \(service.state)")
        }
    }
    
    @Test("10. Last good snapshot becomes stale after an error")
    @MainActor
    func testLastGoodSnapshotBecomesStale() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                {
                  "credits": 230.2,
                  "subscription_plan_type": "creator"
                }
                """,
                standardError: ""
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        let first = await service.refresh()
        #expect(first?.credits == 230.2)
        
        // Second call fails with network/timeout error
        mock.resultStub = .failure(ProcessRunnerError.timedOut(8.0))
        let second = await service.refresh()
        #expect(second == nil)
        
        // State should now be stale, preserving the 230.2 credits!
        if case .stale(let staleSnap, let reason) = service.state {
            #expect(staleSnap.credits == 230.2)
            #expect(staleSnap.isStale == true)
            #expect(reason.contains("Délai") || reason.contains("timeout"))
        } else {
            Issue.record("Expected .stale state but got \(service.state)")
        }
    }
    
    @Test("11. Deduplication of in-flight refresh requests")
    @MainActor
    func testRefreshDeduplication() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.delayNanoseconds = 100_000_000 // 100ms
        mock.resultStub = .success(
            ProcessResult(
                exitCode: 0,
                standardOutput: """
                {
                  "credits": 500.0,
                  "subscription_plan_type": "pro"
                }
                """,
                standardError: ""
            )
        )
        
        let service = HiggsfieldCreditService(executor: mock)
        
        // Launch two concurrent refreshes
        async let first = service.refresh()
        async let second = service.refresh()
        
        let (r1, r2) = await (first, second)
        #expect(r1?.credits == 500.0)
        #expect(r2?.credits == 500.0)
        // Command should have only been executed once!
        #expect(mock.executionCount == 1)
    }
    
    @Test("12. UNKNOWN is never converted to zero (UNKNOWN != ZERO)")
    @MainActor
    func testUnknownNeverConvertedToZero() {
        let nilSnapshot = HiggsfieldCreditSnapshot(credits: nil, plan: nil)
        #expect(nilSnapshot.formattedCredits == "—")
        #expect(nilSnapshot.accessibilityDescription == "Higgsfield : crédits indisponibles")
        
        let zeroSnapshot = HiggsfieldCreditSnapshot(credits: 0.0, plan: "free")
        #expect(zeroSnapshot.formattedCredits == "0")
        #expect(zeroSnapshot.accessibilityDescription.contains("0 crédits restants"))
    }
    
    @Test("13. Relative time formatting")
    func testRelativeTimeFormatting() {
        let refDate = Date(timeIntervalSince1970: 1700000000)
        
        let snap1 = HiggsfieldCreditSnapshot(credits: 100, plan: "pro", capturedAt: refDate)
        #expect(snap1.relativeTimeLabel(at: refDate.addingTimeInterval(30)) == "à l’instant")
        #expect(snap1.relativeTimeLabel(at: refDate.addingTimeInterval(300)) == "il y a 5 min")
        #expect(snap1.relativeTimeLabel(at: refDate.addingTimeInterval(7200)) == "il y a 2 h")
    }
    
    @Test("14. Mini Cockpit HUD item resolution for Higgsfield")
    @MainActor
    func testMiniCockpitItemResolution() {
        let mock = MockHiggsfieldCommandExecutor()
        let service = HiggsfieldCreditService(executor: mock)
        
        // Before refresh
        let initialItem = MiniAICounterItem.resolveHiggsfieldItem(from: service)
        #expect(initialItem.id == "higgsfield")
        #expect(initialItem.shortName == "HF")
        #expect(initialItem.hasData == false)
        
        // After live snapshot
        let snap = HiggsfieldCreditSnapshot(credits: 230.2, plan: "creator")
        service.state = .live(snap)
        let liveItem = MiniAICounterItem.resolveHiggsfieldItem(from: service)
        #expect(liveItem.hasData == true)
        #expect(liveItem.spendAmount == 230.2)
        #expect(liveItem.spendCurrency == "CR")
        #expect(liveItem.tone == .ok)
        
        // Stale snapshot
        service.state = .stale(snap, reason: "Timeout")
        let staleItem = MiniAICounterItem.resolveHiggsfieldItem(from: service)
        #expect(staleItem.isStale == true)
        #expect(staleItem.tone == .warn)
    }
    
    @Test("15. Set and Unset workspace helpers")
    @MainActor
    func testWorkspaceHelpers() async {
        let mock = MockHiggsfieldCommandExecutor()
        let service = HiggsfieldCreditService(executor: mock)
        
        let setResult = await service.setWorkspace(id: "ws_45678")
        #expect(setResult == true)
        
        let unsetResult = await service.unsetWorkspace()
        #expect(unsetResult == true)
    }
    
    @Test("16. Auto workspace resolution when account status requires workspace")
    @MainActor
    func testAutoWorkspaceResolution() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.customHandler = { args in
            if args.contains("account") {
                return ProcessResult(
                    exitCode: 4,
                    standardOutput: "",
                    standardError: "Error: No workspace selected. Run: higgsfield workspace set <workspace_id>"
                )
            } else if args.contains("workspace") && args.contains("list") {
                return ProcessResult(
                    exitCode: 0,
                    standardOutput: """
                    [
                      {
                        "id": "ws-auto-1234",
                        "name": "Private",
                        "plan_type": "plus",
                        "credits": 1119.16,
                        "is_selected": false,
                        "user_role": "owner"
                      }
                    ]
                    """,
                    standardError: ""
                )
            } else if args.contains("workspace") && args.contains("set") {
                return ProcessResult(
                    exitCode: 0,
                    standardOutput: "Selected workspace: ws-auto-1234",
                    standardError: ""
                )
            }
            return ProcessResult(exitCode: 0, standardOutput: "{}", standardError: "")
        }
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        
        #expect(snapshot != nil)
        #expect(snapshot?.credits == 1119.16)
        #expect(snapshot?.plan == "plus")
        #expect(snapshot?.formattedPlan == "Plus")
        if case .live(let snap) = service.state {
            #expect(snap.credits == 1119.16)
        } else {
            Issue.record("Expected .live state with auto-resolved workspace but got \(service.state)")
        }
        #expect(!mock.executedArguments.contains { $0.starts(with: ["workspace", "set"]) })
    }
    
    @Test("17. A poll never changes the CLI workspace, even when none is selected")
    @MainActor
    func testPollNeverSetsWorkspace() async {
        let mock = MockHiggsfieldCommandExecutor()
        mock.customHandler = { args in
            if args.contains("account") {
                return ProcessResult(exitCode: 4, standardOutput: "", standardError: "Error: No workspace selected.")
            }
            if args.starts(with: ["workspace", "list"]) {
                return ProcessResult(exitCode: 0, standardOutput: """
                [{"id": "ws-team", "name": "Team", "plan_type": "pro", "is_selected": false, "user_role": "owner"}]
                """, standardError: "")
            }
            return ProcessResult(exitCode: 0, standardOutput: "{}", standardError: "")
        }
        
        let service = HiggsfieldCreditService(executor: mock)
        let snapshot = await service.refresh()
        
        #expect(snapshot == nil)
        #expect(service.state == .workspaceRequired("Workspace requis. Sélectionnez un workspace ci-dessous."))
        #expect(!mock.executedArguments.contains { $0.starts(with: ["workspace", "set"]) })
        #expect(mock.executionCount == 2)
    }
    
    @Test("18. A restart within the poll interval does not relaunch the CLI")
    @MainActor
    func testRestartWithinIntervalSkipsCLI() async {
        let mock = MockHiggsfieldCommandExecutor()
        let clock = MutableTestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let service = HiggsfieldCreditService(executor: mock, now: { clock.now })
        
        service.startMonitoring()
        #expect(await waitUntil { mock.executionCount == 1 })
        service.stopMonitoring()
        
        clock.advance(by: 60)
        service.startMonitoring()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(mock.executionCount == 1)
        #expect(service.state.isLive)
        service.stopMonitoring()
        
        clock.advance(by: HiggsfieldCreditService.pollingInterval)
        service.startMonitoring()
        #expect(await waitUntil { mock.executionCount == 2 })
        service.stopMonitoring()
    }
    
    @Test("19. updateInterval keeps the loop polling instead of firing once")
    @MainActor
    func testUpdateIntervalKeepsPolling() async {
        let mock = MockHiggsfieldCommandExecutor()
        let service = HiggsfieldCreditService(executor: mock)
        
        service.startMonitoring()
        #expect(await waitUntil { mock.executionCount == 1 })
        service.updateInterval(0.02)
        #expect(await waitUntil { mock.executionCount >= 4 })
        #expect(service.isRunning)
        service.stopMonitoring()
    }
    
    @Test("20. A poll that keeps failing the same way does not rewrite observed state")
    @MainActor
    func testRepeatedFailureDoesNotInvalidateObservers() async {
        let mock = MockHiggsfieldCommandExecutor()
        let service = HiggsfieldCreditService(executor: mock)
        await service.refresh()
        mock.executablePath = nil
        await service.refresh()
        #expect(service.state.isStale)
        
        let changes = ObservationCounter()
        withObservationTracking {
            _ = service.state
            _ = service.cachedSnapshot
        } onChange: {
            changes.increment()
        }
        await service.refresh()
        
        #expect(service.state.isStale)
        #expect(changes.count == 0)
    }
}

private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
