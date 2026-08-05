// ExerciseCatalog.swift — spec §7.5 (resolveExercise) + Appendix A seed.
// Powers: exact alias lookup, fuzzy matching, and the `contextualStrings`
// list fed to SFSpeechRecognizer to bias recognition toward gym vocabulary.

import Foundation

public struct ExerciseCatalog: Sendable {

    public let exercises: [ExerciseDefinition]
    /// canonical alias → exercise
    let byAliasExact: [String: ExerciseDefinition]

    public init(exercises: [ExerciseDefinition]) {
        self.exercises = exercises
        var map: [String: ExerciseDefinition] = [:]
        for ex in exercises {
            map[Self.canonical(ex.name)] = ex
            for a in ex.aliases { map[Self.canonical(a)] = ex }
        }
        self.byAliasExact = map
    }

    // MARK: Canonicalization

    /// lowercase, collapse whitespace, naive singularization of the last word
    /// ("hammer curls" → "hammer curl").
    public static func canonical(_ s: String) -> String {
        var words = s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        if var last = words.last, last.count > 3, last.hasSuffix("s"), !last.hasSuffix("ss") {
            last.removeLast()
            words[words.count - 1] = last
        }
        return words.joined(separator: " ")
    }

    // MARK: Lookup

    public func exact(_ name: String) -> ExerciseDefinition? {
        byAliasExact[Self.canonical(name)]
    }

    /// Best fuzzy match with a 0...1 score (token-set overlap blended with
    /// normalized Levenshtein similarity). Spec threshold: accept ≥ 0.82.
    public func bestFuzzy(_ name: String) -> (ExerciseDefinition, Double)? {
        topFuzzy(name, 1).first
    }

    public func topFuzzy(_ name: String, _ n: Int) -> [(ExerciseDefinition, Double)] {
        let key = Self.canonical(name)
        guard !key.isEmpty else { return [] }
        var scored: [(ExerciseDefinition, Double)] = []
        for ex in exercises {
            var best = 0.0
            for candidate in [ex.name] + ex.aliases {
                best = max(best, Self.similarity(key, Self.canonical(candidate)))
            }
            scored.append((ex, best))
        }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(n))
    }

    /// All names + aliases, for `SFSpeechRecognizer.contextualStrings`.
    public var contextualStrings: [String] {
        exercises.flatMap { [$0.name] + $0.aliases }
            + ["RPE", "RIR", "reps", "pounds", "kilos"]
    }

    // MARK: Similarity

    static func similarity(_ a: String, _ b: String) -> Double {
        let lev = levenshteinSimilarity(a, b)
        let tok = tokenOverlap(a, b)
        let blended = 0.5 * lev + 0.5 * tok
        // Speech often splits/joins words ("lat pull down" vs "lat pulldown"):
        // also compare with spaces stripped and take the best signal.
        let joined = levenshteinSimilarity(a.replacingOccurrences(of: " ", with: ""),
                                           b.replacingOccurrences(of: " ", with: ""))
        return max(blended, joined)
    }

    static func levenshteinSimilarity(_ a: String, _ b: String) -> Double {
        let d = levenshtein(Array(a), Array(b))
        let m = max(a.count, b.count)
        return m == 0 ? 1 : 1 - Double(d) / Double(m)
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    static func tokenOverlap(_ a: String, _ b: String) -> Double {
        let sa = Set(a.split(separator: " ")), sb = Set(b.split(separator: " "))
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        let inter = sa.intersection(sb).count
        let union = sa.union(sb).count
        return Double(inter) / Double(union)
    }

    // MARK: Seed (spec Appendix A + common movements)

    public static let seed = ExerciseCatalog(exercises: [
        .init(name: "Back Squat", equipment: .barbell, aliases: ["squat", "barbell squat", "squats"]),
        .init(name: "Front Squat", equipment: .barbell, aliases: ["front squats"]),
        .init(name: "Bench Press", equipment: .barbell, aliases: ["bench", "barbell bench", "flat bench"]),
        .init(name: "Incline Bench Press", equipment: .barbell, aliases: ["incline bench", "incline press"]),
        .init(name: "Overhead Press", equipment: .barbell, aliases: ["ohp", "shoulder press", "military press", "press"]),
        .init(name: "Deadlift", equipment: .barbell, aliases: ["dead", "conventional deadlift", "deads"]),
        .init(name: "Romanian Deadlift", equipment: .barbell, aliases: ["rdl", "romanian", "rdls"]),
        .init(name: "Barbell Row", equipment: .barbell, aliases: ["bent over row", "barbell rows", "row"]),
        .init(name: "Lat Pulldown", equipment: .machine, aliases: ["pulldown", "lat pull", "pulldowns"]),
        .init(name: "Seated Cable Row", equipment: .cable, aliases: ["cable row", "seated row"]),
        .init(name: "Pull Up", equipment: .bodyweight, aliases: ["pull ups", "pullups", "chin up", "chin ups"]),
        .init(name: "Dip", equipment: .bodyweight, aliases: ["dips"]),
        .init(name: "Hammer Curl", equipment: .dumbbell, aliases: ["hammer curls"]),
        .init(name: "Bicep Curl", equipment: .dumbbell, aliases: ["curls", "dumbbell curl", "biceps curl"]),
        .init(name: "Tricep Pushdown", equipment: .cable, aliases: ["pushdown", "rope pushdown", "tricep extension"]),
        .init(name: "Lateral Raise", equipment: .dumbbell, aliases: ["side raise", "lateral raises", "side laterals"]),
        .init(name: "Leg Press", equipment: .machine, aliases: ["leg presses"]),
        .init(name: "Leg Extension", equipment: .machine, aliases: ["leg extensions", "quad extension"]),
        .init(name: "Leg Curl", equipment: .machine, aliases: ["hamstring curl", "leg curls"]),
        .init(name: "Calf Raise", equipment: .machine, aliases: ["calf raises", "calves"]),
        .init(name: "Hip Thrust", equipment: .barbell, aliases: ["hip thrusts", "glute bridge"]),
        .init(name: "Dumbbell Bench Press", equipment: .dumbbell, aliases: ["dumbbell bench", "db bench"]),
        .init(name: "Dumbbell Shoulder Press", equipment: .dumbbell, aliases: ["db shoulder press", "seated dumbbell press"]),
        .init(name: "Dumbbell Row", equipment: .dumbbell, aliases: ["one arm row", "db row"]),
    ])
}
