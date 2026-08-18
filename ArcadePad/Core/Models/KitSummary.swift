import Foundation

/// Lightweight listing entry for the kit library — avoids decoding every pad/sample just to
/// show a row of "name, pad count, last edited".
struct KitSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let gridSize: GridSize
    let filledPadCount: Int
    let updatedAt: Date
}
