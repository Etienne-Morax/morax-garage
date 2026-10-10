import SwiftUI

/// Motion policy for dashboard gauge arcs.
///
/// Telemetry arrives every ~1.5 s for six dials at once. A spring that takes about
/// a second to settle keeps the dashboard producing frames almost continuously, so
/// the gauges use one short ease-out, fired only when the arc moves by a visible
/// step, and no animation at all under Reduce Motion.
public enum GaugeMotion {
    /// Number of animation steps across the full sweep (one step = 1 % of the dial).
    public static let quantizationSteps = 100
    /// Duration of the ease-out that carries the arc to its new value.
    public static let duration: TimeInterval = 0.25

    /// Animation to apply when the arc moves, or `nil` when motion is reduced.
    public static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }

    /// Value that drives `.animation(_:value:)`: it changes only when the arc moves
    /// by at least one step, so sub-step jitter is applied without starting an animation.
    public static func animationKey(for fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return Int((clamped * Double(quantizationSteps)).rounded())
    }
}
