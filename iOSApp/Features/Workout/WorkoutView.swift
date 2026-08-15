// WorkoutView.swift — implements mockups A1 (active), A2 (empty), A3 (finish
// dialog) from `GymLog Mockups.dc.html`, using DesignSystem/Theme.swift.

import SwiftUI
import GymLogCore

struct WorkoutView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @EnvironmentObject var router: AppRouter
    @State private var showManualAdd = false
    @State private var showFinishConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.activeWorkout != nil {
                    activeSession
                } else {
                    emptyState
                }
            }
            .background(GymTheme.background.ignoresSafeArea())
            .toolbar(coordinator.activeWorkout == nil ? .visible : .hidden, for: .navigationBar)
            .navigationTitle("Workout")
        }
    }

    // MARK: Active session (A1)

    private var activeSession: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array((coordinator.activeWorkout?.exercises ?? []).enumerated()),
                            id: \.element.id) { idx, ex in
                        ExerciseCard(exercise: ex,
                                     isCurrent: idx == coordinator.currentExerciseIndex,
                                     isLatest: idx == latestExerciseIndex,
                                     exerciseIndex: idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            bottomBar
        }
        .sheet(isPresented: $showManualAdd) { ManualSetSheet() }
        .confirmationDialog(finishTitle, isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish & save") { coordinator.finishWorkout() }
            Button("Keep going", role: .cancel) {}
            Button("Discard workout", role: .destructive) { coordinator.discardWorkout() }
        }
    }

    /// A3: dialog title carries the session summary — "52:14 · 8 sets · 12,480 lb"
    private var finishTitle: String {
        guard let w = coordinator.activeWorkout else { return "Finish workout?" }
        let sets = w.exercises.flatMap(\.sets).count
        let vol = Int(AnalyticsCalculator.sessionVolume(w, displayUnit: coordinator.displayUnit))
        return "Finish workout?\n\(formatClock(Date().timeIntervalSince(w.dateStart))) · \(sets) sets · \(vol.formatted()) \(coordinator.displayUnit.rawValue)"
    }

    /// Index of the exercise that received the most recent set (checkmark row lives there).
    private var latestExerciseIndex: Int? {
        coordinator.activeWorkout?.exercises.indices.max { a, b in
            let ta = coordinator.activeWorkout!.exercises[a].sets.map(\.timestamp).max() ?? .distantPast
            let tb = coordinator.activeWorkout!.exercises[b].sets.map(\.timestamp).max() ?? .distantPast
            return ta < tb
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Workout name", text: Binding(
                        get: { coordinator.activeWorkout?.title ?? "" },
                        set: { coordinator.renameActiveWorkout($0) }))
                        .font(.system(size: 22, weight: .bold))
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.35))
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 14) {
                        TimerLabel(kind: .session, text: elapsed)
                        if let rest = restElapsed {
                            TimerLabel(kind: .rest, text: rest)
                        }
                    }
                }
            }
            Spacer()
            Button("Finish") { showFinishConfirm = true }
                .buttonStyle(AccentCapsuleButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var elapsed: String {
        guard let start = coordinator.activeWorkout?.dateStart else { return "0:00" }
        return formatClock(Date().timeIntervalSince(start))
    }

    private var restElapsed: String? {
        guard let last = coordinator.activeWorkout?.exercises
            .flatMap(\.sets).map(\.timestamp).max() else { return nil }
        return formatClock(Date().timeIntervalSince(last))
    }

    private func formatClock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Bottom bar (A1)

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HoldToLogMicButton {
                router.presentVoiceCapture(autoRecord: true)
            }
            HStack {
                Button { coordinator.undoLastSet() } label: {
                    Text("Undo last set")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                Spacer()
                Button { showManualAdd = true } label: {
                    Text("Add manually")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GymTheme.accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Empty state (A2)

    private var emptyState: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(GymTheme.accent.opacity(0.12))
                            .overlay(Circle().strokeBorder(GymTheme.accent.opacity(0.35), lineWidth: 1.5))
                            .frame(width: 96, height: 96)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(GymTheme.accent)
                    }
                    .padding(.top, 40)

                    Text("Press and hold to log\nyour first set")
                        .font(.system(size: 21, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)

                    Text("Or press your Action Button —\nthe mic is already hot.")
                        .font(.system(size: 14))
                        .foregroundStyle(GymTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)

                    NavigationLink {
                        VoiceGuideView()
                    } label: {
                        Text("How voice logging works →")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GymTheme.accent)
                    }
                    .padding(.top, 8)

                    Button("Start empty workout") {
                        coordinator.startWorkout(title: "Untitled Workout")
                    }
                    .buttonStyle(AccentCapsuleButtonStyle(height: 48))
                    .padding(.top, 26)

                    if !coordinator.routines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QUICK START")
                                .font(.system(size: 12, weight: .semibold))
                                .kerning(1)
                                .foregroundStyle(GymTheme.textFaint)
                            ForEach(coordinator.routines.prefix(3)) { routine in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(routine.name)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("\(routine.items.count) exercises"
                                             + lastPerformedSuffix(routine))
                                            .font(.system(size: 12))
                                            .foregroundStyle(GymTheme.textTertiary)
                                    }
                                    Spacer()
                                    Button("Start") { coordinator.startWorkout(from: routine) }
                                        .buttonStyle(AccentCapsuleButtonStyle(height: 32))
                                }
                                .padding(14)
                                .gymCard()
                            }
                        }
                        .padding(.top, 34)
                    }
                }
                .padding(.horizontal, 28)
            }
            HoldToLogMicButton {
                coordinator.startWorkout(title: "Untitled Workout")
                router.presentVoiceCapture(autoRecord: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func lastPerformedSuffix(_ routine: RoutineRecord) -> String {
        guard let d = coordinator.history.first(where: { $0.routineName == routine.name })?.dateStart
        else { return "" }
        return " · last \(d.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Exercise card (A1 set-row grid: # | weight×reps | RPE | rest)

struct ExerciseCard: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    let exercise: ExerciseSessionRecord
    let isCurrent: Bool
    let isLatest: Bool
    let exerciseIndex: Int
    @State private var editingSet: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if isCurrent {
                    Circle()
                        .fill(GymTheme.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: GymTheme.accent.opacity(0.8), radius: 4)
                }
                Text(exercise.exerciseName)
                    .font(.system(size: 17, weight: .semibold))
                EquipmentTag(equipment: exercise.equipment)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { i, s in
                let isCommitted = isLatest && i == exercise.sets.count - 1
                SetRow(set: s, index: i, justCommitted: isCommitted,
                       displayUnit: coordinator.displayUnit)
                    .contentShape(Rectangle())
                    .onLongPressGesture { editingSet = i }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .gymCard(isCurrent: isCurrent)
        .sheet(item: Binding(
            get: { editingSet.map { EditTarget(exerciseIndex: exerciseIndex, setIndex: $0) } },
            set: { editingSet = $0?.setIndex })) { target in
            SetEditSheet(target: target)
        }
    }
}

struct SetRow: View {
    let set: SetRecord
    let index: Int
    var justCommitted = false
    let displayUnit: WeightUnit

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: 26, alignment: .leading)

            Text(summary)
                .font(.scoreboard)

            Spacer(minLength: 4)

            if let rpe = set.rpe {
                Text("RPE \(ParsedChipView.trim(rpe))")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            if let rir = set.rir {
                Text("RIR \(rir)")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.4))
            }

            Group {
                if justCommitted {
                    ZStack {
                        Circle().fill(GymTheme.accent.opacity(0.25)).frame(width: 15, height: 15)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(GymTheme.accent)
                    }
                } else if let rest = set.restSeconds {
                    Text(restString(rest))
                        .font(.metaMono)
                        .foregroundStyle(GymTheme.rest)
                }
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            if index > 0 { Rectangle().fill(GymTheme.rowSeparator).frame(height: 0.5) }
        }
        .background(justCommitted ? GymTheme.accent.opacity(0.12) : .clear)
    }

    private var summary: String {
        let w = ParsedChipView.trim(set.weight)
        let r = set.reps.map(String.init) ?? "—"
        return set.weight == 0 ? "BW × \(r)" : "\(w) \(set.unit.rawValue) × \(r)"
    }

    private func restString(_ s: Int) -> String {
        s < 100 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct EditTarget: Identifiable {
    let exerciseIndex: Int
    let setIndex: Int
    var id: String { "\(exerciseIndex)-\(setIndex)" }
}

// MARK: - Set edit sheet (US-5)

struct SetEditSheet: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    let target: EditTarget

    @State private var weight = ""
    @State private var reps = ""
    @State private var rpe = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight", text: $weight).keyboardType(.decimalPad)
                TextField("Reps", text: $reps).keyboardType(.numberPad)
                TextField("RPE (optional)", text: $rpe).keyboardType(.decimalPad)
            }
            .navigationTitle("Edit set")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        coordinator.updateSet(exerciseIndex: target.exerciseIndex,
                                              setIndex: target.setIndex) { s in
                            if let w = Double(weight) { s.weight = w }
                            if let r = Int(reps) { s.reps = r }
                            s.rpe = Double(rpe)
                        }
                        dismiss()
                    }
                    .tint(GymTheme.accent)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let s = coordinator.activeWorkout?.exercises[safe: target.exerciseIndex]?
                    .sets[safe: target.setIndex] {
                    weight = ParsedChipView.trim(s.weight)
                    reps = s.reps.map(String.init) ?? ""
                    rpe = s.rpe.map { ParsedChipView.trim($0) } ?? ""
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Manual add sheet

struct ManualSetSheet: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: ExerciseDefinition?
    @State private var weight = ""
    @State private var reps = ""

    var body: some View {
        NavigationStack {
            Form {
                if let selected {
                    LabeledContent("Exercise", value: selected.name)
                    TextField("Weight (\(coordinator.displayUnit.rawValue))", text: $weight)
                        .keyboardType(.decimalPad)
                    TextField("Reps", text: $reps).keyboardType(.numberPad)
                    Button("Log set") {
                        if let w = Double(weight), let r = Int(reps) {
                            coordinator.addManualSet(exercise: selected, weight: w, reps: r)
                            dismiss()
                        }
                    }
                    .tint(GymTheme.accent)
                    .disabled(Double(weight) == nil || Int(reps) == nil)
                } else {
                    ForEach(filteredExercises, id: \.id) { ex in
                        Button { self.selected = ex } label: {
                            HStack {
                                Text(ex.name).foregroundStyle(.primary)
                                Spacer()
                                EquipmentTag(equipment: ex.equipment)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises")
            .navigationTitle("Add set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var filteredExercises: [ExerciseDefinition] {
        let all = coordinator.parser.catalog.exercises
        guard !search.isEmpty else { return all }
        let key = search.lowercased()
        return all.filter { ex in
            ex.name.lowercased().contains(key) || ex.aliases.contains { $0.contains(key) }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
