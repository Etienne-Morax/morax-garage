import Foundation
import Testing
@testable import MoraxCockpitKit

@Suite("Usage quota contract")
struct UsageQuotaDecodingTests {
    @Test("decodes a quota and a paid API without inventing a percentage")
    func decodesPayload() throws {
        let data = Data("""
        {
          "ok": true,
          "capturedAt": "2026-08-26T10:00:00.123Z",
          "gauges": [{
            "provider": "claude",
            "label": "Claude Max",
            "planType": "Max",
            "windows": [{
              "windowMinutes": 300, "label": "5 heures", "usedPercent": 42,
              "remainingPercent": 58, "resetsAt": null, "observedAt": "2026-08-26T10:00:00.123Z",
              "tone": "ok", "resetLabel": "reset non communiqué", "resetAtLabel": ""
            }],
            "worst": {
              "windowMinutes": 300, "label": "5 heures", "usedPercent": 42,
              "remainingPercent": 58, "resetsAt": null, "observedAt": "2026-08-26T10:00:00.123Z",
              "tone": "ok", "resetLabel": "reset non communiqué", "resetAtLabel": ""
            },
            "outer": {
              "windowMinutes": 300, "label": "5 heures", "usedPercent": 42,
              "remainingPercent": 58, "resetsAt": null, "observedAt": "2026-08-26T10:00:00.123Z",
              "tone": "ok", "resetLabel": "reset non communiqué", "resetAtLabel": ""
            },
            "inner": null, "tone": "ok", "observedAt": "2026-08-26T10:00:00.123Z",
            "stale": false, "observedLabel": "il y a 1 min"
          }],
          "paidApiMonthToDate": [{
            "provider": "deepseek", "label": "DeepSeek API", "costUsd": 1.2, "calls": 3,
            "totalTokens": 1200, "since": "2026-08-01T00:00:00Z", "latestAt": null,
            "balanceUsd": 8.8, "balanceCurrency": "USD", "balanceObservedAt": "2026-08-26T10:00:00Z",
            "balanceAvailable": true, "balanceSpendUsd": 0.4, "balanceSpendSince": "2026-08-10T00:00:00Z"
          }, {
            "provider": "qwen", "label": "Qwen API", "costUsd": 0.2, "calls": 1,
            "totalTokens": 100, "since": "2026-08-01T00:00:00Z", "latestAt": null,
            "balanceUsd": null, "balanceCurrency": null, "balanceObservedAt": null,
            "balanceAvailable": null, "balanceSpendUsd": null, "balanceSpendSince": null
          }]
        }
        """.utf8)
        // The production decoder: `.iso8601` rejects fractional seconds before macOS 26.
        let snapshot = try UsageQuotaService.decoder.decode(UsageQuotaSnapshot.self, from: data)
        #expect(snapshot.gauges.count == 1)
        #expect(snapshot.gauges[0].inner == nil)
        #expect(snapshot.gauges[0].windows[0].displayShortLabel == "5H")
        #expect(snapshot.paidApiMonthToDate[0].provider == "deepseek")
        #expect(snapshot.paidApiMonthToDate[0].balanceSpendUsd == 0.4)
        #expect(snapshot.paidApiMonthToDate[1].balanceUsd == nil)
    }

    @Test("decodes windows with shortLabel and resetInLabel")
    func decodesWindowsWithShortLabels() throws {
        let data = Data("""
        {
          "ok": true,
          "capturedAt": "2026-08-30T14:00:00Z",
          "gauges": [{
            "provider": "claude",
            "label": "Claude Max",
            "planType": "Subscription",
            "windows": [
              {
                "windowMinutes": 300,
                "label": "5 heures",
                "shortLabel": "5h",
                "usedPercent": 25,
                "remainingPercent": 75,
                "resetsAt": "2026-08-30T18:00:00Z",
                "observedAt": "2026-08-30T14:00:00Z",
                "tone": "ok",
                "resetLabel": "reset dans 4 h",
                "resetInLabel": "in 4 h",
                "resetAtLabel": "30 août, 18:00"
              },
              {
                "windowMinutes": 10080,
                "label": "semaine",
                "shortLabel": "week",
                "usedPercent": 76,
                "remainingPercent": 24,
                "resetsAt": "2026-09-01T15:00:00Z",
                "observedAt": "2026-08-30T14:00:00Z",
                "tone": "warn",
                "resetLabel": "reset dans 2 j",
                "resetInLabel": "in 2 j",
                "resetAtLabel": "1 sept., 15:00"
              }
            ],
            "worst": {
              "windowMinutes": 10080,
              "label": "semaine",
              "shortLabel": "week",
              "usedPercent": 76,
              "remainingPercent": 24,
              "resetsAt": "2026-09-01T15:00:00Z",
              "observedAt": "2026-08-30T14:00:00Z",
              "tone": "warn",
              "resetLabel": "reset dans 2 j",
              "resetInLabel": "in 2 j",
              "resetAtLabel": "1 sept., 15:00"
            },
            "outer": {
              "windowMinutes": 10080,
              "label": "semaine",
              "shortLabel": "week",
              "usedPercent": 76,
              "remainingPercent": 24,
              "resetsAt": "2026-09-01T15:00:00Z",
              "observedAt": "2026-08-30T14:00:00Z",
              "tone": "warn",
              "resetLabel": "reset dans 2 j",
              "resetInLabel": "in 2 j",
              "resetAtLabel": "1 sept., 15:00"
            },
            "inner": {
              "windowMinutes": 300,
              "label": "5 heures",
              "shortLabel": "5h",
              "usedPercent": 25,
              "remainingPercent": 75,
              "resetsAt": "2026-08-30T18:00:00Z",
              "observedAt": "2026-08-30T14:00:00Z",
              "tone": "ok",
              "resetLabel": "reset dans 4 h",
              "resetInLabel": "in 4 h",
              "resetAtLabel": "30 août, 18:00"
            },
            "tone": "warn",
            "observedAt": "2026-08-30T14:00:00Z",
            "stale": false,
            "observedLabel": "relevé il y a 1 min"
          }],
          "paidApiMonthToDate": []
        }
        """.utf8)
        // The production decoder: `.iso8601` rejects fractional seconds before macOS 26.
        let snapshot = try UsageQuotaService.decoder.decode(UsageQuotaSnapshot.self, from: data)
        let gauge = snapshot.gauges[0]
        #expect(gauge.windows.count == 2)
        #expect(gauge.windows[0].displayShortLabel == "5H")
        #expect(gauge.windows[0].shortLabel == "5h")
        #expect(gauge.windows[0].resetInLabel == "in 4 h")
        #expect(gauge.windows[1].displayShortLabel == "WEEK")
        #expect(gauge.windows[1].shortLabel == "week")
        #expect(gauge.windows[1].resetInLabel == "in 2 j")
        #expect(gauge.worst.windowMinutes == 10080)
        #expect(gauge.outer.windowMinutes == 10080)
        #expect(gauge.inner?.windowMinutes == 300)
    }
}

@Suite("Usage quota geometry")
struct UsageQuotaGeometryTests {
    @Test("keeps the cockpit geometry contract")
    func constantsStayFaithful() {
        #expect(UsageQuotaGeometry.center == CGPoint(x: 50, y: 46))
        #expect(UsageQuotaGeometry.outerRadius == 36)
        #expect(UsageQuotaGeometry.innerRadius == 26)
        #expect(UsageQuotaGeometry.startAngle == 135)
        #expect(UsageQuotaGeometry.sweep == 270)
        #expect(UsageQuotaGeometry.tickInnerRadius == 41)
        #expect(UsageQuotaGeometry.tickOuterRadius == 44)
        #expect(UsageQuotaGeometry.ticks == [0, 25, 50, 75, 100])
    }
}
