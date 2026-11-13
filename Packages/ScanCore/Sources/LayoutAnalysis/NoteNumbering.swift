/// Turns note labels as read by OCR into the labels the document most likely
/// prints.
///
/// A label is one or two characters, which is where OCR is weakest: `10`
/// comes back as `I0`, `11` as `II`, a lone `I` not at all. Notes are
/// numbered in sequence, though, so the readings that agree with each other
/// outvote the ones that do not, and unread labels are filled in.
enum NoteNumbering {
    /// How a document numbers its notes.
    enum Kind: CaseIterable, Equatable {
        case arabic, roman, letter
    }

    /// A place in a numbering sequence.
    struct Position: Equatable {
        var kind: Kind
        var value: Int
    }

    /// The repaired labels of a run of consecutive notes.
    struct Run: Equatable {
        /// One label per note, never empty.
        var labels: [String]
        /// The number behind each label, where one is known.
        var values: [Int?]
        var kind: Kind
        /// The position of the last note, for the next run to continue from.
        var last: Position?
    }

    /// The value of one label read as `kind`, or `nil` if it does not read
    /// as that kind. Look-alike characters are resolved in favour of `kind`.
    static func value(of raw: String, as kind: Kind) -> Int? {
        parse(clean(raw), as: kind)?.value
    }

    /// Labels for a run of consecutive notes.
    ///
    /// - Parameters:
    ///   - raw: The labels as read, in order; empty where nothing was read.
    ///   - previous: Where the previous run of notes ended, if there was one.
    ///     Numbering usually carries on from there.
    static func labels(for raw: [String], after previous: Position?) -> Run {
        guard !raw.isEmpty else {
            return Run(labels: [], values: [], kind: previous?.kind ?? .arabic, last: previous)
        }
        let cleaned = raw.map(clean)
        let best = Kind.allCases
            .map { reading(of: cleaned, as: $0, after: previous) }
            .max { ($0.votes, $0.strong) < ($1.votes, $1.strong) }
        // No kind got a single vote: nothing was readable and there is
        // nothing to continue from.
        guard let best, best.votes > 0 else {
            return Run(
                labels: raw.indices.map { String($0 + 1) }, values: raw.indices.map { $0 + 1 },
                kind: .arabic, last: Position(kind: .arabic, value: raw.count)
            )
        }

        var values = best.values
        let parsed = values.count { $0 != nil }
        if Double(best.agreeing) >= 0.6 * Double(parsed) {
            // One sequence explains most readings: the rest are misreadings.
            values = values.indices.map { best.offset + $0 }
        } else {
            values = fillingGaps(in: values, after: previous?.kind == best.kind ? previous?.value : nil)
        }
        let labels = zip(values, cleaned).map { value, text in
            value.flatMap { render($0, as: best.kind) } ?? (text.isEmpty ? "*" : text)
        }
        let last = values.last.flatMap(\.self).map { Position(kind: best.kind, value: $0) } ?? previous
        return Run(labels: labels, values: values, kind: best.kind, last: last)
    }

    /// Numbering restarts somewhere in the run: trust what was read and
    /// derive only the missing values from their neighbours.
    private static func fillingGaps(in values: [Int?], after previous: Int?) -> [Int?] {
        var values = values
        for index in values.indices where values[index] == nil {
            values[index] = (index > 0 ? values[index - 1] : previous).map { $0 + 1 }
        }
        for index in values.indices.dropLast().reversed() where values[index] == nil {
            values[index] = values[index + 1].map { $0 - 1 }
        }
        return values
    }

    /// How well a run reads as one kind of numbering.
    private struct Reading {
        var kind: Kind
        /// The value of each label in this kind, where it has one.
        var values: [Int?]
        /// `value - index` of the sequence most labels agree on.
        var offset: Int
        /// Support for that sequence: agreeing labels plus one when it
        /// continues the previous run.
        var votes: Int
        /// Labels that agree with the sequence.
        var agreeing: Int
        /// Labels that can only be read as this kind.
        var strong: Int
    }

    private static func reading(of labels: [String], as kind: Kind, after previous: Position?) -> Reading {
        let parsed = labels.map { parse($0, as: kind) }
        let values = parsed.map { $0?.value }
        var votes: [Int: Int] = [:]
        for (index, value) in values.enumerated() {
            if let value {
                votes[value - index, default: 0] += 1
            }
        }
        let continuation = previous.flatMap { $0.kind == kind ? $0.value + 1 : nil }
        func support(_ offset: Int) -> Int {
            votes[offset, default: 0] + (offset == continuation ? 1 : 0)
        }
        let candidates = Set(votes.keys).union(continuation.map { [$0] } ?? [])
        // Ties go to the smaller offset so that the result is deterministic.
        let offset = candidates.max { (support($0), -$0) < (support($1), -$1) } ?? 1
        return Reading(
            kind: kind, values: values, offset: offset, votes: candidates.isEmpty ? 0 : support(offset),
            agreeing: votes[offset, default: 0], strong: parsed.count { $0?.isStrong == true }
        )
    }

    /// Letters and digits only, with Cyrillic look-alikes replaced by the
    /// Latin characters labels are written in.
    private static func clean(_ label: String) -> String {
        let lookAlikes: [Character: String] = [
            "І": "I", "Х": "X", "П": "II", "Ш": "III", "З": "3", "О": "O", "о": "o",
            "а": "a", "с": "c", "е": "e", "і": "i", "х": "x", "ı": "I", "|": "I",
        ]
        return label.map { lookAlikes[$0] ?? String($0) }.joined().filter { $0.isLetter || $0.isNumber }
    }

    /// The value of `label` in `kind`. A reading is strong when the label
    /// cannot belong to another kind.
    private static func parse(_ label: String, as kind: Kind) -> (value: Int, isStrong: Bool)? {
        guard !label.isEmpty else { return nil }
        switch kind {
        case .arabic:
            let digits = label.map { character -> Character? in
                switch character {
                case "I", "l", "i": "1"
                case "O", "o": "0"
                default: character.isASCII && character.isNumber ? character : nil
                }
            }
            guard !digits.contains(nil), let value = Int(String(digits.compactMap(\.self))) else { return nil }
            return (value, label.contains { $0.isNumber })
        case .roman:
            guard let value = romanValue(label) else { return nil }
            return (value, label.contains { "VXLC".contains($0) } || label.count > 1)
        case .letter:
            guard label.count == 1, let character = label.first, character.isLowercase, character.isASCII,
                  let ascii = character.asciiValue
            else { return nil }
            return (Int(ascii) - 96, true)
        }
    }

    private static let romanSymbols: [(Int, String)] = [
        (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]

    /// The value of an upper-case roman numeral below 400, or `nil`.
    private static func romanValue(_ text: String) -> Int? {
        var rest = Substring(text)
        var value = 0
        for (amount, symbol) in romanSymbols {
            while rest.hasPrefix(symbol) {
                value += amount
                rest = rest.dropFirst(symbol.count)
            }
        }
        // Reject non-canonical forms such as "IIII" or "VX".
        return rest.isEmpty && value > 0 && render(value, as: .roman) == text ? value : nil
    }

    /// - Returns: `nil` when the value cannot be written in `kind`.
    private static func render(_ value: Int, as kind: Kind) -> String? {
        switch kind {
        case .arabic:
            return value >= 0 ? String(value) : nil
        case .roman:
            guard value > 0, value < 400 else { return nil }
            var rest = value
            var text = ""
            for (amount, symbol) in romanSymbols {
                while rest >= amount {
                    text += symbol
                    rest -= amount
                }
            }
            return text
        case .letter:
            guard (1 ... 26).contains(value), let scalar = Unicode.Scalar(UInt8(96 + value)) as Unicode.Scalar? else {
                return nil
            }
            return String(Character(scalar))
        }
    }
}
