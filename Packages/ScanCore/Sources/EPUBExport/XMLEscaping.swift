extension String {
    /// The string made safe for use as XML text or as a double-quoted
    /// attribute value.
    ///
    /// Characters that XML 1.0 forbids (most control characters, U+FFFE,
    /// U+FFFF) are dropped: they cannot be written even as references, and
    /// one of them makes the whole document unreadable. OCR occasionally
    /// produces them.
    var xmlEscaped: String {
        var result = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar {
            case "&": result.append(contentsOf: "&amp;".unicodeScalars)
            case "<": result.append(contentsOf: "&lt;".unicodeScalars)
            case ">": result.append(contentsOf: "&gt;".unicodeScalars)
            case "\"": result.append(contentsOf: "&quot;".unicodeScalars)
            case "\t", "\n", "\r", "\u{20}" ... "\u{D7FF}", "\u{E000}" ... "\u{FFFD}", "\u{10000}" ... "\u{10FFFF}":
                result.append(scalar)
            default:
                break
            }
        }
        return String(result)
    }
}
