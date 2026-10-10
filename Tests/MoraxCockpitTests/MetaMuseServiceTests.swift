import Foundation
import Testing
@testable import MoraxCockpitKit

private func makeSessionLog(model: String?, toolTerminals: Int) -> String {
    var lines: [String] = []
    if let model {
        lines.append("""
        {"payload_type":"runtime.session.metadata","payload":{"kind":"metadata","record":{"provider_id":"meta","model_id":"\(model)"}}}
        """)
    }
    for _ in 0..<toolTerminals {
        lines.append("""
        {"payload_type":"tool_batch.effect.terminal","payload":{}}
        """)
    }
    lines.append("""
    {"payload_type":"session.opened.observed","payload":{}}
    """)
    return lines.joined(separator: "\n") + "\n"
}

private struct MockExporter: MuseExportExecuting {
    var totals: MetaMuseTokenTotals = MetaMuseTokenTotals(inputTokens: 10_000, outputTokens: 2_000, cachedTokens: 4_000, reasoningTokens: 100)
    var shouldThrow = false

    func exportUsage(sessionLog: URL) async throws -> MetaMuseTokenTotals {
        if shouldThrow {
            throw MetaMuseExportError.exportFailed("boom")
        }
        return totals
    }
}

@discardableResult
private func writeSession(root: URL, name: String, content: String, modified: Date) throws -> URL {
    let dir = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("session.jsonl")
    try content.write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    return file
}

@Suite("Meta Muse Local Activity Service Tests")
struct MetaMuseServiceTests {

    @Test("1. Aggregation counts recent sessions, tool calls and models")
    @MainActor
    func testAggregationCountsRecentActivity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("metamuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        try writeSession(
            root: root, name: "recent",
            content: makeSessionLog(model: "muse-spark-1.3-contributor", toolTerminals: 3),
            modified: now
        )

        let service = MetaMuseService(sessionsRoot: root, exporter: MockExporter(), now: { now })
        let snapshot = await service.refresh()

        #expect(snapshot != nil)
        #expect(snapshot?.sessionsCount == 1)
        #expect(snapshot?.toolCallsCount == 3)
        #expect(snapshot?.models == ["muse-spark-1.3-contributor"])
        #expect(snapshot?.isStale == false)
        #expect(snapshot?.inputTokens == 10_000)
        #expect(snapshot?.outputTokens == 2_000)
        #expect(snapshot?.cachedTokens == 4_000)
        // Contributor pricing: (6000 * 0.10 + 4000 * 0.10 + 2000 * 0.20) / 1e6
        #expect(abs((snapshot?.estimatedSpendUSD ?? -1) - 0.0014) < 1e-9)
        if case .live(let liveSnap) = service.state {
            #expect(liveSnap.sessionsCount == 1)
        } else {
            Issue.record("Expected .live state but got \(service.state)")
        }
    }

    @Test("2. Sessions older than 7 days are excluded")
    @MainActor
    func testOldSessionsExcluded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("metamuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        try writeSession(
            root: root, name: "recent",
            content: makeSessionLog(model: "muse-spark-1.2", toolTerminals: 2),
            modified: now
        )
        try writeSession(
            root: root, name: "old",
            content: makeSessionLog(model: "muse-spark-1.1", toolTerminals: 9),
            modified: now.addingTimeInterval(-8 * 24 * 3_600)
        )

        let service = MetaMuseService(sessionsRoot: root, exporter: MockExporter(), now: { now })
        let snapshot = await service.refresh()

        #expect(snapshot?.sessionsCount == 1)
        #expect(snapshot?.toolCallsCount == 2)
        #expect(snapshot?.models == ["muse-spark-1.2"])
        // Standard pricing: (6000 * 1.25 + 4000 * 0.15 + 2000 * 4.25) / 1e6
        #expect(abs((snapshot?.estimatedSpendUSD ?? -1) - 0.0166) < 1e-9)
    }

    @Test("3. Missing sessions directory yields unavailable state")
    @MainActor
    func testMissingDirectoryIsUnavailable() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("metamuse-missing-\(UUID().uuidString)", isDirectory: true)
        let service = MetaMuseService(sessionsRoot: missing, now: { Date() })
        let snapshot = await service.refresh()

        #expect(snapshot == nil)
        if case .unavailable = service.state {
        } else {
            Issue.record("Expected .unavailable state but got \(service.state)")
        }
    }

    @Test("4. Export failure without cache yields error state")
    @MainActor
    func testExportFailureIsError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("metamuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        try writeSession(
            root: root, name: "recent",
            content: makeSessionLog(model: "muse-spark-1.2", toolTerminals: 1),
            modified: now
        )

        let service = MetaMuseService(
            sessionsRoot: root,
            exporter: MockExporter(shouldThrow: true),
            now: { now }
        )
        let snapshot = await service.refresh()

        #expect(snapshot == nil)
        if case .error = service.state {
        } else {
            Issue.record("Expected .error state but got \(service.state)")
        }
    }

    @Test("5. parseExport counts model_completed only")
    func testParseExportCountsModelCompleted() throws {
        let doc: [String: Any] = [
            "events": [
                ["envelope": ["payload": ["event": [
                    "kind": "model_completed",
                    "usage": ["input_tokens": 1000, "output_tokens": 200, "cached_tokens": 300, "reasoning_tokens": 40]
                ]]]],
                ["envelope": ["payload": ["event": [
                    "kind": "goal_usage_attribution",
                    "record": ["quantity": ["input_tokens": 1000, "output_tokens": 200]]
                ]]]],
                ["envelope": ["payload": ["event": ["kind": "status"]]]]
            ]
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metamuse-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: doc).write(to: url)

        let totals = try MuseExportRunner.parseExport(at: url)
        #expect(totals == MetaMuseTokenTotals(inputTokens: 1000, outputTokens: 200, cachedTokens: 300, reasoningTokens: 40))
    }

    @Test("6. Manual quota clamps, formats and stamps")
    func testManualQuotaHelpers() {
        #expect(MetaMuseManualQuota.clamped(-5) == 0)
        #expect(MetaMuseManualQuota.clamped(137) == 100)
        #expect(MetaMuseManualQuota.formatted(10.4) == "10 %")
        #expect(MetaMuseManualQuota.updatedLabel(at: nil) == "À renseigner dans Réglages")
        let now = Date()
        #expect(MetaMuseManualQuota.updatedLabel(at: now.addingTimeInterval(-90), now: now) == "Relevé manuel • il y a 1 min")
    }

    @Test("7. Snapshot labels degrade gracefully without activity")
    func testEmptySnapshotLabels() {
        let snapshot = MetaMuseSnapshot(
            sessionsCount: 0,
            toolCallsCount: 0,
            models: [],
            lastActivityAt: nil,
            capturedAt: Date(),
            isStale: false
        )
        #expect(snapshot.modelsLabel == "—")
        #expect(snapshot.lastActivityLabel() == "Aucune session")
        #expect(snapshot.formattedTotalTokens == "0")
        #expect(snapshot.formattedSpendUSD == "$0.00")
        #expect(snapshot.cachedShare == 0)
    }
}

@Suite("Meta Muse Usage Page URL Tests")
struct MetaMuseUsagePageTests {

    @Test("8. Usage URL carries project and team IDs")
    func testUsageURL() {
        let url = MetaMuseUsagePage.url(projectID: "1234567890", teamID: "987654321")
        #expect(url?.absoluteString == "https://dev.meta.ai/usage/?project_id=1234567890&team_id=987654321")
    }

    @Test("9. Blank IDs yield no URL")
    func testBlankIDsYieldNil() {
        #expect(MetaMuseUsagePage.url(projectID: "  ", teamID: "987654321") == nil)
        #expect(MetaMuseUsagePage.url(projectID: "1234567890", teamID: "") == nil)
    }
}
