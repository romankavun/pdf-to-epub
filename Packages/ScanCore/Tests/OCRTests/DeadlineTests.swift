import Foundation
@testable import OCR
import Testing

private struct TooSlow: Error, Equatable {}

/// Counts attempts across concurrent calls.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

@Suite("Deadline")
struct DeadlineTests {
    @Test("returns the result of an operation that finishes in time")
    func inTime() async throws {
        let value = try await Deadline.run(seconds: 5, attempts: 1, onTimeout: TooSlow()) { 42 }
        #expect(value == 42)
    }

    @Test("gives up on an operation that never finishes, without waiting for it", .timeLimit(.minutes(1)))
    func timesOut() async {
        let counter = Counter()
        let start = Date()
        await #expect(throws: TooSlow()) {
            try await Deadline.run(seconds: 0.05, attempts: 2, onTimeout: TooSlow()) {
                _ = counter.next()
                // Ignores cancellation, like a request stuck inside a framework.
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            }
        }
        #expect(counter.next() == 3)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test("tries again after a timeout and returns the later result", .timeLimit(.minutes(1)))
    func retries() async throws {
        let counter = Counter()
        let value = try await Deadline.run(seconds: 0.05, attempts: 3, onTimeout: TooSlow()) {
            let attempt = counter.next()
            if attempt == 1 {
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            }
            return attempt
        }
        #expect(value == 2)
    }

    @Test("passes an error of the operation through without retrying")
    func operationError() async {
        let counter = Counter()
        await #expect(throws: CocoaError.self) {
            try await Deadline.run(seconds: 5, attempts: 3, onTimeout: TooSlow()) {
                _ = counter.next()
                throw CocoaError(.fileNoSuchFile)
            }
        }
        #expect(counter.next() == 2)
    }
}
