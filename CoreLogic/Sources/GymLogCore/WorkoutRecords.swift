// WorkoutRecords.swift — platform-independent session records (spec §8 shapes).
// These are the value types the analytics calculator (§12) and export service
// (§15) consume. The iOS app maps Core Data entities ↔ these records, so all
// number-crunching stays pure and unit-testable on any platform.

import Foundation

public struct SetRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var order: Int
    public var weight: Double
    public var unit: WeightUnit
    public var reps: Int?
    public var rpe: Double?
    public var rir: Int?
    public var timestamp: Date
    public var restSeconds: Int?

    public init(id: UUID = UUID(), order: Int, weight: Double, unit: WeightUnit,
                reps: Int? = nil, rpe: Double? = nil, rir: Int? = nil,
                timestamp: Date = Date(), restSeconds: Int? = nil) {
        self.id = id; self.order = order; self.weight = weight; self.unit = unit
        self.reps = reps; self.rpe = rpe; self.rir = rir
        self.timestamp = timestamp; self.restSeconds = restSeconds
    }
}

public struct ExerciseSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var order: Int
    public var exerciseName: String
    public var equipment: EquipmentType
    public var sets: [SetRecord]

    public init(id: UUID = UUID(), order: Int, exerciseName: String,
                equipment: EquipmentType, sets: [SetRecord] = []) {
        self.id = id; self.order = order; self.exerciseName = exerciseName
        self.equipment = equipment; self.sets = sets
    }
}

public struct WorkoutRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var routineName: String?
    public var dateStart: Date
    public var dateEnd: Date?
    public var notes: String?
    public var exercises: [ExerciseSessionRecord]

    public init(id: UUID = UUID(), title: String, routineName: String? = nil,
                dateStart: Date = Date(), dateEnd: Date? = nil, notes: String? = nil,
                exercises: [ExerciseSessionRecord] = []) {
        self.id = id; self.title = title; self.routineName = routineName
        self.dateStart = dateStart; self.dateEnd = dateEnd; self.notes = notes
        self.exercises = exercises
    }

    /// §12: duration = dateEnd − dateStart, or last set timestamp if unfinished.
    public var duration: TimeInterval {
        let end = dateEnd
            ?? exercises.flatMap(\.sets).map(\.timestamp).max()
            ?? dateStart
        return end.timeIntervalSince(dateStart)
    }
}

// MARK: Routine templates (§8)

public struct RoutineItemRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var order: Int
    public var exerciseName: String
    public var targetSets: Int?
    public var targetReps: Int?
    public var targetWeight: Double?

    public init(id: UUID = UUID(), order: Int, exerciseName: String,
                targetSets: Int? = nil, targetReps: Int? = nil, targetWeight: Double? = nil) {
        self.id = id; self.order = order; self.exerciseName = exerciseName
        self.targetSets = targetSets; self.targetReps = targetReps; self.targetWeight = targetWeight
    }
}

public struct RoutineRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var items: [RoutineItemRecord]

    public init(id: UUID = UUID(), name: String, notes: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(),
                items: [RoutineItemRecord] = []) {
        self.id = id; self.name = name; self.notes = notes
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.items = items
    }
}

// MARK: Starter templates (§6.3)

public enum StarterRoutines {
    public static let all: [RoutineRecord] = [
        RoutineRecord(name: "Full Body A", items: [
            .init(order: 0, exerciseName: "Back Squat", targetSets: 3, targetReps: 5),
            .init(order: 1, exerciseName: "Bench Press", targetSets: 3, targetReps: 5),
            .init(order: 2, exerciseName: "Barbell Row", targetSets: 3, targetReps: 8),
        ]),
        RoutineRecord(name: "Push", items: [
            .init(order: 0, exerciseName: "Bench Press", targetSets: 4, targetReps: 6),
            .init(order: 1, exerciseName: "Overhead Press", targetSets: 3, targetReps: 8),
            .init(order: 2, exerciseName: "Tricep Pushdown", targetSets: 3, targetReps: 12),
            .init(order: 3, exerciseName: "Lateral Raise", targetSets: 3, targetReps: 15),
        ]),
        RoutineRecord(name: "Pull", items: [
            .init(order: 0, exerciseName: "Deadlift", targetSets: 3, targetReps: 5),
            .init(order: 1, exerciseName: "Lat Pulldown", targetSets: 3, targetReps: 10),
            .init(order: 2, exerciseName: "Seated Cable Row", targetSets: 3, targetReps: 10),
            .init(order: 3, exerciseName: "Hammer Curl", targetSets: 3, targetReps: 12),
        ]),
        RoutineRecord(name: "Legs", items: [
            .init(order: 0, exerciseName: "Back Squat", targetSets: 4, targetReps: 6),
            .init(order: 1, exerciseName: "Romanian Deadlift", targetSets: 3, targetReps: 8),
            .init(order: 2, exerciseName: "Leg Press", targetSets: 3, targetReps: 10),
            .init(order: 3, exerciseName: "Calf Raise", targetSets: 4, targetReps: 12),
        ]),
    ]
}
