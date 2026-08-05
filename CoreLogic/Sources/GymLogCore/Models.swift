// Models.swift — value types used by the voice-parsing pipeline (spec §7.5).
// These are deliberately Foundation-only so they compile on any platform.

import Foundation

// MARK: - Units

public enum WeightUnit: String, Codable, Equatable, Sendable {
    case lb
    case kg

    public init?(spoken: String) {
        switch spoken.lowercased() {
        case "lb", "lbs", "pound", "pounds": self = .lb
        case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms": self = .kg
        default: return nil
        }
    }
}

// MARK: - Equipment

public enum EquipmentType: String, Codable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, other
}

// MARK: - Exercise (catalog definition)

/// A catalog exercise. In the app this maps 1:1 onto the Core Data `Exercise`
/// entity; here it is a plain value type so the parser stays pure (spec §9).
public struct ExerciseDefinition: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let equipment: EquipmentType
    public let aliases: [String]

    public init(id: UUID = UUID(), name: String, equipment: EquipmentType, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.aliases = aliases
    }
}

// MARK: - Parse output

/// The slots the parser fills from one utterance (spec §7.5).
public struct SetDraft: Equatable, Sendable {
    public var exerciseName: String?   // nil => inherit current exercise
    public var weight: Double?
    public var unit: WeightUnit?       // default applied from prefs at commit
    public var reps: Int?
    public var rpe: Double?            // 0...10 in 0.5 steps
    public var rir: Int?               // 0...10

    public init(exerciseName: String? = nil,
                weight: Double? = nil,
                unit: WeightUnit? = nil,
                reps: Int? = nil,
                rpe: Double? = nil,
                rir: Int? = nil) {
        self.exerciseName = exerciseName
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
    }
}

/// How the spoken (or omitted) exercise name resolved against the catalog.
public enum ExerciseMatch: Equatable, Sendable {
    /// No name spoken → keep logging on the current exercise group.
    case inherit
    /// Name matched a catalog exercise (exactly or fuzzily above threshold).
    case matched(ExerciseDefinition)
    /// Name spoken but below confidence → surface suggestions in the confirm chip.
    case unresolved(spoken: String, suggestions: [ExerciseDefinition])
    /// No name spoken AND no current exercise exists.
    case missing
}

/// Why a parse could not be committed as-is.
public enum ParseProblem: Equatable, Sendable {
    case emptyUtterance
    case noNumbersFound
    case ambiguousNumbers(String)      // e.g. "8 and 12 — which is the weight?"
    case missingReps                   // weight-only draft ([OPEN E])
    case missingWeight
    case invalidRPE(Double)
    case invalidRIR(Int)
    case noExerciseContext             // nothing spoken, nothing to inherit
}

/// Final parser output (spec §7.5 / §7.6).
public enum ParseResult: Equatable, Sendable {
    /// Ready to commit. `warnings` carries soft issues (e.g. `.missingReps`
    /// when policy allows weight-only drafts).
    case valid(SetDraft, ExerciseMatch, warnings: [ParseProblem])
    /// Needs the user to repeat / confirm. Raw transcript is echoed in the UI.
    case invalid(ParseProblem, transcript: String)
}

// MARK: - Preferences relevant to parsing

public struct ParserPrefs: Sendable {
    public var defaultUnit: WeightUnit
    /// [OPEN E] policy: allow committing a set that has weight but no reps yet.
    public var allowWeightOnlyDraft: Bool

    public init(defaultUnit: WeightUnit = .lb, allowWeightOnlyDraft: Bool = false) {
        self.defaultUnit = defaultUnit
        self.allowWeightOnlyDraft = allowWeightOnlyDraft
    }
}
