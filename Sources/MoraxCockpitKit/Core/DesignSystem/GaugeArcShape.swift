import SwiftUI

/// Circular arc used by the dashboard gauges.
///
/// `sweepAngle` is animatable so the arc itself interpolates to a new value
/// instead of snapping while only its tip dot moves.
public struct GaugeArcShape: Shape {
    public let startAngle: Double
    public var sweepAngle: Double
    public let center: CGPoint
    public let radius: CGFloat

    public init(startAngle: Double, sweepAngle: Double, center: CGPoint, radius: CGFloat) {
        self.startAngle = startAngle
        self.sweepAngle = sweepAngle
        self.center = center
        self.radius = radius
    }

    public var animatableData: Double {
        get { sweepAngle }
        set { sweepAngle = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = Angle.degrees(startAngle)
        let end = Angle.degrees(startAngle + sweepAngle)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}
