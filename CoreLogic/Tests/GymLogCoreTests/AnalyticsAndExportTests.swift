import XCTest
@testable import GymLogCore

final class AnalyticsAndExportTests: XCTestCase {

    // Fixture: two workouts, one 3 days ago, one 40 days ago.
    func fixture(reference: Date) -> [WorkoutRecord] {
        let cal = Calendar.current
        let d3 = cal.date(byAdding: .day, value: -3, to: reference)!
        let d40 = cal.date(byAdding: .day, value: -40, to: reference)!

        let recent = WorkoutRecord(
            title: "Push Day", routineName: "Push",
            dateStart: d3, dateEnd: d3.addingTimeInterval(3600),
            exercises: [
                ExerciseSessionRecord(order: 0, exerciseName: "Bench Press", equipment: .barbell, sets: [
                    SetRecord(order: 0, weight: 135, unit: .lb, reps: 10, timestamp: d3, restSeconds: 90),
                    SetRecord(order: 1, weight: 185, unit: .lb, reps: 5, rpe: 8, timestamp: d3.addingTimeInterval(180)),
                ]),
                ExerciseSessionRecord(order: 1, exerciseName: "Overhead Press", equipment: .barbell, sets: [
                    SetRecord(order: 0, weight: 95, unit: .lb, reps: 8, timestamp: d3.addingTimeInterval(600)),
                ]),
            ])

        let old = WorkoutRecord(
            title: "Old Session",
            dateStart: d40, dateEnd: d40.addingTimeInterval(1800),
            exercises: [
                ExerciseSessionRecord(order: 0, exerciseName: "Bench Press", equipment: .barbell, sets: [
                    SetRecord(order: 0, weight: 80, unit: .kg, reps: 5, timestamp: d40),
                ]),
            ])
        return [recent, old]
    }

    // MARK: §12 volume

    func testSetAndSessionVolume() {
        let ref = Date()
        let all = fixture(reference: ref)
        // 135×10 + 185×5 + 95×8 = 1350 + 925 + 760 = 3035
        XCTAssertEqual(AnalyticsCalculator.sessionVolume(all[0], displayUnit: .lb), 3035, accuracy: 0.01)
    }

    func testUnitConversionInVolume() {
        let s = SetRecord(order: 0, weight: 100, unit: .kg, reps: 1)
        XCTAssertEqual(AnalyticsCalculator.setVolume(s, displayUnit: .lb), 220.46, accuracy: 0.01)
        XCTAssertEqual(AnalyticsCalculator.setVolume(s, displayUnit: .kg), 100, accuracy: 0.001)
    }

    // MARK: §12 period boundaries

    func testWeekPeriodExcludesOldWorkout() {
        let ref = Date()
        let all = fixture(reference: ref)
        let week = AnalyticsCalculator.summary(all, period: .week, displayUnit: .lb, reference: ref)
        XCTAssertEqual(week.workoutsCount, 1)
        XCTAssertEqual(week.setsCount, 3)
        XCTAssertEqual(week.totalVolume, 3035, accuracy: 0.01)

        let year = AnalyticsCalculator.summary(all, period: .year, displayUnit: .lb, reference: ref)
        XCTAssertEqual(year.workoutsCount, 2)
    }

    // MARK: §12 Epley e1RM

    func testEpley() {
        XCTAssertEqual(AnalyticsCalculator.epley1RM(weight: 225, reps: 5), 262.5, accuracy: 0.01)
        XCTAssertEqual(AnalyticsCalculator.epley1RM(weight: 315, reps: 1), 315)   // 1 rep = actual
        XCTAssertEqual(AnalyticsCalculator.epley1RM(weight: 100, reps: 0), 0)
    }

    func testE1RMSeriesUsesBestSetPerWorkout() {
        let ref = Date()
        let all = fixture(reference: ref)
        let series = AnalyticsCalculator.e1RMSeries(of: "Bench Press", in: all, displayUnit: .lb)
        XCTAssertEqual(series.count, 2)                       // both workouts have bench
        // recent workout best: max(135×(1+10/30)=180, 185×(1+5/30)≈215.83) = 215.83
        XCTAssertEqual(series.last!.e1RM, 215.83, accuracy: 0.01)
        XCTAssertLessThan(series.first!.date, series.last!.date) // chronological
    }

    // MARK: §12 frequency / top set

    func testFrequencyAndTopSet() {
        let all = fixture(reference: Date())
        XCTAssertEqual(AnalyticsCalculator.frequency(of: "Bench Press", in: all), 2)
        XCTAssertEqual(AnalyticsCalculator.frequency(of: "Overhead Press", in: all), 1)
        let top = AnalyticsCalculator.topSet(of: "Bench Press", in: all[0], displayUnit: .lb)
        XCTAssertEqual(top?.weight, 185)                      // max weight wins
    }

    // MARK: §15 CSV

    func testCSV() {
        let all = fixture(reference: Date())
        let csv = ExportService.csv(all)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, Substring(ExportService.csvHeader))
        XCTAssertEqual(lines.count, 1 + 4)                    // header + 4 sets total
        XCTAssertTrue(csv.contains("Bench Press"))
        XCTAssertTrue(csv.contains(",lb,"))
        XCTAssertTrue(csv.contains(",kg,"))
        XCTAssertTrue(csv.contains(",8,"))                    // rpe 8 present
    }

    func testCSVEscaping() {
        XCTAssertEqual(ExportService.escape("Squat, Front"), "\"Squat, Front\"")
        XCTAssertEqual(ExportService.escape("plain"), "plain")
    }

    // MARK: §15 Markdown

    func testMarkdown() {
        let all = fixture(reference: Date())
        let md = ExportService.markdown(all)
        XCTAssertTrue(md.hasPrefix("# Workout Log"))
        XCTAssertTrue(md.contains("## Push Day"))
        XCTAssertTrue(md.contains("### Bench Press (barbell)"))
        XCTAssertTrue(md.contains("- Set 2: 185 lb × 5 @ RPE 8"))
        XCTAssertTrue(md.contains("rest 90s"))
    }

    // MARK: Duration fallback

    func testDurationFallsBackToLastSet() {
        var w = fixture(reference: Date())[0]
        w.dateEnd = nil
        XCTAssertEqual(w.duration, 600, accuracy: 1)          // last set at +600s
    }
}
