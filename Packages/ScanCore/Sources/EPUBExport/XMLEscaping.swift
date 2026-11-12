extension String {
    /// The string made safe for use as XML text or as a double-quoted
    /// attribute value.
    var xmlEscaped: String {
        var result = ""
        result.reserveCapacity(utf8.count)
        for character in self {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }
}
