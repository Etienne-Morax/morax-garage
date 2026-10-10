import CoreGraphics

public enum UsageQuotaGeometry {
    public static let canvas = CGSize(width: 100, height: 82)
    public static let center = CGPoint(x: 50, y: 46)
    public static let outerRadius: CGFloat = 36
    public static let innerRadius: CGFloat = 26
    public static let startAngle: AngleDegrees = 135
    public static let sweep: AngleDegrees = 270
    public static let tickInnerRadius: CGFloat = 41
    public static let tickOuterRadius: CGFloat = 44
    public static let ticks = [0, 25, 50, 75, 100]
}

public typealias AngleDegrees = Double
