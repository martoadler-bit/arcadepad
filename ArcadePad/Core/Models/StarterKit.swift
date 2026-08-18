import Foundation

/// A bundled, ready-to-use kit definition. Installing one copies its audio out of the app
/// bundle into the user's own kit folder — from then on it behaves exactly like a kit the
/// user built themselves (editable, re-shareable, etc.).
struct StarterKit: Identifiable {
    struct PadDefinition {
        let name: String
        /// Resource name (without extension) and extension, resolved against the bundle.
        let resource: String
        let ext: String

        var bundleURL: URL? {
            Bundle.main.url(forResource: resource, withExtension: ext)
        }
    }

    let id: String
    let name: String
    let subtitle: String
    let gridSize: GridSize
    let pads: [PadDefinition]

    static let all: [StarterKit] = [
        StarterKit(
            id: "drum-kit",
            name: "Drum Kit",
            subtitle: "Kick, snare, hats, clap, tom, crash",
            gridSize: .eight,
            pads: [
                PadDefinition(name: "Kick", resource: "kick", ext: "mp3"),
                PadDefinition(name: "Kick Natural", resource: "kick_natural", ext: "mp3"),
                PadDefinition(name: "Snare", resource: "snare", ext: "mp3"),
                PadDefinition(name: "Clap", resource: "clap", ext: "mp3"),
                PadDefinition(name: "Hat Closed", resource: "hihat_closed", ext: "mp3"),
                PadDefinition(name: "Hat Open", resource: "hihat_open", ext: "mp3"),
                PadDefinition(name: "Tom", resource: "tom", ext: "mp3"),
                PadDefinition(name: "Crash", resource: "crash", ext: "mp3"),
            ]
        ),
        StarterKit(
            id: "konnakol-bols",
            name: "Konnakol Bols",
            subtitle: "Indian vocal percussion syllables",
            gridSize: .eight,
            pads: [
                PadDefinition(name: "Di", resource: "Di", ext: "wav"),
                PadDefinition(name: "Ka", resource: "Ka", ext: "wav"),
                PadDefinition(name: "Ki", resource: "Ki", ext: "wav"),
                PadDefinition(name: "Mi", resource: "Mi", ext: "wav"),
                PadDefinition(name: "Nam", resource: "Nam", ext: "wav"),
                PadDefinition(name: "Ta", resource: "Ta", ext: "wav"),
            ]
        ),
        StarterKit(
            id: "chiptune",
            name: "Chiptune",
            subtitle: "8-bit synth game sounds",
            gridSize: .eight,
            pads: [
                PadDefinition(name: "Coin", resource: "coin", ext: "wav"),
                PadDefinition(name: "Jump", resource: "jump", ext: "wav"),
                PadDefinition(name: "Laser", resource: "laser", ext: "wav"),
                PadDefinition(name: "Power-Up", resource: "powerup", ext: "wav"),
                PadDefinition(name: "Explosion", resource: "explosion", ext: "wav"),
                PadDefinition(name: "Hit", resource: "hit", ext: "wav"),
                PadDefinition(name: "Select", resource: "select", ext: "wav"),
                PadDefinition(name: "Game Over", resource: "gameover", ext: "wav"),
            ]
        ),
    ]
}
