// DashboardView.swift — spec §6.4 + §12. All numbers computed locally by
// AnalyticsCalculator on view appear; nothing cached, nothing networked.
// Charts: weekly volume bars, per-exercise estimated-1RM (Epley) line.
// History list (reverse-chronological) → read-only session detail.

import SwiftUI
import Charts
import GymLogCore

struct DashboardView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @State private var period: Period = .week
    @State private var selectedExercise: String?

    private var unit: WeightUnit { coordinator.displayUnit }
    private var history: [WorkoutRecord] { coordinator.history }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    periodPicker
                    summaryCards
                    weeklyVolumeChart
                    e1RMChart
                    historyList
                }
                .padding()
            }
            .background(GymTheme.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .onAppear {
                coordinator.reloadFromStore()
                if selectedExercise == nil {
                    selectedExercise = AnalyticsCalculator.exerciseNamesByFrequency(history).first
                }
            }
        }
    }

    // MARK: Period picker + summary cards

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            Text("Week").tag(Period.week)
            Text("Month").tag(Period.month)
            Text("Year").tag(Period.year)
        }
        .pickerStyle(.segmented)
    }

    private var summaryCards: some View {
        let s = AnalyticsCalculator.summary(history, period: period, displayUnit: unit)
        let empty = s.workoutsCount == 0
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCardView(value: empty ? "—" : Int(s.totalVolume).formatted(),
                         unit: empty ? nil : unit.rawValue, label: "Volume", dimmed: empty)
            StatCardView(value: "\(s.workoutsCount)", label: "Workouts", dimmed: empty)
            StatCardView(value: "\(s.setsCount)", label: "Sets", dimmed: empty)
            StatCardView(value: empty ? "—" : durationString(s.avgSessionDuration),
                         label: "Avg session", dimmed: empty)
        }
    }

    private func durationString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    // MARK: Weekly volume bars

    private var weeklyVolumeChart: some View {
        let data = AnalyticsCalculator.weeklyVolume(history, weeks: 8, displayUnit: unit)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Weekly volume").font(.headline)
            Chart(data, id: \.weekStart) { bucket in
                BarMark(
                    x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                    y: .value("Volume", bucket.volume)
                )
                .foregroundStyle(bucket.weekStart == data.last?.weekStart
                                 ? GymTheme.accent
                                 : GymTheme.accent.opacity(0.28))
                .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
        }
        .padding()
        .gymCard()
    }

    // MARK: Per-exercise e1RM line

    private var e1RMChart: some View {
        let names = AnalyticsCalculator.exerciseNamesByFrequency(history)
        let series = selectedExercise.map {
            AnalyticsCalculator.e1RMSeries(of: $0, in: history, displayUnit: unit)
        } ?? []

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Estimated 1RM").font(.headline)
                Spacer()
                Picker("Exercise", selection: $selectedExercise) {
                    ForEach(names, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            if series.count >= 2 {
                Chart(series, id: \.date) { point in
                    LineMark(x: .value("Date", point.date),
                             y: .value("e1RM", point.e1RM))
                        .foregroundStyle(GymTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    if point.date == series.last?.date {
                        PointMark(x: .value("Date", point.date),
                                  y: .value("e1RM", point.e1RM))
                            .foregroundStyle(GymTheme.accent)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 100)
                HStack {
                    Text("\(series.count) workouts")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(GymTheme.textFaint)
                    Spacer()
                    Text("\(Int(series.last?.e1RM ?? 0)) \(unit.rawValue)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(GymTheme.accent)
                }
            } else {
                Text("Log this exercise in at least two workouts to see a trend.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding()
        .gymCard()
    }

    // MARK: History (§5: implicit, reverse-chronological)

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline)
            if history.isEmpty {
                Text("Finished workouts appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(history) { w in
                NavigationLink {
                    SessionDetailView(workout: w)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(w.title).font(.body)
                            Text(w.dateStart.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(AnalyticsCalculator.sessionVolume(w, displayUnit: unit))) \(unit.rawValue)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

// MARK: Read-only session detail

struct SessionDetailView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    let workout: WorkoutRecord

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: workout.dateStart.formatted(date: .long, time: .shortened))
                LabeledContent("Duration", value: "\(Int(workout.duration) / 60) min")
                LabeledContent("Volume", value: "\(Int(AnalyticsCalculator.sessionVolume(workout, displayUnit: coordinator.displayUnit))) \(coordinator.displayUnit.rawValue)")
                if let routine = workout.routineName {
                    LabeledContent("Routine", value: routine)
                }
            }
            ForEach(workout.exercises) { ex in
                Section(ex.exerciseName) {
                    ForEach(ex.sets) { s in
                        HStack {
                            Text("Set \(s.order + 1)")
                            Spacer()
                            Text(coordinator.summary(s)).monospacedDigit()
                            if let rpe = s.rpe {
                                Text("RPE \(rpe.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rpe)) : String(rpe))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.title)
    }
}
