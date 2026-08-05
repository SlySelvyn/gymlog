import XCTest
@testable import GymLogCore

final class NormalizerTests: XCTestCase {

    func n(_ s: String) -> String { NumberNormalizer.normalize(s) }

    // MARK: Plate-math compounds (spec §7.4b)

    func testPlateMathCompounds() {
        XCTAssertEqual(n("two twenty five"), "225")
        XCTAssertEqual(n("two-twenty-five"), "225")
        XCTAssertEqual(n("one thirty five"), "135")
        XCTAssertEqual(n("two fifteen"), "215")
        XCTAssertEqual(n("one oh five"), "105")
        XCTAssertEqual(n("three fifteen"), "315")
        XCTAssertEqual(n("four oh five"), "405")
        XCTAssertEqual(n("two twenty"), "220")
    }

    // MARK: Standard numbers

    func testStandardNumbers() {
        XCTAssertEqual(n("one hundred thirty five"), "135")
        XCTAssertEqual(n("one hundred and thirty five"), "135")
        XCTAssertEqual(n("a hundred and five"), "105")
        XCTAssertEqual(n("two hundred"), "200")
        XCTAssertEqual(n("ninety five"), "95")
        XCTAssertEqual(n("twelve"), "12")
        XCTAssertEqual(n("five"), "5")
    }

    // MARK: Decimals / halves (RPE)

    func testDecimals() {
        XCTAssertEqual(n("eight point five"), "8.5")
        XCTAssertEqual(n("eight and a half"), "8.5")
        XCTAssertEqual(n("rpe eight and a half"), "rpe 8.5")
        XCTAssertEqual(n("r-p-e eight"), "rpe 8")
        XCTAssertEqual(n("r p e nine"), "rpe 9")
    }

    // MARK: Keyword canonicalization

    func testKeywords() {
        XCTAssertEqual(n("135 pounds"), "135 lb")
        XCTAssertEqual(n("60 kilos"), "60 kg")
        XCTAssertEqual(n("five rep"), "5 reps")
        XCTAssertEqual(n("reps in reserve two"), "rir 2")
        XCTAssertEqual(n("225 times 5"), "225 x 5")
        XCTAssertEqual(n("225 by 5"), "225 x 5")
    }

    // MARK: Filler stripping

    func testFiller() {
        XCTAssertEqual(n("um squat uh two twenty five okay for five"), "squat 225 for 5")
    }

    // MARK: Adjacent numbers stay separate

    func testSeparateNumbers() {
        // "two twenty five five" = 225 then 5 (weight then reps, name omitted)
        XCTAssertEqual(n("two twenty five five"), "225 5")
        // literal digits pass through
        XCTAssertEqual(n("225 for 5"), "225 for 5")
        XCTAssertEqual(n("8.5"), "8.5")
    }

    // MARK: Full phrases

    func testFullPhrases() {
        XCTAssertEqual(n("Squat two-twenty-five for five"), "squat 225 for 5")
        XCTAssertEqual(n("Bench press, five reps, 135 pounds, R-P-E eight"),
                       "bench press 5 reps 135 lb rpe 8")
        XCTAssertEqual(n("Lat pulldown, one-forty for ten, RIR two"),
                       "lat pulldown 140 for 10 rir 2")
    }
}
