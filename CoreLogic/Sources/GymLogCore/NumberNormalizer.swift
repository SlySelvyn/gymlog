// NumberNormalizer.swift — spec §7.4.
// Turns a messy speech transcript into clean, parse-ready tokens:
//   "Squat two-twenty-five for five, R-P-E eight and a half"
//     → "squat 225 for 5 rpe 8.5"
//
// Pipeline: lowercase → de-hyphenate → strip filler → canonicalize keywords
//           → spoken-numbers-to-digits (incl. plate-math compounds).

import Foundation

public enum NumberNormalizer {

    // MARK: Public entry point

    public static func normalize(_ raw: String) -> String {
        var tokens = tokenize(raw)
        tokens = stripFiller(tokens)
        tokens = canonicalizeKeywords(tokens)
        tokens = convertSpokenNumbers(tokens)
        return tokens.joined(separator: " ")
    }

    // MARK: Tokenization

    /// Lowercase, split hyphens ("two-twenty-five" → "two twenty five",
    /// "r-p-e" → "r p e"), drop punctuation except decimal points inside digits.
    static func tokenize(_ raw: String) -> [String] {
        let lowered = raw.lowercased()
        var cleaned = ""
        let chars = Array(lowered)
        for (i, c) in chars.enumerated() {
            if c.isLetter || c.isNumber {
                cleaned.append(c)
            } else if c == "." {
                // keep "8.5", drop sentence-ending periods
                let prevDigit = i > 0 && chars[i - 1].isNumber
                let nextDigit = i + 1 < chars.count && chars[i + 1].isNumber
                cleaned.append(prevDigit && nextDigit ? c : " ")
            } else {
                cleaned.append(" ") // hyphens, commas, etc. → separators
            }
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    // MARK: Filler removal

    static let fillerWords: Set<String> = ["um", "uh", "uhh", "umm", "er", "okay", "ok", "please", "like"]

    static func stripFiller(_ tokens: [String]) -> [String] {
        tokens.filter { !fillerWords.contains($0) }
    }

    // MARK: Keyword canonicalization (spec §7.4c)

    /// pounds→lb, kilos→kg, "r p e"→rpe, "reps in reserve"→rir,
    /// "times"/"by"→x, "rep"→reps.
    static func canonicalizeKeywords(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]

            // spelled-out acronyms: "r p e" / "r i r"
            if i + 2 < tokens.count {
                let tri = tokens[i...(i + 2)].joined()
                if tri == "rpe" { out.append("rpe"); i += 3; continue }
                if tri == "rir" { out.append("rir"); i += 3; continue }
            }
            // "reps in reserve" → rir
            if t == "reps", i + 2 < tokens.count,
               tokens[i + 1] == "in", tokens[i + 2] == "reserve" {
                out.append("rir"); i += 3; continue
            }

            switch t {
            case "lbs", "pound", "pounds":                       out.append("lb")
            case "kgs", "kilo", "kilos", "kilogram", "kilograms": out.append("kg")
            case "rep":                                          out.append("reps")
            case "times", "by":                                  out.append("x")
            default:                                             out.append(t)
            }
            i += 1
        }
        return out
    }

    // MARK: Spoken numbers → digits (spec §7.4b)

    static let unitWords: [String: Int] = [
        "zero": 0, "oh": 0, "o": 0,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    static let teenWords: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tensWords: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    static func isNumberWord(_ t: String) -> Bool {
        unitWords[t] != nil || teenWords[t] != nil || tensWords[t] != nil
            || t == "hundred" || t == "thousand"
    }

    /// Words that may appear *inside* a spoken-number run without ending it.
    static func isRunConnector(_ t: String) -> Bool {
        t == "and" || t == "a" || t == "point" || t == "half"
    }

    /// Scan tokens, find maximal runs of spoken-number words, convert each.
    static func convertSpokenNumbers(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let startsRun = isNumberWord(tokens[i]) || isNumericLiteral(tokens[i])
                || (tokens[i] == "a" && i + 1 < tokens.count && tokens[i + 1] == "hundred")
            guard startsRun else {
                out.append(tokens[i]); i += 1; continue
            }
            // collect the run (number words, connectors that lead to more
            // number-ish content, numeric literals like "225")
            var j = i
            var run: [String] = []
            while j < tokens.count {
                let t = tokens[j]
                if isNumberWord(t) || isNumericLiteral(t) {
                    run.append(t); j += 1
                } else if isRunConnector(t) {
                    // only absorb a connector if something number-ish follows
                    // ("and a half", "and thirty five", "point five")
                    if lookaheadContinuesRun(tokens, from: j) {
                        run.append(t); j += 1
                    } else { break }
                } else { break }
            }
            out.append(contentsOf: renderRun(run))
            i = j
        }
        return out
    }

    static func isNumericLiteral(_ t: String) -> Bool {
        Double(t) != nil
    }

    static func lookaheadContinuesRun(_ tokens: [String], from j: Int) -> Bool {
        var k = j
        // skip a chain of connectors, require a number word / literal / "half" after
        while k < tokens.count, isRunConnector(tokens[k]) {
            if tokens[k] == "half" { return true }
            k += 1
        }
        return k < tokens.count && (isNumberWord(tokens[k]) || isNumericLiteral(tokens[k]))
    }

    /// Convert one run of number-ish tokens to digit token(s).
    /// Falls back to greedy sub-run parsing when the whole run is not one number
    /// (e.g. "225 5" spoken as "two twenty five five" stays two numbers).
    static func renderRun(_ run: [String]) -> [String] {
        var out: [String] = []
        var rest = ArraySlice(run)
        while !rest.isEmpty {
            if let (value, consumed) = parseLongestNumber(rest) {
                out.append(format(value))
                rest = rest.dropFirst(consumed)
            } else {
                out.append(String(rest.first!)) // unparseable token, pass through
                rest = rest.dropFirst()
            }
        }
        return out
    }

    static func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(v)
    }

    /// Try to parse the longest valid number starting at the head of `slice`.
    /// Grammar (checked longest-first):
    ///   number   := integer fraction?
    ///   fraction := "point" digit+ | ("and")? ("a")? "half"
    ///   integer  := standard | plateCompound | literal | simple
    ///   standard := simple "hundred" ("and"? simple0to99)?      // 135 = "one hundred thirty five"
    ///   plate    := unit(1-9) remainder0to99                    // 225 = "two twenty five"
    ///   remainder:= tens unit? | teen | "oh" unit               // 25, 15, 05
    ///   simple   := tens unit? | teen | unit | "a hundred" ...
    static func parseLongestNumber(_ slice: ArraySlice<String>) -> (Double, Int)? {
        guard let (intVal, intLen) = parseInteger(slice) else { return nil }
        var value = Double(intVal)
        var len = intLen
        // fraction?
        var rest = slice.dropFirst(intLen)
        if let (frac, fracLen) = parseFraction(rest) {
            value += frac; len += fracLen; rest = rest.dropFirst(fracLen)
        }
        return (value, len)
    }

    static func parseFraction(_ slice: ArraySlice<String>) -> (Double, Int)? {
        var s = slice
        var len = 0
        // "point five" / "point two five"
        if s.first == "point" {
            s = s.dropFirst(); len += 1
            var digits = ""
            while let t = s.first, let d = unitWords[t] ?? teenWords[t].flatMap({ $0 < 10 ? $0 : nil }) {
                digits.append(String(d)); s = s.dropFirst(); len += 1
                _ = d
            }
            // also allow a numeric literal after "point": "point 5"
            if digits.isEmpty, let t = s.first, let _ = Int(t) {
                digits = t; s = s.dropFirst(); len += 1
            }
            guard !digits.isEmpty else { return nil }
            return (Double("0.\(digits)") ?? 0, len)
        }
        // "and a half" / "and half" / "a half"
        var k = 0
        var seenHalf = false
        for t in s {
            if t == "and" || t == "a" { k += 1; continue }
            if t == "half" { k += 1; seenHalf = true }
            break
        }
        if seenHalf { return (0.5, len + k) }
        return nil
    }

    static func parseInteger(_ slice: ArraySlice<String>) -> (Int, Int)? {
        // numeric literal ("225")
        if let t = slice.first, let v = Int(t) { return (v, 1) }
        if let t = slice.first, let d = Double(t), d.truncatingRemainder(dividingBy: 1) == 0 {
            return (Int(d), 1)
        }

        // ---- standard with "hundred"/"thousand": "one hundred (and) thirty five"
        if let r = parseStandard(slice) { return r }
        // ---- plate-math compound: "two twenty five" → 225
        if let r = parsePlateCompound(slice) { return r }
        // ---- simple 0–99
        if let r = parseSimple(slice) { return r }
        return nil
    }

    /// "one hundred thirty five", "a hundred and five", "two hundred"
    static func parseStandard(_ slice: ArraySlice<String>) -> (Int, Int)? {
        var s = slice
        var len = 0
        var hundreds = 0

        if s.first == "a", s.dropFirst().first == "hundred" {
            hundreds = 1; s = s.dropFirst(2); len += 2
        } else if let t = s.first, let u = unitWords[t], u > 0, s.dropFirst().first == "hundred" {
            hundreds = u; s = s.dropFirst(2); len += 2
        } else if let t = s.first, let teen = teenWords[t], s.dropFirst().first == "hundred" {
            hundreds = teen; s = s.dropFirst(2); len += 2   // "fifteen hundred" = 1500
        } else {
            return nil
        }

        var value = hundreds * 100
        // optional "and"
        if s.first == "and", lookaheadSimple(s.dropFirst()) {
            s = s.dropFirst(); len += 1
        }
        if let (rem, remLen) = parseSimple(s) {
            value += rem; len += remLen
        }
        return (value, len)
    }

    static func lookaheadSimple(_ s: ArraySlice<String>) -> Bool {
        guard let t = s.first else { return false }
        return unitWords[t] != nil || teenWords[t] != nil || tensWords[t] != nil
    }

    /// "two twenty five" → 225. First token must be a unit 1–9; remainder must
    /// be a *plausible* 0–99 spoken as one breath: tens(+unit), teen, or "oh"+unit.
    /// A bare unit remainder ("two five") is NOT compounded — too ambiguous.
    static func parsePlateCompound(_ slice: ArraySlice<String>) -> (Int, Int)? {
        guard let first = slice.first, let lead = unitWords[first], (1...9).contains(lead) else { return nil }
        let rest = slice.dropFirst()

        // "oh five" → 05
        if rest.first == "oh" || rest.first == "o" || rest.first == "zero" {
            if let t2 = rest.dropFirst().first, let u = unitWords[t2], t2 != "oh", t2 != "o" {
                return (lead * 100 + u, 3)
            }
            return nil
        }
        // teen: "two fifteen" → 215
        if let t = rest.first, let teen = teenWords[t] {
            return (lead * 100 + teen, 2)
        }
        // tens (+ optional unit): "two twenty (five)" → 220 / 225
        if let t = rest.first, let tens = tensWords[t] {
            if let t2 = rest.dropFirst().first, let u = unitWords[t2], u > 0 {
                return (lead * 100 + tens + u, 3)
            }
            return (lead * 100 + tens, 2)
        }
        return nil
    }

    /// 0–99: "five", "twelve", "thirty five", "ninety"
    static func parseSimple(_ slice: ArraySlice<String>) -> (Int, Int)? {
        guard let t = slice.first else { return nil }
        if let tens = tensWords[t] {
            if let t2 = slice.dropFirst().first, let u = unitWords[t2], u > 0 {
                return (tens + u, 2)
            }
            return (tens, 1)
        }
        if let teen = teenWords[t] { return (teen, 1) }
        if let u = unitWords[t], t != "oh", t != "o" { return (u, 1) }
        if t == "zero" { return (0, 1) }
        return nil
    }
}
