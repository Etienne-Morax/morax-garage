import Foundation
import os

public enum TelemetryLogger {
    public static let telemetry = Logger(subsystem: "com.morax.cockpit", category: "Telemetry")
    public static let process = Logger(subsystem: "com.morax.cockpit", category: "ProcessRunner")
    public static let lifecycle = Logger(subsystem: "com.morax.cockpit", category: "Lifecycle")
}
