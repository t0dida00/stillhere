import Foundation

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Modulo-based so results are stable across Swift versions (unlike `Int.random(in:using:)`).
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}

enum PuzzleKind: CaseIterable {
    case addition, subtraction, multiplication, missingNumber
}

struct Puzzle: Equatable {
    var kind: PuzzleKind
    var a: Int
    var b: Int
    var answer: Int

    var question: String {
        switch kind {
        case .addition: "\(a) + \(b) = ?"
        case .subtraction: "\(a) − \(b) = ?"
        case .multiplication: "\(a) × \(b) = ?"
        case .missingNumber: "\(a) + ? = \(b)"
        }
    }
}

enum PuzzleGenerator {
    /// FNV-1a over "dayKey#slotIndex". Swift's `Hasher` is randomized per launch, so it can't be used here.
    static func seed(dayKey: String, slotIndex: Int) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(dayKey)#\(slotIndex)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func puzzle(dayKey: String, slotIndex: Int, difficulty: Int) -> Puzzle {
        puzzle(seed: seed(dayKey: dayKey, slotIndex: slotIndex), difficulty: difficulty)
    }

    static func puzzle(seed: UInt64, difficulty: Int) -> Puzzle {
        var rng = SplitMix64(seed: seed)
        let level = min(max(difficulty, 1), 3)
        let maxSum = [20, 50, 99][level - 1]
        let kind = PuzzleKind.allCases[rng.int(in: 0...PuzzleKind.allCases.count - 1)]

        switch kind {
        case .addition:
            let a = rng.int(in: 1...maxSum - 1)
            let b = rng.int(in: 1...maxSum - a)
            return Puzzle(kind: kind, a: a, b: b, answer: a + b)
        case .subtraction:
            let a = rng.int(in: 2...maxSum)
            let b = rng.int(in: 1...a - 1)
            return Puzzle(kind: kind, a: a, b: b, answer: a - b)
        case .multiplication:
            let a = rng.int(in: 2...[5, 9, 9][level - 1])
            let b = rng.int(in: [1, 2, 2][level - 1]...[5, 9, 10][level - 1])
            return Puzzle(kind: kind, a: a, b: b, answer: a * b)
        case .missingNumber:
            let a = rng.int(in: 1...maxSum - 1)
            let missing = rng.int(in: 1...maxSum - a)
            return Puzzle(kind: kind, a: a, b: a + missing, answer: missing)
        }
    }
}
