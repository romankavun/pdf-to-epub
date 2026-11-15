import Foundation
import Testing

/// A deterministic random number generator (SplitMix64). The same seed gives
/// the same sequence on every machine, which is what makes a failing
/// property reproducible.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// A property did not hold. Thrown by ``Property/require(_:_:)`` and caught
/// by ``Property/check(_:cases:body:)``, which reports it with the seed.
public struct PropertyViolation: Error, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

/// Property-style testing without a dependency: a property is a closure run
/// for many generated cases, each driven by its own seed.
///
/// Environment variables:
/// - `PROPERTY_SEED=<n>`: run only the case with seed `n`, which is the
///   number printed by a failure.
/// - `PROPERTY_CASES=<n>`: run `n` cases instead of the default of the test.
public enum Property {
    /// The seed of the first case. Fixed, so the suite is deterministic and a
    /// failure seen in CI is seen locally.
    public static let baseSeed: UInt64 = 0x00B0_0C5C_A1AD

    /// Seed of case number `index`.
    public static func seed(ofCase index: Int) -> UInt64 {
        var mixer = SeededGenerator(seed: baseSeed &+ UInt64(index))
        return mixer.next()
    }

    /// Throws ``PropertyViolation`` unless `condition` holds.
    public static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw PropertyViolation(description: message())
        }
    }

    /// Throws ``PropertyViolation`` unless the two values are equal.
    public static func requireEqual<T: Equatable>(
        _ actual: T, _ expected: T, _ what: @autoclosure () -> String
    ) throws {
        if actual != expected {
            throw PropertyViolation(description: "\(what()): expected \(expected), got \(actual)")
        }
    }

    /// Runs `body` for `cases` generated cases and records one issue for the
    /// first case that throws, naming the seed that reproduces it. Stops at
    /// the first failure: later cases would only repeat the same defect.
    public static func check(
        _ name: String,
        cases: Int = 100,
        sourceLocation: SourceLocation = #_sourceLocation,
        body: (inout SeededGenerator) throws -> Void
    ) {
        let environment = ProcessInfo.processInfo.environment
        let seeds: [UInt64]
        if let single = environment["PROPERTY_SEED"].flatMap({ UInt64($0) }) {
            seeds = [single]
        } else {
            let count = environment["PROPERTY_CASES"].flatMap { Int($0) } ?? cases
            seeds = (0 ..< count).map(seed(ofCase:))
        }
        for seed in seeds {
            var generator = SeededGenerator(seed: seed)
            do {
                try body(&generator)
            } catch {
                Issue.record(
                    "Property '\(name)' failed: \(error). Reproduce with PROPERTY_SEED=\(seed)",
                    sourceLocation: sourceLocation
                )
                return
            }
        }
    }
}

public extension RandomNumberGenerator {
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func chance(_ probability: Double) -> Bool {
        double(0 ... 1) < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(0 ... items.count - 1)]
    }
}
