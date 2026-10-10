import Foundation
import os

/// Runs blocking file-system work on a GCD thread and stops waiting after `timeout`.
///
/// A `stat` or directory walk on a stale SMB mount can sit in the kernel for the whole
/// SMB timeout and cannot be interrupted. Rather than freezing the caller (or starving
/// the cooperative thread pool), the caller is released with `nil` and the stuck thread
/// finishes on its own. Cancelling the calling task releases it the same way.
enum BlockingDeadline {
    static func run<Value: Sendable>(
        timeout: TimeInterval,
        _ work: @escaping @Sendable () -> Value
    ) async -> Value? {
        let gate = ResumeOnce<Value?>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                DispatchQueue.global(qos: .utility).async { gate.resume(work()) }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { gate.resume(nil) }
            }
        } onCancel: {
            gate.resume(nil)
        }
    }
}

/// Resumes a continuation exactly once, whichever of work, deadline or cancellation
/// comes first, including a cancellation that lands before the continuation exists.
private final class ResumeOnce<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var result: Value?
        var isResolved = false
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let early: Value? = state.withLockUnchecked { state in
            guard state.isResolved else {
                state.continuation = continuation
                return nil
            }
            return state.result
        }
        if let early { continuation.resume(returning: early) }
    }

    func resume(_ value: Value) {
        let waiting: CheckedContinuation<Value, Never>? = state.withLockUnchecked { state in
            guard !state.isResolved else { return nil }
            state.isResolved = true
            guard let continuation = state.continuation else {
                state.result = value
                return nil
            }
            state.continuation = nil
            return continuation
        }
        waiting?.resume(returning: value)
    }
}
