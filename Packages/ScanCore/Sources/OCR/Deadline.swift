import Foundation

/// Runs an asynchronous operation with a time limit and retries.
///
/// A Vision request has been seen to never return, with the process idle,
/// roughly once in a few thousand pages. Such a request does not react to
/// cancellation, so it cannot be awaited: it is abandoned and the work is
/// started again.
enum Deadline {
    /// The result of `operation`, started up to `attempts` times.
    ///
    /// - Parameters:
    ///   - seconds: How long one attempt may take.
    ///   - attempts: How many times to start the operation; at least once.
    ///   - onTimeout: Thrown when every attempt ran out of time.
    /// - Throws: An error of the operation itself at once, without retrying.
    static func run<Value: Sendable>(
        seconds: TimeInterval,
        attempts: Int,
        onTimeout: any Error,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        for _ in 1 ..< max(1, attempts) {
            if let value = try await attempt(seconds: seconds, operation) {
                return value
            }
        }
        guard let value = try await attempt(seconds: seconds, operation) else { throw onTimeout }
        return value
    }

    /// - Returns: `nil` when the operation did not finish in time. It may
    ///   still be running: nothing waits for it.
    private static func attempt<Value: Sendable>(
        seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value? {
        try await withCheckedThrowingContinuation { continuation in
            let gate = Gate(continuation)
            let work = Task {
                do {
                    try await gate.open(.success(operation()))
                } catch {
                    gate.open(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                work.cancel()
                gate.open(.success(nil))
            }
        }
    }

    /// Resumes a continuation exactly once, whichever side gets there first.
    private final class Gate<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, any Error>?

        init(_ continuation: CheckedContinuation<Value?, any Error>) {
            self.continuation = continuation
        }

        func open(_ result: Result<Value?, any Error>) {
            let waiting = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            waiting?.resume(with: result)
        }
    }
}
