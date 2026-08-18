import Foundation

/// Public, web-playable snapshot of a Kit: local `fileName`s are replaced with public
/// Storage download URLs, and empty pads are dropped entirely.
struct SharedKitManifest: Codable {
    struct SharedPad: Codable {
        let index: Int
        let name: String
        let mode: PlaybackMode
        let pitchSemitones: Double
        let volume: Double
        let trimStart: Double
        let trimEnd: Double
        let colorIndex: Int
        let audioURL: String
    }

    let id: String
    let name: String
    let gridSize: Int
    let pads: [SharedPad]
    let createdAt: Date
}
