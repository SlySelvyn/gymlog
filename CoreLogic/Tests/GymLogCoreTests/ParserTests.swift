import XCTest
@testable import GymLogCore

final class ParserTests: XCTestCase {

    let parser = SetParser()

    // Convenience: parse and unwrap a valid result or fail.
    @discardableResult
    func expectValid(_ phrase: String,
                     current: String? = nil,
                     prefs: ParserPrefs = ParserPrefs(),
                     file: StaticString = #filePath, line: UInt = #line) -> (SetDraft, ExerciseMatch)? {
        let r = parser.parse(phrase, currentExerciseName: current, prefs: prefs)
        guard case .valid(let d, let m, _) = r else {
            XCTFail("Expected valid parse for \"\(phrase)\", got \(r)", file: file, line: line)
            return nil
        }
        return (d, m)
    }

    func expectInvalid(_ phrase: String, current: String? = nil,
                       file: StaticString = #filePath, line: UInt = #line) -> ParseProblem? {
        let r = parser.parse(phrase, currentExerciseName: current)
        guard case .invalid(let p, _) = r else {
            XCTFail("Expected invalid parse for \"\(phrase)\", got \(r)", file: file, line: line)
            return nil
        }
        return p
    }

    func matchedName(_ m: ExerciseMatch) -> String? {
        if case .matched(let ex) = m { return ex.name }
        return nil
    }

    // MARK: - Spec §7.8 accepted examples

    func testSpecExample1_squatPlateMath() {
        guard let (d, m) = expectValid("Squat two-twenty-five for five") else { return }
        XCTAssertEqual(matchedName(m), "Back Squat")
        XCTAssertEqual(d.weight, 225)
        XCTAssertEqual(d.reps, 5)
        XCTAssertEqual(d.unit, .lb)
    }

    func testSpecExample2_benchRepsFirst() {
        guard let (d, m) = expectValid("Bench press, five reps, 135 pounds, R-P-E eight") else { return }
        XCTAssertEqual(matchedName(m), "Bench Press")
        XCTAssertEqual(d.weight, 135)
        XCTAssertEqual(d.reps, 5)
        XCTAssertEqual(d.rpe, 8)
    }

    func testSpecExample3_hammerCurls() {
        guard let (d, m) = expectValid("Hammer curls, thirty-five pounds, twelve") else { return }
        XCTAssertEqual(matchedName(m), "Hammer Curl")
        XCTAssertEqual(d.weight, 35)
        XCTAssertEqual(d.reps, 12)
    }

    func testSpecExample4_inheritCurrentExercise() {
        guard let (d, m) = expectValid("Two-twenty-five, five", current: "Back Squat") else { return }
        XCTAssertEqual(m, .inherit)
        XCTAssertEqual(d.weight, 225)
        XCTAssertEqual(d.reps, 5)
    }

    func testSpecExample5_latPulldownRIR() {
        guard let (d, m) = expectValid("Lat pulldown, one-forty for ten, RIR two") else { return }
        XCTAssertEqual(matchedName(m), "Lat Pulldown")
        XCTAssertEqual(d.weight, 140)
        XCTAssertEqual(d.reps, 10)
        XCTAssertEqual(d.rir, 2)
    }

    // MARK: - US-3 order independence

    func testOrderPermutations() {
        let phrases = [
            "225 for 5 RPE 8",
            "5 reps at 225 pounds RPE 8",
            "RPE 8, five reps, two-twenty-five",
            "at rpe 8 two twenty five for five",
        ]
        for p in phrases {
            guard let (d, _) = expectValid(p, current: "Back Squat") else { continue }
            XCTAssertEqual(d.weight, 225, "phrase: \(p)")
            XCTAssertEqual(d.reps, 5, "phrase: \(p)")
            XCTAssertEqual(d.rpe, 8, "phrase: \(p)")
        }
    }

    // MARK: - Unlabeled-number heuristics

    func testTwoUnlabeled_bigNumberIsWeight() {
        guard let (d, _) = expectValid("squat 5 225") else { return }
        XCTAssertEqual(d.weight, 225)   // >50 rule wins over spoken order
        XCTAssertEqual(d.reps, 5)
    }

    func testTwoUnlabeled_bothSmallIsAmbiguous() {
        let p = expectInvalid("curls 12 15")
        if case .ambiguousNumbers = p {} else { XCTFail("expected ambiguousNumbers, got \(String(describing: p))") }
    }

    func testKgUnit() {
        guard let (d, _) = expectValid("deadlift 100 kilos for 3") else { return }
        XCTAssertEqual(d.weight, 100)
        XCTAssertEqual(d.unit, .kg)
        XCTAssertEqual(d.reps, 3)
    }

    func testDefaultUnitFromPrefs() {
        guard let (d, _) = expectValid("bench 60 for 8", prefs: ParserPrefs(defaultUnit: .kg)) else { return }
        XCTAssertEqual(d.unit, .kg)
    }

    // MARK: - Bodyweight movements

    func testBodyweightRepsOnly() {
        guard let (d, m) = expectValid("pull ups twelve") else { return }
        XCTAssertEqual(matchedName(m), "Pull Up")
        XCTAssertEqual(d.reps, 12)
        XCTAssertEqual(d.weight, 0)     // bodyweight → weight 0 with warning
    }

    // MARK: - RPE half steps

    func testRPEHalfStep() {
        guard let (d, _) = expectValid("bench 135 for 5 rpe eight and a half") else { return }
        XCTAssertEqual(d.rpe, 8.5)
    }

    func testInvalidRPE() {
        let p = expectInvalid("bench 135 for 5 rpe 14")
        XCTAssertEqual(p, .invalidRPE(14))
    }

    // MARK: - Fuzzy / alias resolution

    func testAliases() {
        XCTAssertEqual(matchedName(parserMatch("bench 135 for 5")), "Bench Press")
        XCTAssertEqual(matchedName(parserMatch("rdl 185 for 8")), "Romanian Deadlift")
        XCTAssertEqual(matchedName(parserMatch("pulldown 140 for 10")), "Lat Pulldown")
        XCTAssertEqual(matchedName(parserMatch("ohp 95 for 5")), "Overhead Press")
    }

    func testFuzzyNearMiss() {
        // slight mis-hearing: "lat pull down" (extra split) should still match
        XCTAssertEqual(matchedName(parserMatch("lat pull down 140 for 10")), "Lat Pulldown")
    }

    func testUnresolvedOffersSuggestions() {
        let r = parser.parse("zercher squat 185 for 5")
        guard case .valid(_, .unresolved(let spoken, let suggestions), _) = r else {
            XCTFail("expected unresolved with suggestions, got \(r)"); return
        }
        XCTAssertEqual(spoken, "zercher squat")
        XCTAssertFalse(suggestions.isEmpty)
    }

    func parserMatch(_ p: String) -> ExerciseMatch {
        if case .valid(_, let m, _) = parser.parse(p) { return m }
        return .missing
    }

    // MARK: - Failure & edge cases

    func testNoExerciseAndNoCurrent() {
        XCTAssertEqual(expectInvalid("225 for 5"), .noExerciseContext)
    }

    func testEmptyUtterance() {
        XCTAssertEqual(expectInvalid("  "), .emptyUtterance)
    }

    func testNoNumbers() {
        XCTAssertEqual(expectInvalid("back squat", current: "Back Squat"), .noNumbersFound)
    }

    func testMissingRepsPolicy() {
        // default: reject
        XCTAssertEqual(expectInvalid("squat two twenty five"), .missingReps)
        // [OPEN E] permissive policy: allow weight-only draft with warning
        let r = parser.parse("squat two twenty five",
                             prefs: ParserPrefs(allowWeightOnlyDraft: true))
        guard case .valid(let d, _, let warnings) = r else {
            XCTFail("expected valid weight-only draft, got \(r)"); return
        }
        XCTAssertEqual(d.weight, 225)
        XCTAssertNil(d.reps)
        XCTAssertTrue(warnings.contains(.missingReps))
    }

    // MARK: - Same-name re-speak should still match current exercise (§7.6)

    func testSameExerciseRenamed() {
        guard let (_, m) = expectValid("squat 225 for 5", current: "Back Squat") else { return }
        XCTAssertEqual(matchedName(m), "Back Squat")
    }
}
