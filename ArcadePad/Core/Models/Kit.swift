import Foundation

enum GridSize: Int, Codable, CaseIterable, Identifiable {
    case four = 4
    case eight = 8
    case twelve = 12
    case sixteen = 16

    var id: Int { rawValue }
    var label: String { "\(rawValue)" }

    /// Columns to use when laying out the grid, tuned per size for a square-ish arcade panel.
    var columns: Int {
        switch self {
        case .four: return 2
        case .eight: return 4
        case .twelve: return 4
        case .sixteen: return 4
        }
    }
}

/// A full saveable project: the pad grid, its samples, and its sequencer pattern.
struct Kit: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var gridSize: GridSize
    var pads: [Pad]
    var pattern: Pattern
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "New Kit",
        gridSize: GridSize = .eight,
        pads: [Pad]? = nil,
        pattern: Pattern = Pattern(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gridSize = gridSize
        self.pads = pads ?? (0..<gridSize.rawValue).map { Pad(index: $0, colorIndex: $0 % ArcadeTheme.padColors.count) }
        self.pattern = pattern
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func resizeGrid(to newSize: GridSize) {
        if newSize.rawValue > pads.count {
            let additional = (pads.count..<newSize.rawValue).map { Pad(index: $0, colorIndex: $0 % ArcadeTheme.padColors.count) }
            pads.append(contentsOf: additional)
        } else if newSize.rawValue < pads.count {
            pads = Array(pads.prefix(newSize.rawValue))
        }
        gridSize = newSize
        pattern.resize(to: pattern.stepCount)
    }
}
