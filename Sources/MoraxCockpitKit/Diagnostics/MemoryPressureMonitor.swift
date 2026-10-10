import Foundation
import Dispatch

/// Receives the operating system's memory-pressure events without inventing an
/// initial value. The first state is deliberately nil until macOS reports one.
@MainActor
public final class MemoryPressureMonitor {
    public static let shared = MemoryPressureMonitor()

    public private(set) var currentState: MemoryPressureState?
    private var source: DispatchSourceMemoryPressure?

    public init(startMonitoring: Bool = true) {
        if startMonitoring { start() }
    }

    public func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let event = source.data
            if event.contains(.critical) {
                self.currentState = .critical
            } else if event.contains(.warning) {
                self.currentState = .warning
            } else if event.contains(.normal) {
                self.currentState = .normal
            }
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        currentState = nil
    }
}
