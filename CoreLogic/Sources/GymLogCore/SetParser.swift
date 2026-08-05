// SetParser.swift — spec §7.5. Pure and synchronous: String in → ParseResult out.
// Strategy:
//   1. Normalize (NumberNormalizer).
//   2. Extract LABELED slots first (rpe N, rir N, N lb/kg, "for N"/"x N"/"N reps",
//      "at N") — each consumes its tokens.
//   3. Resolve remaining UNLABELED numbers by heuristic.
//   4. Residual words → exercise-name candidate → catalog resolution (fuzzy).
//   5. Validate ranges + completeness, package as ParseResult.

import Foundation

public struct SetParser: Sendable {

    public let catalog: ExerciseCatalog
    public let fuzzyThreshold: Double

    public init(catalog: ExerciseCatalog = .seed, fuzzyThreshold: Double = 0.82) {
        self.catalog = catalog
        self.fuzzyThreshold = fuzzyThreshold
    }

    // Words that carry no meaning once slots are consumed.
    static let stopWords: Set<String> = ["at", "for", "x", "and", "a", "an", "of", "the", "with", "on", "do", "did", "then"]

    // MARK: Entry point

    /// - Parameters:
    ///   - rawTranscript: what SFSpeechRecognizer heard.
    ///   - currentExerciseName: name of the active `WorkoutExercise` (nil if none).
    ///   - prefs: default unit + [OPEN E] policy.
    public func parse(_ rawTranscript: String,
                      currentExerciseName: String? = nil,
                      prefs: ParserPrefs = ParserPrefs()) -> ParseResult {

        let normalized = NumberNormalizer.normalize(rawTranscript)
        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return .invalid(.emptyUtterance, transcript: rawTranscript) }

        var draft = SetDraft()
        var consumed = [Bool](repeating: false, count: tokens.count)

        // ---- 1) Labeled slots ------------------------------------------------

        // rpe N  (also swallow a preceding "at": "at rpe 8")
        if let i = firstIndex(of: "rpe", in: tokens, consumed: consumed),
           let (v, vi) = numberAfter(i, tokens, consumed) {
            draft.rpe = v
            consume(&consumed, i, vi)
            consumePreceding("at", before: i, tokens, &consumed)
        }

        // rir N
        if let i = firstIndex(of: "rir", in: tokens, consumed: consumed),
           let (v, vi) = numberAfter(i, tokens, consumed) {
            draft.rir = Int(v)
            consume(&consumed, i, vi)
            consumePreceding("at", before: i, tokens, &consumed)
        }

        // N lb / N kg  → weight (+ swallow preceding "at")
        for i in tokens.indices where !consumed[i] && (tokens[i] == "lb" || tokens[i] == "kg") {
            if i > 0, !consumed[i - 1], let v = Double(tokens[i - 1]) {
                draft.weight = v
                draft.unit = WeightUnit(rawValue: tokens[i])
                consume(&consumed, i - 1, i)
                consumePreceding("at", before: i - 1, tokens, &consumed)
                break
            }
        }

        // reps: "for N" | "x N" | "N x" | "N reps" | "reps N"
        if draft.reps == nil {
            outer: for i in tokens.indices where !consumed[i] {
                let t = tokens[i]
                if (t == "for" || t == "x"), let (v, vi) = numberAfter(i, tokens, consumed), v == v.rounded() {
                    draft.reps = Int(v); consume(&consumed, i, vi); break outer
                }
                if t == "reps" {
                    // "5 reps"
                    if i > 0, !consumed[i - 1], let v = Double(tokens[i - 1]), v == v.rounded() {
                        draft.reps = Int(v); consume(&consumed, i - 1, i); break outer
                    }
                    // "reps 5"
                    if let (v, vi) = numberAfter(i, tokens, consumed), v == v.rounded() {
                        draft.reps = Int(v); consume(&consumed, i, vi); break outer
                    }
                    consume(&consumed, i, i) // dangling keyword
                }
            }
        }

        // "at N" with no unit → weight in default unit ("5 reps at 225")
        if draft.weight == nil,
           let i = firstIndex(of: "at", in: tokens, consumed: consumed),
           let (v, vi) = numberAfter(i, tokens, consumed) {
            draft.weight = v
            consume(&consumed, i, vi)
        }

        // ---- 2) Unlabeled leftover numbers ----------------------------------

        var leftoverNums: [(Double, Int)] = []   // (value, index)
        for i in tokens.indices where !consumed[i] {
            if let v = Double(tokens[i]) { leftoverNums.append((v, i)) }
        }

        switch resolveUnlabeled(&draft, leftoverNums) {
        case .ok(let usedIndices):
            for idx in usedIndices { consumed[idx] = true }
        case .ambiguous(let why):
            return .invalid(.ambiguousNumbers(why), transcript: rawTranscript)
        }

        // ---- 3) Residual words → exercise name ------------------------------

        var residual: [String] = []
        for i in tokens.indices where !consumed[i] {
            let t = tokens[i]
            if Double(t) != nil { continue }                    // stray number, already handled
            if Self.stopWords.contains(t) { continue }
            if t == "lb" || t == "kg" || t == "rpe" || t == "rir" || t == "reps" { continue }
            residual.append(t)
        }
        if !residual.isEmpty {
            draft.exerciseName = residual.joined(separator: " ")
        }

        // ---- 4) Exercise resolution -----------------------------------------

        let match = resolveExercise(draft.exerciseName, currentExerciseName: currentExerciseName)
        if case .missing = match {
            return .invalid(.noExerciseContext, transcript: rawTranscript)
        }

        // ---- 5) Validation ---------------------------------------------------

        var warnings: [ParseProblem] = []

        if let rpe = draft.rpe {
            let valid = (0...10).contains(rpe) && (rpe * 2) == (rpe * 2).rounded()
            if !valid { return .invalid(.invalidRPE(rpe), transcript: rawTranscript) }
        }
        if let rir = draft.rir, !(0...10).contains(rir) {
            return .invalid(.invalidRIR(rir), transcript: rawTranscript)
        }

        if draft.weight == nil && draft.reps == nil {
            return .invalid(.noNumbersFound, transcript: rawTranscript)
        }
        if draft.reps == nil {
            if prefs.allowWeightOnlyDraft {
                warnings.append(.missingReps)          // [OPEN E]: store partial
            } else {
                return .invalid(.missingReps, transcript: rawTranscript)
            }
        }
        if draft.weight == nil {
            // Bodyweight movements legitimately have no weight ("pull ups twelve").
            let isBodyweight: Bool = {
                if case .matched(let ex) = match { return ex.equipment == .bodyweight }
                return false
            }()
            if isBodyweight {
                draft.weight = 0
                warnings.append(.missingWeight)
            } else {
                return .invalid(.missingWeight, transcript: rawTranscript)
            }
        }

        if draft.unit == nil { draft.unit = prefs.defaultUnit }
        return .valid(draft, match, warnings: warnings)
    }

    // MARK: Unlabeled-number heuristics (spec §7.5)

    enum UnlabeledResolution {
        case ok(usedIndices: [Int])
        case ambiguous(String)
    }

    func resolveUnlabeled(_ d: inout SetDraft, _ nums: [(Double, Int)]) -> UnlabeledResolution {
        guard !nums.isEmpty else { return .ok(usedIndices: []) }

        switch (d.weight, d.reps) {
        case (.some, .some):
            // both known — ignore strays (defensive)
            return .ok(usedIndices: nums.map(\.1))

        case (.some, .none):
            // weight known → single leftover is reps
            if nums.count == 1, nums[0].0 == nums[0].0.rounded() {
                d.reps = Int(nums[0].0)
                return .ok(usedIndices: [nums[0].1])
            }
            return .ambiguous("heard extra numbers after the weight")

        case (.none, .some):
            // reps known → single leftover is weight
            if nums.count == 1 {
                d.weight = nums[0].0
                return .ok(usedIndices: [nums[0].1])
            }
            return .ambiguous("heard extra numbers after the reps")

        case (.none, .none):
            if nums.count == 1 {
                let v = nums[0].0
                if v > 50 {                     // almost certainly a weight
                    d.weight = v
                    return .ok(usedIndices: [nums[0].1])
                }
                if v <= 30, v == v.rounded() {  // plausible bodyweight reps
                    d.reps = Int(v)
                    return .ok(usedIndices: [nums[0].1])
                }
                return .ambiguous("one number that could be weight or reps — say \"pounds\" or \"for\"")
            }
            if nums.count == 2 {
                let (a, b) = (nums[0], nums[1])
                // any number > 50 is almost certainly weight
                if a.0 > 50 || b.0 > 50 {
                    let (w, r) = a.0 > b.0 ? (a, b) : (b, a)
                    guard r.0 == r.0.rounded() else {
                        return .ambiguous("could not tell reps from weight")
                    }
                    d.weight = w.0; d.reps = Int(r.0)
                    return .ok(usedIndices: [w.1, r.1])
                }
                // both small & plausibly reps → flag (spec: ask to repeat)
                if a.0 <= 30 && b.0 <= 30 {
                    return .ambiguous("both numbers could be reps — say \"pounds\" or \"for\"")
                }
                // [OPEN C] default convention: weight then reps, spoken order
                guard b.0 == b.0.rounded() else {
                    return .ambiguous("could not tell reps from weight")
                }
                d.weight = a.0; d.reps = Int(b.0)
                return .ok(usedIndices: [a.1, b.1])
            }
            return .ambiguous("heard more than two unlabeled numbers")
        }
    }

    // MARK: Exercise resolution (spec §7.5)

    public func resolveExercise(_ name: String?, currentExerciseName: String?) -> ExerciseMatch {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return currentExerciseName != nil ? .inherit : .missing
        }
        if let hit = catalog.exact(name) { return .matched(hit) }
        if let (hit, score) = catalog.bestFuzzy(name), score >= fuzzyThreshold {
            return .matched(hit)
        }
        let suggestions = catalog.topFuzzy(name, 3).map(\.0)
        return .unresolved(spoken: name, suggestions: suggestions)
    }

    // MARK: Token helpers

    func firstIndex(of word: String, in tokens: [String], consumed: [Bool]) -> Int? {
        tokens.indices.first { !consumed[$0] && tokens[$0] == word }
    }

    /// First unconsumed numeric token strictly after index i (adjacent-ish: within 2).
    func numberAfter(_ i: Int, _ tokens: [String], _ consumed: [Bool]) -> (Double, Int)? {
        for j in (i + 1)..<min(tokens.count, i + 3) where !consumed[j] {
            if let v = Double(tokens[j]) { return (v, j) }
            if tokens[j] != "of" && tokens[j] != "a" { break }  // small connectors only
        }
        return nil
    }

    func consume(_ consumed: inout [Bool], _ range: Int...) {
        for i in range { consumed[i] = true }
    }

    func consumePreceding(_ word: String, before i: Int, _ tokens: [String], _ consumed: inout [Bool]) {
        if i > 0, !consumed[i - 1], tokens[i - 1] == word { consumed[i - 1] = true }
    }
}
