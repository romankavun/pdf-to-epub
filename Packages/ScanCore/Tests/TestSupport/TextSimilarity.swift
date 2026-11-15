import Foundation

/// Tolerant text comparison for golden files: OCR output changes between OS
/// releases, so the text of a block must be close to the expectation, not
/// identical.
public enum TextSimilarity {
    /// Lower-cases and collapses whitespace so layout differences do not count.
    public static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Share of the longer text that is not edited away, 0...1.
    public static func ratio(_ first: String, _ second: String) -> Double {
        let left = Array(normalized(first)), right = Array(normalized(second))
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(left, right)) / Double(longest)
    }

    /// Whether the two texts are at least `threshold` alike.
    public static func matches(_ first: String, _ second: String, threshold: Double) -> Bool {
        ratio(first, second) >= threshold
    }

    private static func editDistance(_ first: [Character], _ second: [Character]) -> Int {
        guard !first.isEmpty else { return second.count }
        guard !second.isEmpty else { return first.count }
        var previous = Array(0 ... second.count)
        for (row, left) in first.enumerated() {
            var current = [row + 1]
            for (column, right) in second.enumerated() {
                current.append(min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    previous[column] + (left == right ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[second.count]
    }
}
