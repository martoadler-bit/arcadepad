import Foundation

/// A single trigger inside a pattern's step grid.
struct Step: Codable, Equatable {
    var isActive: Bool
    var velocity: Double

    static let off = Step(isActive: false, velocity: 0.8)
}

/// A step-sequencer pattern: one row of steps per pad, all sharing a step count and tempo.
struct Pattern: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var stepCount: Int
    var tempoBPM: Double
    var swing: Double // 0...1, 0 = straight
    /// Keyed by pad index; each value has `stepCount` entries.
    var rows: [Int: [Step]]

    init(
        id: UUID = UUID(),
        name: String = "Pattern 1",
        stepCount: Int = 16,
        tempoBPM: Double = 120,
        swing: Double = 0,
        rows: [Int: [Step]] = [:]
    ) {
        self.id = id
        self.name = name
        self.stepCount = stepCount
        self.tempoBPM = tempoBPM
        self.swing = swing
        self.rows = rows
    }

    func steps(forPad padIndex: Int) -> [Step] {
        rows[padIndex] ?? Array(repeating: .off, count: stepCount)
    }

    mutating func toggleStep(padIndex: Int, step: Int) {
        var row = steps(forPad: padIndex)
        guard row.indices.contains(step) else { return }
        row[step].isActive.toggle()
        rows[padIndex] = row
    }

    mutating func resize(to newStepCount: Int) {
        for (pad, row) in rows {
            var resized = row
            if resized.count < newStepCount {
                resized.append(contentsOf: Array(repeating: .off, count: newStepCount - resized.count))
            } else if resized.count > newStepCount {
                resized = Array(resized.prefix(newStepCount))
            }
            rows[pad] = resized
        }
        stepCount = newStepCount
    }
}
