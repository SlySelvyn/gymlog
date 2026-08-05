// PersistenceController.swift — spec §8 (data model) + §10 (security).
// The Core Data model is defined PROGRAMMATICALLY (no .xcdatamodeld file), so
// the whole schema lives in reviewable code — friendly to a VS Code workflow.
// Store: SQLite in the app container, NSFileProtectionComplete (encrypted at
// rest, inaccessible while the device is locked).
//
// Mapping strategy: entities ↔ the pure `*Record` types from GymLogCore, so
// analytics/export/tests never touch Core Data.

import Foundation
import CoreData
import GymLogCore

final class PersistenceController {

    static let shared = PersistenceController()
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "GymLog", managedObjectModel: Self.model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let desc = container.persistentStoreDescriptions.first {
            // §10: encrypt at rest; store unreadable while device is locked.
            desc.setOption(FileProtectionType.complete as NSObject,
                           forKey: NSPersistentStoreFileProtectionKey)
        }
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed: \(error)") }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Programmatic model (spec §8)

    static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        // ---- Entities
        let workout = entity("CDWorkout", attrs: [
            ("id", .UUIDAttributeType, false),
            ("title", .stringAttributeType, false),
            ("routineName", .stringAttributeType, true),
            ("dateStart", .dateAttributeType, false),
            ("dateEnd", .dateAttributeType, true),
            ("notes", .stringAttributeType, true),
        ])
        let workoutExercise = entity("CDWorkoutExercise", attrs: [
            ("id", .UUIDAttributeType, false),
            ("order", .integer32AttributeType, false),
            ("exerciseName", .stringAttributeType, false),
            ("equipment", .stringAttributeType, false),
        ])
        let setEntry = entity("CDSetEntry", attrs: [
            ("id", .UUIDAttributeType, false),
            ("order", .integer32AttributeType, false),
            ("weight", .doubleAttributeType, false),
            ("unit", .stringAttributeType, false),
            ("reps", .integer32AttributeType, true),
            ("rpe", .doubleAttributeType, true),
            ("rir", .integer32AttributeType, true),
            ("timestamp", .dateAttributeType, false),
            ("restSeconds", .integer32AttributeType, true),
        ])
        let routine = entity("CDRoutine", attrs: [
            ("id", .UUIDAttributeType, false),
            ("name", .stringAttributeType, false),
            ("notes", .stringAttributeType, true),
            ("createdAt", .dateAttributeType, false),
            ("updatedAt", .dateAttributeType, false),
        ])
        let routineItem = entity("CDRoutineItem", attrs: [
            ("id", .UUIDAttributeType, false),
            ("order", .integer32AttributeType, false),
            ("exerciseName", .stringAttributeType, false),
            ("targetSets", .integer32AttributeType, true),
            ("targetReps", .integer32AttributeType, true),
            ("targetWeight", .doubleAttributeType, true),
        ])
        // User-added catalog exercises ("|"-joined aliases keeps schema simple).
        let exercise = entity("CDExercise", attrs: [
            ("id", .UUIDAttributeType, false),
            ("name", .stringAttributeType, false),
            ("equipment", .stringAttributeType, false),
            ("aliases", .stringAttributeType, true),
        ])

        // ---- Relationships (with inverses, cascade delete downward)
        relate(workout, "exercises", to: workoutExercise, inverseName: "workout", toMany: true, ordered: true)
        relate(routine, "items", to: routineItem, inverseName: "routine", toMany: true, ordered: true)
        relate(workoutExercise, "sets", to: setEntry, inverseName: "exercise", toMany: true, ordered: true)

        model.entities = [workout, workoutExercise, setEntry, routine, routineItem, exercise]
        return model
    }()

    private static func entity(_ name: String,
                               attrs: [(String, NSAttributeType, Bool)]) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        e.managedObjectClassName = "NSManagedObject"   // KVC access; no codegen needed
        e.properties = attrs.map { (n, t, optional) in
            let a = NSAttributeDescription()
            a.name = n; a.attributeType = t; a.isOptional = optional
            return a
        }
        return e
    }

    private static func relate(_ from: NSEntityDescription, _ name: String,
                               to dest: NSEntityDescription, inverseName: String,
                               toMany: Bool, ordered: Bool) {
        let fwd = NSRelationshipDescription()
        fwd.name = name; fwd.destinationEntity = dest
        fwd.minCount = 0; fwd.maxCount = toMany ? 0 : 1
        fwd.isOrdered = ordered
        fwd.deleteRule = .cascadeDeleteRule

        let inv = NSRelationshipDescription()
        inv.name = inverseName; inv.destinationEntity = from
        inv.minCount = 0; inv.maxCount = 1
        inv.deleteRule = .nullifyDeleteRule

        fwd.inverseRelationship = inv
        inv.inverseRelationship = fwd
        from.properties.append(fwd)
        dest.properties.append(inv)
    }

    // MARK: - Workouts

    func saveWorkout(_ record: WorkoutRecord) throws {
        let ctx = container.viewContext
        // upsert by id
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CDWorkout")
        fetch.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)
        if let existing = try ctx.fetch(fetch).first { ctx.delete(existing) }

        let w = NSEntityDescription.insertNewObject(forEntityName: "CDWorkout", into: ctx)
        w.setValue(record.id, forKey: "id")
        w.setValue(record.title, forKey: "title")
        w.setValue(record.routineName, forKey: "routineName")
        w.setValue(record.dateStart, forKey: "dateStart")
        w.setValue(record.dateEnd, forKey: "dateEnd")
        w.setValue(record.notes, forKey: "notes")

        let exSet = NSMutableOrderedSet()
        for ex in record.exercises {
            let e = NSEntityDescription.insertNewObject(forEntityName: "CDWorkoutExercise", into: ctx)
            e.setValue(ex.id, forKey: "id")
            e.setValue(Int32(ex.order), forKey: "order")
            e.setValue(ex.exerciseName, forKey: "exerciseName")
            e.setValue(ex.equipment.rawValue, forKey: "equipment")
            let setSet = NSMutableOrderedSet()
            for s in ex.sets {
                let se = NSEntityDescription.insertNewObject(forEntityName: "CDSetEntry", into: ctx)
                se.setValue(s.id, forKey: "id")
                se.setValue(Int32(s.order), forKey: "order")
                se.setValue(s.weight, forKey: "weight")
                se.setValue(s.unit.rawValue, forKey: "unit")
                se.setValue(s.reps.map(Int32.init), forKey: "reps")
                se.setValue(s.rpe, forKey: "rpe")
                se.setValue(s.rir.map(Int32.init), forKey: "rir")
                se.setValue(s.timestamp, forKey: "timestamp")
                se.setValue(s.restSeconds.map(Int32.init), forKey: "restSeconds")
                setSet.add(se)
            }
            e.setValue(setSet, forKey: "sets")
            exSet.add(e)
        }
        w.setValue(exSet, forKey: "exercises")
        try ctx.save()
    }

    func loadWorkouts() -> [WorkoutRecord] {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CDWorkout")
        fetch.sortDescriptors = [NSSortDescriptor(key: "dateStart", ascending: false)]
        guard let rows = try? container.viewContext.fetch(fetch) else { return [] }
        return rows.map { w in
            let exercises = ((w.value(forKey: "exercises") as? NSOrderedSet)?.array as? [NSManagedObject] ?? [])
                .map { e -> ExerciseSessionRecord in
                    let sets = ((e.value(forKey: "sets") as? NSOrderedSet)?.array as? [NSManagedObject] ?? [])
                        .map { s in
                            SetRecord(
                                id: s.value(forKey: "id") as? UUID ?? UUID(),
                                order: Int(s.value(forKey: "order") as? Int32 ?? 0),
                                weight: s.value(forKey: "weight") as? Double ?? 0,
                                unit: WeightUnit(rawValue: s.value(forKey: "unit") as? String ?? "lb") ?? .lb,
                                reps: (s.value(forKey: "reps") as? Int32).map(Int.init),
                                rpe: s.value(forKey: "rpe") as? Double,
                                rir: (s.value(forKey: "rir") as? Int32).map(Int.init),
                                timestamp: s.value(forKey: "timestamp") as? Date ?? Date(),
                                restSeconds: (s.value(forKey: "restSeconds") as? Int32).map(Int.init))
                        }
                    return ExerciseSessionRecord(
                        id: e.value(forKey: "id") as? UUID ?? UUID(),
                        order: Int(e.value(forKey: "order") as? Int32 ?? 0),
                        exerciseName: e.value(forKey: "exerciseName") as? String ?? "",
                        equipment: EquipmentType(rawValue: e.value(forKey: "equipment") as? String ?? "other") ?? .other,
                        sets: sets)
                }
            return WorkoutRecord(
                id: w.value(forKey: "id") as? UUID ?? UUID(),
                title: w.value(forKey: "title") as? String ?? "Workout",
                routineName: w.value(forKey: "routineName") as? String,
                dateStart: w.value(forKey: "dateStart") as? Date ?? Date(),
                dateEnd: w.value(forKey: "dateEnd") as? Date,
                notes: w.value(forKey: "notes") as? String,
                exercises: exercises)
        }
    }

    func deleteWorkout(id: UUID) throws {
        let ctx = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CDWorkout")
        fetch.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        for row in try ctx.fetch(fetch) { ctx.delete(row) }
        try ctx.save()
    }

    // MARK: - Routines

    func saveRoutine(_ record: RoutineRecord) throws {
        let ctx = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CDRoutine")
        fetch.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)
        if let existing = try ctx.fetch(fetch).first { ctx.delete(existing) }

        let r = NSEntityDescription.insertNewObject(forEntityName: "CDRoutine", into: ctx)
        r.setValue(record.id, forKey: "id")
        r.setValue(record.name, forKey: "name")
        r.setValue(record.notes, forKey: "notes")
        r.setValue(record.createdAt, forKey: "createdAt")
        r.setValue(Date(), forKey: "updatedAt")
        let items = NSMutableOrderedSet()
        for item in record.items {
            let i = NSEntityDescription.insertNewObject(forEntityName: "CDRoutineItem", into: ctx)
            i.setValue(item.id, forKey: "id")
            i.setValue(Int32(item.order), forKey: "order")
            i.setValue(item.exerciseName, forKey: "exerciseName")
            i.setValue(item.targetSets.map(Int32.init), forKey: "targetSets")
            i.setValue(item.targetReps.map(Int32.init), forKey: "targetReps")
            i.setValue(item.targetWeight, forKey: "targetWeight")
            items.add(i)
        }
        r.setValue(items, forKey: "items")
        try ctx.save()
    }

    func loadRoutines() -> [RoutineRecord] {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CDRoutine")
        fetch.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        guard let rows = try? container.viewContext.fetch(fetch) else { return [] }
        return rows.map { r in
            let items = ((r.value(forKey: "items") as? NSOrderedSet)?.array as? [NSManagedObject] ?? [])
                .map { i in
                    RoutineItemRecord(
                        id: i.value(forKey: "id") as? UUID ?? UUID(),
                        order: Int(i.value(forKey: "order") as? Int32 ?? 0),
                        exerciseName: i.value(forKey: "exerciseName") as? String ?? "",
                        targetSets: (i.value(forKey: "targetSets") as? Int32).map(Int.init),
                        targetReps: (i.value(forKey: "targetReps") as? Int32).map(Int.init),
                        targetWeight: i.value(forKey: "targetWeight") as? Double)
                }
            return RoutineRecord(
                id: r.value(forKey: "id") as? UUID ?? UUID(),
                name: r.value(forKey: "name") as? String ?? "Routine",
                notes: r.value(forKey: "notes") as? String,
                createdAt: r.value(forKey: "createdAt") as? Date ?? Date(),
                updatedAt: r.value(forKey: "updatedAt") as? Date ?? Date(),
                items: items)
        }
    }

    func deleteRoutine(id: UUID) throws {
        let ctx = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CDRoutine")
        fetch.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        for row in try ctx.fetch(fetch) { ctx.delete(row) }
        try ctx.save()
    }
}
