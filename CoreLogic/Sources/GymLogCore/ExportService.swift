// ExportService.swift — spec §15 (GDPR / portability).
// Pure string generation; the iOS layer wraps the output in a share sheet.
// CSV: one row per set. Markdown: workout → exercise → sets, human-readable.

import Foundation

public enum ExportService {

    // MARK: CSV

    public static let csvHeader =
        "date,time,routine,exercise,equipment,weight,unit,reps,rpe,rir,restSeconds"

    public static func csv(_ workouts: [WorkoutRecord]) -> String {
        var lines = [csvHeader]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        tf.locale = Locale(identifier: "en_US_POSIX")

        for w in workouts.sorted(by: { $0.dateStart < $1.dateStart }) {
            for ex in w.exercises.sorted(by: { $0.order < $1.order }) {
                for s in ex.sets.sorted(by: { $0.order < $1.order }) {
                    let fields: [String] = [
                        df.string(from: s.timestamp),
                        tf.string(from: s.timestamp),
                        escape(w.routineName ?? w.title),
                        escape(ex.exerciseName),
                        ex.equipment.rawValue,
                        trim(s.weight),
                        s.unit.rawValue,
                        s.reps.map(String.init) ?? "",
                        s.rpe.map(trim) ?? "",
                        s.rir.map(String.init) ?? "",
                        s.restSeconds.map(String.init) ?? "",
                    ]
                    lines.append(fields.joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC-4180-style quoting for fields containing commas/quotes/newlines.
    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: Markdown

    public static func markdown(_ workouts: [WorkoutRecord],
                                displayUnit: WeightUnit = .lb) -> String {
        var out = "# Workout Log\n"
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        df.locale = Locale(identifier: "en_US_POSIX")

        for w in workouts.sorted(by: { $0.dateStart > $1.dateStart }) {
            out += "\n## \(w.title) — \(df.string(from: w.dateStart))\n"
            if let routine = w.routineName { out += "_Routine: \(routine)_\n" }
            let vol = AnalyticsCalculator.sessionVolume(w, displayUnit: displayUnit)
            out += "_Volume: \(trim(vol)) \(displayUnit.rawValue) · Duration: \(formatDuration(w.duration))_\n"

            for ex in w.exercises.sorted(by: { $0.order < $1.order }) {
                out += "\n### \(ex.exerciseName) (\(ex.equipment.rawValue))\n"
                for s in ex.sets.sorted(by: { $0.order < $1.order }) {
                    var line = "- Set \(s.order + 1): \(trim(s.weight)) \(s.unit.rawValue)"
                    if let r = s.reps { line += " × \(r)" }
                    if let rpe = s.rpe { line += " @ RPE \(trim(rpe))" }
                    if let rir = s.rir { line += " (RIR \(rir))" }
                    if let rest = s.restSeconds { line += " — rest \(rest)s" }
                    out += line + "\n"
                }
            }
            if let notes = w.notes, !notes.isEmpty { out += "\n> \(notes)\n" }
        }
        return out
    }

    // MARK: Helpers

    static func trim(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
