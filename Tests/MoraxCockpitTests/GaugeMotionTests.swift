import SwiftUI
import Testing
@testable import MoraxCockpitKit

struct GaugeMotionTests {
    @Test("Reduce Motion disables the gauge arc animation")
    func reduceMotionDisablesAnimation() {
        #expect(GaugeMotion.animation(reduceMotion: true) == nil)
    }

    @Test("gauges use a short ease-out instead of a long-settling spring")
    func usesShortEaseOut() {
        #expect(GaugeMotion.animation(reduceMotion: false) == .easeOut(duration: GaugeMotion.duration))
        #expect(GaugeMotion.duration <= 0.3)
    }

    @Test("sub-step jitter between samples does not start a new animation")
    func subStepJitterKeepsTheSameKey() {
        #expect(GaugeMotion.animationKey(for: 0.421) == GaugeMotion.animationKey(for: 0.423))
    }

    @Test("a visible move of the arc starts an animation")
    func visibleMoveChangesTheKey() {
        #expect(GaugeMotion.animationKey(for: 0.40) != GaugeMotion.animationKey(for: 0.42))
    }

    @Test("animation keys stay bounded for out-of-range and non-finite fractions")
    func keysAreClamped() {
        #expect(GaugeMotion.animationKey(for: -1) == 0)
        #expect(GaugeMotion.animationKey(for: 2) == GaugeMotion.quantizationSteps)
        #expect(GaugeMotion.animationKey(for: .nan) == 0)
        #expect(GaugeMotion.animationKey(for: .infinity) == 0)
    }

    @Test("the gauge arc interpolates its sweep instead of snapping")
    func arcSweepIsAnimatable() {
        var arc = GaugeArcShape(startAngle: 140, sweepAngle: 0, center: .zero, radius: 10)
        arc.animatableData = 130

        #expect(arc.sweepAngle == 130)
        #expect(arc.animatableData == 130)
    }
}
