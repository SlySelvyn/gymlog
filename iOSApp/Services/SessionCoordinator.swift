// SessionCoordinator.swift — spec §7.6 state machine + §11 rest timer.
// Owns the active WorkoutRecord and currentExercise; single entry point for
// both the in-app mic and the App Intent. Autosaves after every committed set
// so a crash/force-quit mid-workout loses nothing.

import Foundation
import SwiftUI
import GymLogCore

@MainActor
final class SessionCoordinator: ObservableObject {

    static let shared = SessionCoordinator()

    @Published private(set) var activeWorkout: WorkoutRecord?
    @Published private(set) var currentExerciseIndex: Int?
    @Published var lastToast: String?
    @Published private(set) var history: [WorkoutRecord] = []
    @Published private(set) var routines: [RoutineRecord] = []

    let parser = SetParser()
    let persistence = PersistenceController.shared

    // Settings-backed prefs (§6.5)
    @AppStorage("units") private var unitsRaw = WeightUnit.lb.rawValue
    @AppStorage("restCapSeconds") var restCapSeconds = 600
    @AppStorage("allowWeightOnlyDraft") private var allowWeightOnly = false

    var prefs: ParserPrefs {
        ParserPrefs(defaultUnit: WeightUnit(rawValue: unitsRaw) ?? .lb,
                    allowWeightOnlyDraft: allowWeightOnly)
    }
    var displayUnit: WeightUnit { WeightUnit(rawValue: unitsRaw) ?? .lb }

    var currentExercise: ExerciseSessionRecord? {
        guard let w = activeWorkout, let i = currentExerciseIndex,
              w.exercises.indices.contains(i) else { return nil }
        return w.exercises[i]
    }

    private init() {
        reloadFromStore()
        seedStarterRoutinesIfEmpty()
        resumeUnfinishedWorkoutIfAny()
    }

    // MARK: Store sync

    func reloadFromStore() {
        history = persistence.loadWorkouts().filter { $0.dateEnd != nil }
        routines = persistence.loadRoutines()
    }

    private func seedStarterRoutinesIfEmpty() {
        guard routines.isEmpty, history.isEmpty else { return }
        for r in StarterRoutines.all { try? persistence.saveRoutine(r) }
        routines = persistence.loadRoutines()
    }

    /// Crash recovery: an autosaved workout with no dateEnd resumes as active.
    private func resumeUnfinishedWorkoutIfAny() {
        if let unfinished = persistence.loadWorkouts().first(where: { $0.dateEnd == nil }) {
            activeWorkout = unfinished
            currentExerciseIndex = unfinished.exercises.indices.last
        }
    }

    // MARK: Session lifecycle

    enum MissingSessionPolicy { case autoStartUntitled, promptIfMissing }

    func ensureActiveWorkout(policy: MissingSessionPolicy = .autoStartUntitled) {
        guard activeWorkout == nil else { return }
        if case .autoStartUntitled = policy {
            startWorkout(title: "Untitled Workout")
        }
    }

    func startWorkout(title: String, routine: RoutineRecord? = nil) {
        activeWorkout = WorkoutRecord(title: title, routineName: routine?.name)
        currentExerciseIndex = nil
        autosave()
    }

    /// US-4: activate a routine → session carries its name; targets shown in UI.
    func startWorkout(from routine: RoutineRecord) {
        startWorkout(title: routine.name, routine: routine)
    }

    func renameActiveWorkout(_ title: String) {
        activeWorkout?.title = title
        autosave()
    }

    func finishWorkout() {
        guard var w = activeWorkout else { return }
        w.dateEnd = Date()
        try? persistence.saveWorkout(w)
        activeWorkout = nil
        currentExerciseIndex = nil
        reloadFromStore()
        lastToast = "Workout saved — \(w.title)"
    }

    func discardWorkout() {
        if let id = activeWorkout?.id { try? persistence.deleteWorkout(id: id) }
        activeWorkout = nil
        currentExerciseIndex = nil
    }

    // MARK: Voice commit path (spec §7.6)

    /// Entry point for in-app mic + App Intent. Parses, commits if valid,
    /// returns the result so the UI can prompt on invalid/unresolved.
    @discardableResult
    func handleTranscript(_ transcript: String) -> ParseResult {
        ensureActiveWorkout()
        let result = parser.parse(transcript,
                                  currentExerciseName: currentExercise?.exerciseName,
                                  prefs: prefs)
        if case .valid(let draft, let match, _) = result {
            commit(draft, match)
        }
        return result
    }

    /// Parse without committing (confirm-first mode shows the chip first).
    func preview(_ transcript: String) -> ParseResult {
        parser.parse(transcript,
                     currentExerciseName: currentExercise?.exerciseName,
                     prefs: prefs)
    }

    func commit(_ draft: SetDraft, _ match: ExerciseMatch) {
        guard activeWorkout != nil else { return }

        let targetIndex: Int
        switch match {
        case .inherit:
            guard let i = currentExerciseIndex else { return }
            targetIndex = i
        case .matched(let ex) where ex.name == currentExercise?.exerciseName:
            targetIndex = currentExerciseIndex!          // same exercise re-named
        case .matched(let ex):                           // new exercise → new group
            let group = ExerciseSessionRecord(order: activeWorkout!.exercises.count,
                                              exerciseName: ex.name,
                                              equipment: ex.equipment)
            activeWorkout!.exercises.append(group)
            targetIndex = activeWorkout!.exercises.count - 1
            currentExerciseIndex = targetIndex
        case .unresolved, .missing:
            return   // UI confirms a suggestion, then calls commit again
        }

        let now = Date()
        var set = SetRecord(order: activeWorkout!.exercises[targetIndex].sets.count,
                            weight: draft.weight ?? 0,
                            unit: draft.unit ?? displayUnit,
                            reps: draft.reps, rpe: draft.rpe, rir: draft.rir,
                            timestamp: now)

        // §11: close previous set's rest, clamped to the cap.
        if let prevIdx = activeWorkout!.exercises[targetIndex].sets.indices.last {
            let gap = Int(now.timeIntervalSince(activeWorkout!.exercises[targetIndex].sets[prevIdx].timestamp))
            activeWorkout!.exercises[targetIndex].sets[prevIdx].restSeconds =
                max(0, min(gap, restCapSeconds))
        }
        _ = set   // silence unused-mutation lint on some toolchains
        activeWorkout!.exercises[targetIndex].sets.append(set)

        autosave()
        lastToast = "\(activeWorkout!.exercises[targetIndex].exerciseName) \(summary(set))"
    }

    /// Manual set entry (§6.1 secondary action) reuses the same path.
    func addManualSet(exercise: ExerciseDefinition, weight: Double, reps: Int,
                      rpe: Double? = nil, rir: Int? = nil) {
        ensureActiveWorkout()
        commit(SetDraft(weight: weight, unit: displayUnit, reps: reps, rpe: rpe, rir: rir),
               .matched(exercise))
    }

    // MARK: Edit / undo (US-5)

    func undoLastSet() {
        guard var w = activeWorkout,
              let gi = w.exercises.lastIndex(where: { !$0.sets.isEmpty }) else { return }
        w.exercises[gi].sets.removeLast()
        if w.exercises[gi].sets.isEmpty {                // empty group → remove
            w.exercises.remove(at: gi)
            currentExerciseIndex = w.exercises.indices.last
        }
        activeWorkout = w
        autosave()
        lastToast = "Undid last set"
    }

    func updateSet(exerciseIndex: Int, setIndex: Int, _ transform: (inout SetRecord) -> Void) {
        guard activeWorkout?.exercises.indices.contains(exerciseIndex) == true,
              activeWorkout!.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        transform(&activeWorkout!.exercises[exerciseIndex].sets[setIndex])
        autosave()
    }

    private func autosave() {
        if let w = activeWorkout { try? persistence.saveWorkout(w) }
    }

    // MARK: Routines CRUD (US-4)

    func saveRoutine(_ r: RoutineRecord) {
        try? persistence.saveRoutine(r)
        reloadFromStore()
    }

    func deleteRoutine(_ r: RoutineRecord) {
        try? persistence.deleteRoutine(id: r.id)
        reloadFromStore()
    }

    // MARK: Helpers

    func summary(_ s: SetRecord) -> String {
        let w = s.weight.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(s.weight)) : String(s.weight)
        return "\(w)\(s.unit.rawValue) × \(s.reps.map(String.init) ?? "?")"
    }
}

// MARK: App routing

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var showVoiceCapture = false
    @Published var autoRecord = false
    @Published var selectedTab: Tab = .workout

    enum Tab: Hashable { case workout, routines, dashboard, profile }

    func presentVoiceCapture(autoRecord: Bool) {
        selectedTab = .workout
        self.autoRecord = autoRecord
        self.showVoiceCapture = true
    }
}
