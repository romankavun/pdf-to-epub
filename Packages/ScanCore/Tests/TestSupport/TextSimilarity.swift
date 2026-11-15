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
        let a = Array(normalized(first)), b = Array(normalized(second))
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(a, b)) / Double(longest)
    }

    /// Whether the two texts are at least `threshold` alike.
    public static func matches(_ first: String, _ second: String, threshold: Double) -> Bool {
        ratio(first, second) >= threshold
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0 ... b.count)
        for (i, left) in a.enumerated() {
            var row = [i + 1]
            for (j, right) in b.enumerated() {
                row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = row
        }
        return previous[b.count]
    }
}
