import Foundation

/// Groups starter kits in the library UI. Purely presentational — installing a kit works
/// the same regardless of category.
enum StarterKitCategory: String, CaseIterable {
    case musical = "MUSICAL"
    case percussion = "PERCUSSION"
    case streamer = "STREAMER"

    var order: Int {
        switch self {
        case .musical: return 0
        case .percussion: return 1
        case .streamer: return 2
        }
    }
}

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
    let category: StarterKitCategory
    let gridSize: GridSize
    let pads: [PadDefinition]

    static let all: [StarterKit] = [
        StarterKit(
            id: "drum-kit",
            name: "Drum Kit",
            subtitle: "Kick, snare, hats, clap, tom, crash",
            category: .percussion,
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
            id: "808-drums",
            name: "808 Drums",
            subtitle: "Synthesized trap-style kick, snare, hats, clap",
            category: .percussion,
            gridSize: .eight,
            pads: [
                PadDefinition(name: "Kick", resource: "kick", ext: "wav"),
                PadDefinition(name: "Snare", resource: "snare", ext: "wav"),
                PadDefinition(name: "Hat Closed", resource: "hihat_closed", ext: "wav"),
                PadDefinition(name: "Hat Open", resource: "hihat_open", ext: "wav"),
                PadDefinition(name: "Clap", resource: "clap", ext: "wav"),
                PadDefinition(name: "Rim", resource: "rim", ext: "wav"),
                PadDefinition(name: "Tom", resource: "tom", ext: "wav"),
                PadDefinition(name: "Perc", resource: "perc", ext: "wav"),
            ]
        ),
        StarterKit(
            id: "hand-drums",
            name: "Hand Drums",
            subtitle: "Conga, bongo and shaker-style percussion",
            category: .percussion,
            gridSize: .eight,
            pads: [
                PadDefinition(name: "Conga Low", resource: "conga_low", ext: "wav"),
                PadDefinition(name: "Conga Mid", resource: "conga_mid", ext: "wav"),
                PadDefinition(name: "Conga High", resource: "conga_high", ext: "wav"),
                PadDefinition(name: "Slap", resource: "slap", ext: "wav"),
                PadDefinition(name: "Tom Low", resource: "tom_low", ext: "wav"),
                PadDefinition(name: "Tom High", resource: "tom_high", ext: "wav"),
                PadDefinition(name: "Shaker", resource: "shaker", ext: "wav"),
                PadDefinition(name: "Click", resource: "click", ext: "wav"),
            ]
        ),
        StarterKit(
            id: "konnakol-bols",
            name: "Konnakol Bols",
            subtitle: "Indian vocal percussion syllables",
            category: .percussion,
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
            category: .musical,
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
        StarterKit(
            id: "synth-bass",
            name: "Synth Bass",
            subtitle: "Plucky one-shot bass notes across an octave",
            category: .musical,
            gridSize: .eight,
            pads: [
                PadDefinition(name: "C2", resource: "bass_c2", ext: "wav"),
                PadDefinition(name: "D2", resource: "bass_d2", ext: "wav"),
                PadDefinition(name: "Eb2", resource: "bass_eb2", ext: "wav"),
                PadDefinition(name: "F2", resource: "bass_f2", ext: "wav"),
                PadDefinition(name: "G2", resource: "bass_g2", ext: "wav"),
                PadDefinition(name: "Ab2", resource: "bass_ab2", ext: "wav"),
                PadDefinition(name: "Bb2", resource: "bass_bb2", ext: "wav"),
                PadDefinition(name: "C3", resource: "bass_c3", ext: "wav"),
            ]
        ),
        StarterKit(
            id: "arp-bells",
            name: "Arp Bells",
            subtitle: "Bell tones tuned to a pentatonic scale",
            category: .musical,
            gridSize: .eight,
            pads: [
                PadDefinition(name: "C5", resource: "bell_c5", ext: "wav"),
                PadDefinition(name: "D5", resource: "bell_d5", ext: "wav"),
                PadDefinition(name: "F5", resource: "bell_f5", ext: "wav"),
                PadDefinition(name: "G5", resource: "bell_g5", ext: "wav"),
                PadDefinition(name: "A5", resource: "bell_a5", ext: "wav"),
                PadDefinition(name: "C6", resource: "bell_c6", ext: "wav"),
                PadDefinition(name: "D6", resource: "bell_d6", ext: "wav"),
                PadDefinition(name: "F6", resource: "bell_f6", ext: "wav"),
            ]
        ),
        StarterKit(
            id: "streamer-fx",
            name: "Streamer FX",
            subtitle: "Airhorn, buzzer, drumroll, applause and more",
            category: .streamer,
            gridSize: .eight,
            pads: [
                PadDefinition(name: "Airhorn", resource: "airhorn", ext: "mp3"),
                PadDefinition(name: "Duck Quack", resource: "duck_quack", ext: "mp3"),
                PadDefinition(name: "Sad Trombone", resource: "sad_trombone", ext: "mp3"),
                PadDefinition(name: "Drumroll", resource: "drumroll", ext: "mp3"),
                PadDefinition(name: "Applause", resource: "applause", ext: "mp3"),
                PadDefinition(name: "Success", resource: "success_chime", ext: "mp3"),
                PadDefinition(name: "Buzzer", resource: "buzzer", ext: "mp3"),
                PadDefinition(name: "Scratch", resource: "record_scratch", ext: "mp3"),
            ]
        ),
    ]
}
