// AnalyticsCalculator.swift — spec §12. All computed locally, pure functions.
// The dashboard recomputes on view appear; nothing is cached or networked.

import Foundation

public enum Period: CaseIterable, Sendable {
    case week, month, year
}

public struct PeriodSummary: Equatable, Sendable {
    public var totalVolume: Double          // Σ weight × reps, display unit
    public var totalWeightMoved: Double     // same formula, exposed per spec naming
    public var workoutsCount: Int
    public var setsCount: Int
    public var avgSessionDuration: TimeInterval
}

public enum AnalyticsCalculator {

    static let lbPerKg = 2.2046226218

    // MARK: Unit normalization

    public static func convert(_ weight: Double, from: WeightUnit, to: WeightUnit) -> Double {
        guard from != to else { return weight }
        return from == .kg ? weight * lbPerKg : weight / lbPerKg
    }

    // MARK: Set / session volume (§12)

    /// Set volume = weight × reps, normalized to the display unit.
    public static func setVolume(_ set: SetRecord, displayUnit: WeightUnit) -> Double {
        let w = convert(set.weight, from: set.unit, to: displayUnit)
        return w * Double(set.reps ?? 0)
    }

    public static func sessionVolume(_ workout: WorkoutRecord, displayUnit: WeightUnit) -> Double {
        workout.exercises.flatMap(\.sets).reduce(0) { $0 + setVolume($1, displayUnit: displayUnit) }
    }

    // MARK: Period math

    /// Rolling period range ending at `reference` (default now).
    public static func range(for period: Period, reference: Date = Date(),
                             calendar: Calendar = .current) -> DateInterval {
        let start: Date
        switch period {
        case .week:  start = calendar.date(byAdding: .day, value: -7, to: reference)!
        case .month: start = calendar.date(byAdding: .month, value: -1, to: reference)!
        case .year:  start = calendar.date(byAdding: .year, value: -1, to: reference)!
        }
        return DateInterval(start: start, end: reference)
    }

    public static func workouts(_ all: [WorkoutRecord], in interval: DateInterval) -> [WorkoutRecord] {
        all.filter { interval.contains($0.dateStart) }
    }

    public static func summary(_ all: [WorkoutRecord], period: Period,
                               displayUnit: WeightUnit,
                               reference: Date = Date()) -> PeriodSummary {
        let ws = workouts(all, in: range(for: period, reference: reference))
        let sets = ws.flatMap(\.exercises).flatMap(\.sets)
        let volume = ws.reduce(0) { $0 + sessionVolume($1, displayUnit: displayUnit) }
        let avgDur = ws.isEmpty ? 0 : ws.map(\.duration).reduce(0, +) / Double(ws.count)
        return PeriodSummary(totalVolume: volume,
                             totalWeightMoved: volume,
                             workoutsCount: ws.count,
                             setsCount: sets.count,
                             avgSessionDuration: avgDur)
    }

    // MARK: Exercise-level stats

    /// Count of distinct workouts containing the exercise (§12 frequency).
    public static func frequency(of exerciseName: String, in all: [WorkoutRecord]) -> Int {
        all.filter { w in w.exercises.contains { $0.exerciseName == exerciseName } }.count
    }

    /// Top set = max weight, tie-break higher reps (§12).
    public static func topSet(of exerciseName: String, in workout: WorkoutRecord,
                              displayUnit: WeightUnit) -> SetRecord? {
        let sets = workout.exercises.filter { $0.exerciseName == exerciseName }.flatMap(\.sets)
        return sets.max { a, b in
            let wa = convert(a.weight, from: a.unit, to: displayUnit)
            let wb = convert(b.weight, from: b.unit, to: displayUnit)
            if wa != wb { return wa < wb }
            return (a.reps ?? 0) < (b.reps ?? 0)
        }
    }

    /// Estimated 1RM — Epley: weight × (1 + reps/30) (§12).
    /// reps == 1 returns the weight itself.
    public static func epley1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// Per-workout best estimated 1RM series for an exercise (chart data).
    public static func e1RMSeries(of exerciseName: String, in all: [WorkoutRecord],
                                  displayUnit: WeightUnit) -> [(date: Date, e1RM: Double)] {
        all.sorted { $0.dateStart < $1.dateStart }.compactMap { w in
            let sets = w.exercises.filter { $0.exerciseName == exerciseName }.flatMap(\.sets)
            let best = sets.compactMap { s -> Double? in
                guard let reps = s.reps, reps > 0 else { return nil }
                let wConv = convert(s.weight, from: s.unit, to: displayUnit)
                return epley1RM(weight: wConv, reps: reps)
            }.max()
            return best.map { (w.dateStart, $0) }
        }
    }

    /// Weekly volume buckets for the bar chart (last `weeks` weeks).
    public static func weeklyVolume(_ all: [WorkoutRecord], weeks: Int,
                                    displayUnit: WeightUnit,
                                    reference: Date = Date(),
                                    calendar: Calendar = .current) -> [(weekStart: Date, volume: Double)] {
        var buckets: [(Date, Double)] = []
        for i in stride(from: weeks - 1, through: 0, by: -1) {
            guard let end = calendar.date(byAdding: .day, value: -7 * i, to: reference),
                  let start = calendar.date(byAdding: .day, value: -7, to: end) else { continue }
            let interval = DateInterval(start: start, end: end)
            let vol = workouts(all, in: interval)
                .reduce(0) { $0 + sessionVolume($1, displayUnit: displayUnit) }
            buckets.append((start, vol))
        }
        return buckets
    }

    /// Distinct exercise names across history, most frequent first.
    public static func exerciseNamesByFrequency(_ all: [WorkoutRecord]) -> [String] {
        var counts: [String: Int] = [:]
        for w in all {
            for name in Set(w.exercises.map(\.exerciseName)) {
                counts[name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }
}
