import XCTest
@testable import StillAlive

final class PuzzleGeneratorTests: XCTestCase {
    func testSameSlotGivesSamePuzzle() {
        for difficulty in 1...3 {
            let first = PuzzleGenerator.puzzle(dayKey: "2026-10-01", slotIndex: 0, difficulty: difficulty)
            let second = PuzzleGenerator.puzzle(dayKey: "2026-10-01", slotIndex: 0, difficulty: difficulty)
            XCTAssertEqual(first, second)
        }
    }

    func testSeedIsStableAndSlotSpecific() {
        // Golden value guards against switching to a per-launch randomized hash.
        XCTAssertEqual(PuzzleGenerator.seed(dayKey: "2026-10-01", slotIndex: 0), PuzzleGenerator.seed(dayKey: "2026-10-01", slotIndex: 0))
        XCTAssertEqual(PuzzleGenerator.seed(dayKey: "", slotIndex: 0), fnv1a("#0"))
        XCTAssertNotEqual(PuzzleGenerator.seed(dayKey: "2026-10-01", slotIndex: 0), PuzzleGenerator.seed(dayKey: "2026-10-01", slotIndex: 1))
        XCTAssertNotEqual(PuzzleGenerator.seed(dayKey: "2026-10-01", slotIndex: 0), PuzzleGenerator.seed(dayKey: "2026-10-02", slotIndex: 0))
    }

    func testAnswersAreCorrectAndNonNegative() {
        for difficulty in 1...3 {
            for seed in UInt64(0)..<5_000 {
                let puzzle = PuzzleGenerator.puzzle(seed: seed &* 0x9E37_79B9, difficulty: difficulty)
                switch puzzle.kind {
                case .addition: XCTAssertEqual(puzzle.a + puzzle.b, puzzle.answer)
                case .subtraction: XCTAssertEqual(puzzle.a - puzzle.b, puzzle.answer)
                case .multiplication: XCTAssertEqual(puzzle.a * puzzle.b, puzzle.answer)
                case .missingNumber: XCTAssertEqual(puzzle.a + puzzle.answer, puzzle.b)
                }
                XCTAssertGreaterThanOrEqual(puzzle.a, 0)
                XCTAssertGreaterThanOrEqual(puzzle.b, 0)
                XCTAssertGreaterThanOrEqual(puzzle.answer, 0)
            }
        }
    }

    func testRangesStayGradeThree() {
        for seed in UInt64(0)..<5_000 {
            let puzzle = PuzzleGenerator.puzzle(seed: seed, difficulty: 3)
            switch puzzle.kind {
            case .addition: XCTAssertLessThan(puzzle.answer, 100)
            case .missingNumber: XCTAssertLessThan(puzzle.b, 100)
            case .subtraction: XCTAssertLessThan(puzzle.a, 100)
            case .multiplication: XCTAssertTrue((2...9).contains(puzzle.a))
            }
        }
    }

    func testEasyIsSmallerThanHard() {
        let easyMax = (UInt64(0)..<2_000).map { PuzzleGenerator.puzzle(seed: $0, difficulty: 1) }
            .filter { $0.kind == .addition }.map(\.answer).max() ?? 0
        XCTAssertLessThanOrEqual(easyMax, 20)
    }

    func testAllKindsAppear() {
        let kinds = Set((UInt64(0)..<200).map { PuzzleGenerator.puzzle(seed: $0, difficulty: 2).kind })
        XCTAssertEqual(kinds, Set(PuzzleKind.allCases))
    }

    func testDifficultyIsClamped() {
        XCTAssertEqual(PuzzleGenerator.puzzle(seed: 42, difficulty: 0), PuzzleGenerator.puzzle(seed: 42, difficulty: 1))
        XCTAssertEqual(PuzzleGenerator.puzzle(seed: 42, difficulty: 9), PuzzleGenerator.puzzle(seed: 42, difficulty: 3))
    }

    private func fnv1a(_ string: String) -> UInt64 {
        string.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}
