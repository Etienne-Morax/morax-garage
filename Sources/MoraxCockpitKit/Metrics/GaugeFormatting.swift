import Foundation

/// Text formatting shared by the dashboard dials, re-evaluated on every telemetry sample.
public enum GaugeFormatting {
    /// Built once: allocating a NumberFormatter per sample is measurably expensive.
    /// It is configured here and only read afterwards, which Foundation documents as thread-safe.
    static let frequencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Formats a clock frequency such as "1,398 MHz" in the user's locale.
    public static func frequency(mhz: Double) -> String {
        guard mhz.isFinite else { return "— MHz" }
        let rounded = Int(mhz.rounded())
        let formatted = frequencyFormatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
        return "\(formatted) MHz"
    }
}
