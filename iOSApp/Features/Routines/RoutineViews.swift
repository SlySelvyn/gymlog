// RoutineViews.swift — spec §6.3. Routine list (Start / Edit cards) and the
// builder: name, ordered exercises from the searchable catalog, optional
// target sets/reps/weight, drag to reorder, swipe to delete.

import SwiftUI
import GymLogCore

// MARK: - List

struct RoutineListView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @EnvironmentObject var router: AppRouter
    @State private var editing: RoutineRecord?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(coordinator.routines) { routine in
                    RoutineCard(routine: routine,
                                lastPerformed: lastPerformed(routine),
                                onStart: {
                                    coordinator.startWorkout(from: routine)
                                    router.selectedTab = .workout
                                },
                                onEdit: { editing = routine })
                }
                .onDelete { idx in
                    for i in idx { coordinator.deleteRoutine(coordinator.routines[i]) }
                }
            }
            .navigationTitle("Routines")
            .toolbar {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { r in RoutineBuilderView(routine: r) }
            .sheet(isPresented: $creating) {
                RoutineBuilderView(routine: RoutineRecord(name: ""))
            }
            .overlay {
                if coordinator.routines.isEmpty {
                    ContentUnavailableView("No routines yet",
                                           systemImage: "list.bullet.rectangle",
                                           description: Text("Create one, or start an empty workout from the Workout tab."))
                }
            }
        }
    }

    private func lastPerformed(_ routine: RoutineRecord) -> Date? {
        coordinator.history.first { $0.routineName == routine.name }?.dateStart
    }
}

struct RoutineCard: View {
    let routine: RoutineRecord
    let lastPerformed: Date?
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routine.name).font(.headline)
            Text("\(routine.items.count) exercises"
                 + (lastPerformed.map { " · last \($0.formatted(.relative(presentation: .named)))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Start", action: onStart)
                    .buttonStyle(AccentCapsuleButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("Edit", action: onEdit)
                    .buttonStyle(BorderedCapsuleButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Builder

struct RoutineBuilderView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State var routine: RoutineRecord
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Routine name", text: $routine.name)
                }
                Section("Exercises") {
                    ForEach($routine.items) { $item in
                        RoutineItemRow(item: $item)
                    }
                    .onMove { from, to in
                        routine.items.move(fromOffsets: from, toOffset: to)
                        reindex()
                    }
                    .onDelete { idx in
                        routine.items.remove(atOffsets: idx)
                        reindex()
                    }
                    Button {
                        showPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GymTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(GymTheme.accent.opacity(0.4),
                                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            )
                    }
                }
            }
            .navigationTitle(routine.name.isEmpty ? "New Routine" : routine.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        coordinator.saveRoutine(routine)
                        dismiss()
                    }
                    .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { ex in
                    routine.items.append(RoutineItemRecord(order: routine.items.count,
                                                           exerciseName: ex.name))
                }
            }
        }
    }

    private func reindex() {
        for i in routine.items.indices { routine.items[i].order = i }
    }
}

struct RoutineItemRow: View {
    @Binding var item: RoutineItemRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.exerciseName).font(.body)
            HStack(spacing: 8) {
                targetField("Sets", value: Binding(
                    get: { item.targetSets.map(String.init) ?? "" },
                    set: { item.targetSets = Int($0) }))
                targetField("Reps", value: Binding(
                    get: { item.targetReps.map(String.init) ?? "" },
                    set: { item.targetReps = Int($0) }))
                targetField("Weight", value: Binding(
                    get: { item.targetWeight.map { String(Int($0)) } ?? "" },
                    set: { item.targetWeight = Double($0) }))
            }
        }
    }

    private func targetField(_ label: String, value: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.primary.opacity(0.4))
            TextField("—", text: value)
                .keyboardType(.numberPad)
                .frame(width: 34)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
    }
}

// MARK: - Exercise picker (shared, searchable catalog)

struct ExercisePickerView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onPick: (ExerciseDefinition) -> Void

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id) { ex in
                Button {
                    onPick(ex)
                    dismiss()
                } label: {
                    HStack {
                        Text(ex.name)
                        Spacer()
                        Text(ex.equipment.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Pick exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var filtered: [ExerciseDefinition] {
        let all = coordinator.parser.catalog.exercises
        guard !search.isEmpty else { return all }
        let key = search.lowercased()
        return all.filter { $0.name.lowercased().contains(key) || $0.aliases.contains { $0.contains(key) } }
    }
}
