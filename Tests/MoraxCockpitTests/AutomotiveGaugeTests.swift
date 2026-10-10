import XCTest
@testable import MoraxCockpitKit

final class AutomotiveGaugeTests: XCTestCase {
    
    func testFractionCalculationForStandardPercentage() {
        let config = AutomotiveGaugeConfig(
            title: "CPU",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 70,
            criticalThreshold: 90
        )
        
        XCTAssertEqual(config.fraction(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(config.fraction(for: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(config.fraction(for: 100), 1.0, accuracy: 0.0001)
    }
    
    func testFractionClampingBelowMinAndAboveMax() {
        let config = AutomotiveGaugeConfig(
            title: "RAM",
            unit: "GB",
            minValue: 0,
            maxValue: 36
        )
        
        XCTAssertEqual(config.fraction(for: -10), 0.0, accuracy: 0.0001)
        XCTAssertEqual(config.fraction(for: 50), 1.0, accuracy: 0.0001)
        XCTAssertEqual(config.fraction(for: Double.nan), 0.0, accuracy: 0.0001)
        XCTAssertEqual(config.fraction(for: Double.infinity), 0.0, accuracy: 0.0001)
    }
    
    func testAngleConversionForSemicircleSweep() {
        let config = AutomotiveGaugeConfig(
            title: "Power",
            unit: "W",
            minValue: 0,
            maxValue: 100,
            startAngle: 180.0,
            sweepAngle: 180.0
        )
        
        // 180° start angle, 180° sweep: 0 -> 180°, 50 -> 270°, 100 -> 360°
        XCTAssertEqual(config.angleDegrees(for: 0), 180.0, accuracy: 0.0001)
        XCTAssertEqual(config.angleDegrees(for: 50), 270.0, accuracy: 0.0001)
        XCTAssertEqual(config.angleDegrees(for: 100), 360.0, accuracy: 0.0001)
    }
    
    func testAngleConversionForMercedes250DegreeSweep() {
        let config = AutomotiveGaugeConfig(
            title: "Power",
            unit: "W",
            minValue: 0,
            maxValue: 100,
            startAngle: 145.0,
            sweepAngle: 250.0
        )
        
        // 145° start angle, 250° sweep: 0 -> 145°, 50 -> 270°, 100 -> 395°
        XCTAssertEqual(config.angleDegrees(for: 0), 145.0, accuracy: 0.0001)
        XCTAssertEqual(config.angleDegrees(for: 50), 270.0, accuracy: 0.0001)
        XCTAssertEqual(config.angleDegrees(for: 100), 395.0, accuracy: 0.0001)
    }
    
    func testCockpitGaugeStyleTokens() {
        let style = CockpitGaugeStyle.standard
        XCTAssertEqual(style.id, "default")
        XCTAssertEqual(style.primaryAccentHex, "#EF4444")
        XCTAssertEqual(style.secondaryAccentHex, "#F59E0B")
        XCTAssertEqual(style.safeArcHex, "#10B981")
        XCTAssertEqual(style.warningArcHex, "#F59E0B")
        XCTAssertEqual(style.criticalArcHex, "#DC2626")
        XCTAssertFalse(style.bezelGradientColors.isEmpty)
        
        let defaultStyle = CockpitGaugeStyle.default
        XCTAssertEqual(defaultStyle, style)
    }
    
    func testThresholdClassification() {
        let config = AutomotiveGaugeConfig(
            title: "Swap",
            unit: "GB",
            minValue: 0,
            maxValue: 8,
            warningThreshold: 1.0,
            criticalThreshold: 2.0
        )
        
        XCTAssertEqual(config.zoneStatus(for: 0.5), .safe)
        XCTAssertEqual(config.zoneStatus(for: 1.0), .warning)
        XCTAssertEqual(config.zoneStatus(for: 1.5), .warning)
        XCTAssertEqual(config.zoneStatus(for: 2.0), .critical)
        XCTAssertEqual(config.zoneStatus(for: 4.5), .critical)
    }
    
    func testTickGenerationWithMajorAndMinorTicks() {
        let config = AutomotiveGaugeConfig(
            title: "CPU",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            majorTicksCount: 4, // [0, 25, 50, 75, 100]
            minorTicksPerInterval: 4
        )
        
        let ticks = config.generateTicks()
        let majorTicks = ticks.filter { $0.isMajor }
        let minorTicks = ticks.filter { !$0.isMajor }
        
        XCTAssertEqual(majorTicks.count, 5)
        XCTAssertEqual(majorTicks[0].value, 0.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[1].value, 25.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[2].value, 50.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[3].value, 75.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[4].value, 100.0, accuracy: 0.0001)
        
        // 4 intervals * 4 minor ticks = 16 minor ticks
        XCTAssertEqual(minorTicks.count, 16)
    }
    
    func testValueFormatting() {
        let configWithDecimals = AutomotiveGaugeConfig(
            title: "Power",
            unit: "W",
            minValue: 0,
            maxValue: 100,
            displayDecimals: 1
        )
        XCTAssertEqual(configWithDecimals.formatValue(45.67), "45.7 W")
        
        let configZeroDecimals = AutomotiveGaugeConfig(
            title: "CPU",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            displayDecimals: 0
        )
        XCTAssertEqual(configZeroDecimals.formatValue(45.67), "46 %")
    }
    
    func testCustomScaleForUnifiedMemory() {
        let config = AutomotiveGaugeConfig(
            title: "Unified Memory",
            unit: "GB",
            minValue: 0,
            maxValue: 36,
            warningThreshold: 28,
            criticalThreshold: 32,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 1
        )
        
        XCTAssertEqual(config.fraction(for: 18), 0.5, accuracy: 0.0001)
        XCTAssertEqual(config.zoneStatus(for: 20), .safe)
        XCTAssertEqual(config.zoneStatus(for: 29), .warning)
        XCTAssertEqual(config.zoneStatus(for: 34), .critical)
        XCTAssertEqual(config.formatValue(18.24), "18.2 GB")
    }
    
    func testPowerGaugeConfigScaleAndThresholds() {
        let powerConfig = AutomotiveGaugeConfig(
            title: "System Power",
            unit: "W",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 45,
            criticalThreshold: 75,
            majorTicksCount: 4,
            minorTicksPerInterval: 4,
            displayDecimals: 1
        )
        
        XCTAssertEqual(powerConfig.fraction(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(powerConfig.fraction(for: 25), 0.25, accuracy: 0.0001)
        XCTAssertEqual(powerConfig.fraction(for: 50), 0.50, accuracy: 0.0001)
        XCTAssertEqual(powerConfig.fraction(for: 75), 0.75, accuracy: 0.0001)
        XCTAssertEqual(powerConfig.fraction(for: 100), 1.0, accuracy: 0.0001)
        
        XCTAssertEqual(powerConfig.zoneStatus(for: 20.0), .safe)
        XCTAssertEqual(powerConfig.zoneStatus(for: 45.0), .warning)
        XCTAssertEqual(powerConfig.zoneStatus(for: 60.0), .warning)
        XCTAssertEqual(powerConfig.zoneStatus(for: 75.0), .critical)
        XCTAssertEqual(powerConfig.zoneStatus(for: 95.0), .critical)
        
        XCTAssertEqual(powerConfig.formatValue(24.579), "24.6 W")
    }
    
    func testNanAndInfinityFormattingSafety() {
        let config = AutomotiveGaugeConfig(
            title: "Power",
            unit: "W",
            minValue: 0,
            maxValue: 100
        )
        
        XCTAssertEqual(config.fraction(for: Double.nan), 0.0)
        XCTAssertEqual(config.fraction(for: Double.infinity), 0.0)
        XCTAssertEqual(config.formatValue(Double.nan), "0 W")
        XCTAssertEqual(config.formatValue(Double.infinity), "0 W")
    }
    
    func testInvertedGaugeConfigurationAndZones() {
        let bufferConfig = AutomotiveGaugeConfig(
            title: "200 GB Buffer",
            unit: "GB",
            minValue: 0,
            maxValue: 200,
            warningThreshold: 100,
            criticalThreshold: 50,
            majorTicksCount: 4,
            minorTicksPerInterval: 4,
            displayDecimals: 1,
            isInverted: true
        )
        
        XCTAssertTrue(bufferConfig.isInverted)
        XCTAssertEqual(bufferConfig.minValue, 0.0)
        XCTAssertEqual(bufferConfig.maxValue, 200.0)
        
        // Fractions
        XCTAssertEqual(bufferConfig.fraction(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(bufferConfig.fraction(for: 50), 0.25, accuracy: 0.0001)
        XCTAssertEqual(bufferConfig.fraction(for: 100), 0.50, accuracy: 0.0001)
        XCTAssertEqual(bufferConfig.fraction(for: 150), 0.75, accuracy: 0.0001)
        XCTAssertEqual(bufferConfig.fraction(for: 200), 1.0, accuracy: 0.0001)
        
        // Ticks
        let ticks = bufferConfig.generateTicks()
        let majorTicks = ticks.filter { $0.isMajor }
        XCTAssertEqual(majorTicks.count, 5)
        XCTAssertEqual(majorTicks[0].value, 0.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[1].value, 50.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[2].value, 100.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[3].value, 150.0, accuracy: 0.0001)
        XCTAssertEqual(majorTicks[4].value, 200.0, accuracy: 0.0001)
        
        // Inverted Zone Status: Low value is critical, High value is safe
        XCTAssertEqual(bufferConfig.zoneStatus(for: 20.0), .critical)
        XCTAssertEqual(bufferConfig.zoneStatus(for: 50.0), .critical)
        XCTAssertEqual(bufferConfig.zoneStatus(for: 75.0), .warning)
        XCTAssertEqual(bufferConfig.zoneStatus(for: 100.0), .warning)
        XCTAssertEqual(bufferConfig.zoneStatus(for: 150.0), .safe)
        XCTAssertEqual(bufferConfig.zoneStatus(for: 200.0), .safe)
        
        // Formatting
        XCTAssertEqual(bufferConfig.formatValue(142.5), "142.5 GB")
        XCTAssertEqual(bufferConfig.formatNumberOnly(142.5), "142.5")
    }
    
    func testBufferDeficitGaugeStandardDirection() {
        // Standard Direction (Left = 0 Deficit / Safe, Right = 200 Deficit / Critical)
        let deficitConfig = AutomotiveGaugeConfig(
            title: "Buffer Deficit",
            unit: "GB",
            minValue: 0,
            maxValue: 200,
            warningThreshold: 100, // Deficit >= 100 is warning
            criticalThreshold: 150, // Deficit >= 150 is critical
            majorTicksCount: 4,
            minorTicksPerInterval: 4,
            displayDecimals: 1,
            isInverted: false
        )
        
        XCTAssertFalse(deficitConfig.isInverted)
        
        // 0 Deficit (Left): Safe Green
        XCTAssertEqual(deficitConfig.fraction(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(deficitConfig.zoneStatus(for: 0), .safe)
        XCTAssertEqual(deficitConfig.zoneStatus(for: 50), .safe)
        
        // 100 Deficit (Middle): Warning Amber
        XCTAssertEqual(deficitConfig.fraction(for: 100), 0.50, accuracy: 0.0001)
        XCTAssertEqual(deficitConfig.zoneStatus(for: 100), .warning)
        XCTAssertEqual(deficitConfig.zoneStatus(for: 120), .warning)
        
        // 150..200 Deficit (Right): Critical Red
        XCTAssertEqual(deficitConfig.fraction(for: 150), 0.75, accuracy: 0.0001)
        XCTAssertEqual(deficitConfig.zoneStatus(for: 150), .critical)
        XCTAssertEqual(deficitConfig.zoneStatus(for: 200), .critical)
        
        // Formatting
        XCTAssertEqual(deficitConfig.formatValue(0), "0.0 GB")
        XCTAssertEqual(deficitConfig.formatValue(35.4), "35.4 GB")
    }
    
    func testGpuGaugeConfigScaleAndThresholds() {
        let gpuConfig = AutomotiveGaugeConfig(
            title: "Charge GPU",
            unit: "%",
            minValue: 0,
            maxValue: 100,
            warningThreshold: 70,
            criticalThreshold: 90,
            majorTicksCount: 4,
            minorTicksPerInterval: 3,
            displayDecimals: 1
        )
        
        // Fraction calculations
        XCTAssertEqual(gpuConfig.fraction(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(gpuConfig.fraction(for: 68.7), 0.687, accuracy: 0.0001)
        XCTAssertEqual(gpuConfig.fraction(for: 100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(gpuConfig.fraction(for: -10), 0.0, accuracy: 0.0001)
        XCTAssertEqual(gpuConfig.fraction(for: 120), 1.0, accuracy: 0.0001)
        
        // Zone status
        XCTAssertEqual(gpuConfig.zoneStatus(for: 45.0), .safe)
        XCTAssertEqual(gpuConfig.zoneStatus(for: 70.0), .warning)
        XCTAssertEqual(gpuConfig.zoneStatus(for: 85.0), .warning)
        XCTAssertEqual(gpuConfig.zoneStatus(for: 90.0), .critical)
        XCTAssertEqual(gpuConfig.zoneStatus(for: 100.0), .critical)
        
        // Tick marks: 4 intervals -> 5 major ticks: [0, 25, 50, 75, 100]
        let ticks = gpuConfig.generateTicks()
        let majorTicks = ticks.filter { $0.isMajor }
        XCTAssertEqual(majorTicks.count, 5)
        XCTAssertEqual(majorTicks[0].label, "0")
        XCTAssertEqual(majorTicks[1].label, "25")
        XCTAssertEqual(majorTicks[2].label, "50")
        XCTAssertEqual(majorTicks[3].label, "75")
        XCTAssertEqual(majorTicks[4].label, "100")
        
        // Formatting
        XCTAssertEqual(gpuConfig.formatValue(68.7), "68.7 %")
        XCTAssertEqual(gpuConfig.formatNumberOnly(68.7), "68.7")
        XCTAssertNotEqual(gpuConfig.formatValue(68.7), "6870.0 %")
    }
}

