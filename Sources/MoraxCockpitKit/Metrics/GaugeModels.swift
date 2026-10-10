import Foundation
import SwiftUI

public struct CockpitGaugeStyle: Sendable, Equatable, Hashable {
    public static let standard = CockpitGaugeStyle()
    public static let `default` = CockpitGaugeStyle()
    
    public var id: String { "default" }
    public var iconName: String { "gauge.with.needle.fill" }
    
    public var primaryAccentHex: String { "#EF4444" }
    public var secondaryAccentHex: String { "#F59E0B" }
    public var safeArcHex: String { "#10B981" }
    public var warningArcHex: String { "#F59E0B" }
    public var criticalArcHex: String { "#DC2626" }
    public var needleColor: Color { Color(hex: "#FF3B30") }
    
    public var bezelGradientColors: [Color] {
        [
            Color(hex: "#54192D"),
            Color(hex: "#280A15"),
            Color(hex: "#1A050D"),
            Color(hex: "#0E0207")
        ]
    }
    
    public init() {}
}

public enum GaugeZoneStatus: String, Sendable, Equatable {
    case safe = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

public struct GaugeZone: Identifiable, Sendable, Equatable {
    public var id: String { "\(startFraction)-\(endFraction)-\(colorHex)" }
    public let startFraction: Double
    public let endFraction: Double
    public let colorHex: String
    
    public init(startFraction: Double, endFraction: Double, colorHex: String) {
        self.startFraction = max(0, min(1, startFraction))
        self.endFraction = max(0, min(1, endFraction))
        self.colorHex = colorHex
    }
}

public struct GaugeTick: Identifiable, Sendable, Equatable {
    public var id: String { "\(fraction)-\(isMajor)-\(label)" }
    public let value: Double
    public let fraction: Double
    public let label: String
    public let isMajor: Bool
    
    public init(value: Double, fraction: Double, label: String, isMajor: Bool) {
        self.value = value
        self.fraction = fraction
        self.label = label
        self.isMajor = isMajor
    }
}

public struct AutomotiveGaugeConfig: Sendable, Equatable {
    public let title: String
    public let unit: String
    public let minValue: Double
    public let maxValue: Double
    public let warningThreshold: Double?
    public let criticalThreshold: Double?
    public let majorTicksCount: Int
    public let minorTicksPerInterval: Int
    public let displayDecimals: Int
    public let isInverted: Bool
    public let zones: [GaugeZone]
    public let startAngle: Double // Degrees (0 = 3 o'clock, 90 = 6 o'clock, 135/145 = 7 o'clock)
    public let sweepAngle: Double // Angular span in degrees (e.g. 250° for authentic automotive dial)
    public let ticks: [GaugeTick]
    
    public init(
        title: String,
        unit: String,
        minValue: Double = 0.0,
        maxValue: Double = 100.0,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil,
        majorTicksCount: Int = 4, // e.g. 4 intervals = 5 major tick marks (0, 25, 50, 75, 100)
        minorTicksPerInterval: Int = 3,
        displayDecimals: Int = 1,
        isInverted: Bool = false,
        customZones: [GaugeZone]? = nil,
        startAngle: Double = 145.0,
        sweepAngle: Double = 250.0
    ) {
        self.title = title
        self.unit = unit
        self.minValue = minValue
        let safeMax = max(minValue + 0.0001, maxValue)
        self.maxValue = safeMax
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        let safeMajor = max(1, majorTicksCount)
        self.majorTicksCount = safeMajor
        let safeMinor = max(0, minorTicksPerInterval)
        self.minorTicksPerInterval = safeMinor
        self.displayDecimals = max(0, displayDecimals)
        self.isInverted = isInverted
        self.startAngle = startAngle
        self.sweepAngle = sweepAngle
        
        let range = safeMax - minValue
        if let custom = customZones {
            self.zones = custom
        } else {
            if isInverted {
                // Inverted gauge (e.g. 200 GB Headroom buffer / battery reserve):
                // Low values are critical redline, medium values are warning amber, high values are safe green
                let critFrac: Double
                if let c = criticalThreshold {
                    critFrac = max(0, min(1, (c - minValue) / range))
                } else {
                    critFrac = 0.25
                }
                
                let warnFrac: Double
                if let w = warningThreshold {
                    warnFrac = max(critFrac, min(1, (w - minValue) / range))
                } else {
                    warnFrac = 0.50
                }
                
                var computedZones: [GaugeZone] = []
                if critFrac > 0 {
                    computedZones.append(GaugeZone(startFraction: 0.0, endFraction: critFrac, colorHex: "#E11D48")) // Critical Ruby
                }
                if warnFrac > critFrac {
                    computedZones.append(GaugeZone(startFraction: critFrac, endFraction: warnFrac, colorHex: "#F59E0B")) // Warning Amber
                }
                if warnFrac < 1.0 {
                    computedZones.append(GaugeZone(startFraction: warnFrac, endFraction: 1.0, colorHex: "#10B981")) // Safe Green
                }
                self.zones = computedZones
            } else {
                // Standard gauge: Low values are safe green, medium values are warning amber, high values are critical red
                let warnFrac: Double
                if let w = warningThreshold {
                    warnFrac = max(0, min(1, (w - minValue) / range))
                } else {
                    warnFrac = 0.70
                }
                
                let critFrac: Double
                if let c = criticalThreshold {
                    critFrac = max(warnFrac, min(1, (c - minValue) / range))
                } else {
                    critFrac = 0.90
                }
                
                var computedZones: [GaugeZone] = []
                if warnFrac > 0 {
                    computedZones.append(GaugeZone(startFraction: 0.0, endFraction: warnFrac, colorHex: "#10B981")) // Success Green
                }
                if critFrac > warnFrac {
                    computedZones.append(GaugeZone(startFraction: warnFrac, endFraction: critFrac, colorHex: "#F59E0B")) // Warning Amber
                }
                if critFrac < 1.0 {
                    computedZones.append(GaugeZone(startFraction: critFrac, endFraction: 1.0, colorHex: "#E11D48")) // Critical Ruby
                }
                self.zones = computedZones
            }
        }
        
        // Precompute and memoize ticks
        var generatedTicks: [GaugeTick] = []
        for i in 0...safeMajor {
            let frac = Double(i) / Double(safeMajor)
            let val = minValue + frac * range
            let label: String
            if val.truncatingRemainder(dividingBy: 1) == 0 || safeMax >= 100 {
                label = String(format: "%.0f", val)
            } else if safeMax <= 10 {
                label = String(format: "%.1f", val)
            } else {
                label = String(format: "%.0f", val)
            }
            generatedTicks.append(GaugeTick(value: val, fraction: frac, label: label, isMajor: true))
            
            // Generate minor ticks between this major tick and the next
            if i < safeMajor && safeMinor > 0 {
                let stepFrac = 1.0 / Double(safeMajor)
                let subStepFrac = stepFrac / Double(safeMinor + 1)
                for j in 1...safeMinor {
                    let subFrac = frac + Double(j) * subStepFrac
                    let subVal = minValue + subFrac * range
                    generatedTicks.append(GaugeTick(value: subVal, fraction: subFrac, label: "", isMajor: false))
                }
            }
        }
        self.ticks = generatedTicks
    }
    
    /// Normalizes any input value into a 0.0 ... 1.0 range clamped within min and max
    public func fraction(for value: Double) -> Double {
        guard !value.isNaN && !value.isInfinite else { return 0 }
        let clamped = min(max(value, minValue), maxValue)
        let range = maxValue - minValue
        guard range > 0 else { return 0 }
        return (clamped - minValue) / range
    }
    
    /// Converts a value to an angle in degrees along the dial sweep
    public func angleDegrees(for value: Double) -> Double {
        let frac = fraction(for: value)
        return startAngle + frac * sweepAngle
    }
    
    /// Converts a fraction (0...1) to an angle in degrees
    public func angleDegrees(forFraction fraction: Double) -> Double {
        let clamped = max(0, min(1, fraction))
        return startAngle + clamped * sweepAngle
    }
    
    /// Returns the active zone status for a given value
    public func zoneStatus(for value: Double) -> GaugeZoneStatus {
        guard !value.isNaN && !value.isInfinite else { return .safe }
        if isInverted {
            if let crit = criticalThreshold, value <= crit {
                return .critical
            }
            if let warn = warningThreshold, value <= warn {
                return .warning
            }
            let frac = fraction(for: value)
            if frac <= 0.25 {
                return .critical
            } else if frac <= 0.50 {
                return .warning
            }
            return .safe
        } else {
            if let crit = criticalThreshold, value >= crit {
                return .critical
            }
            if let warn = warningThreshold, value >= warn {
                return .warning
            }
            // Fallback to fraction thresholds
            let frac = fraction(for: value)
            if frac >= 0.90 {
                return .critical
            } else if frac >= 0.70 {
                return .warning
            }
            return .safe
        }
    }
    
    /// Returns major and minor ticks with exact values, fractions, and numeric labels
    public func generateTicks() -> [GaugeTick] {
        return ticks
    }
    
    /// Formats the primary digital readout
    public func formatValue(_ value: Double) -> String {
        guard !value.isNaN && !value.isInfinite else { return "0 \(unit)" }
        let clamped = min(max(value, minValue), maxValue)
        if displayDecimals == 0 {
            return String(format: "%.0f %@", clamped, unit)
        } else {
            return String(format: "%.\(displayDecimals)f %@", clamped, unit)
        }
    }
    
    /// Formats numeric value only (without unit)
    public func formatNumberOnly(_ value: Double) -> String {
        guard !value.isNaN && !value.isInfinite else { return "0" }
        let clamped = min(max(value, minValue), maxValue)
        if displayDecimals == 0 {
            return String(format: "%.0f", clamped)
        } else {
            return String(format: "%.\(displayDecimals)f", clamped)
        }
    }
}
