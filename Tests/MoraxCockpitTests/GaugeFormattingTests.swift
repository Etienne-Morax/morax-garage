import Foundation
import Testing
@testable import MoraxCockpitKit

struct GaugeFormattingTests {
    @Test("the frequency formatter is built once and reused across samples")
    func formatterIsCached() {
        #expect(GaugeFormatting.frequencyFormatter === GaugeFormatting.frequencyFormatter)
    }

    @Test("frequencies are rounded to whole MHz with locale grouping")
    func formatsRoundedMegahertz() {
        let expected = GaugeFormatting.frequencyFormatter.string(from: NSNumber(value: 1398)) ?? "1398"
        #expect(GaugeFormatting.frequency(mhz: 1397.6) == "\(expected) MHz")
        #expect(GaugeFormatting.frequency(mhz: 0) == "0 MHz")
    }

    @Test("a non-finite frequency does not trap")
    func nonFiniteFrequencyIsHandled() {
        #expect(GaugeFormatting.frequency(mhz: .nan) == "— MHz")
        #expect(GaugeFormatting.frequency(mhz: .infinity) == "— MHz")
    }
}
