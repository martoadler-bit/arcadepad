import Foundation

enum PlaybackMode: String, Codable, CaseIterable, Identifiable {
    case oneShot
    case loop
    case reverse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneShot: return "ONE-SHOT"
        case .loop: return "LOOP"
        case .reverse: return "REVERSE"
        }
    }
}

struct EffectSettings: Codable, Equatable {
    var filterCutoff: Double   // 0...1, 1 = fully open
    var delayMix: Double       // 0...1
    var reverbMix: Double      // 0...1
    var bitcrushAmount: Double // 0...1, 0 = off

    static let none = EffectSettings(filterCutoff: 1, delayMix: 0, reverbMix: 0, bitcrushAmount: 0)
}

/// One button in the arcade grid: a sample plus how it should be triggered and processed.
struct Pad: Identifiable, Codable, Equatable {
    let id: UUID
    var index: Int
    var sample: Sample?
    var mode: PlaybackMode
    var pitchSemitones: Double
    var volume: Double
    /// Pads sharing a non-nil choke group cut each other off when triggered (hi-hat-style choking).
    var chokeGroup: Int?
    var effects: EffectSettings
    var colorIndex: Int

    init(
        id: UUID = UUID(),
        index: Int,
        sample: Sample? = nil,
        mode: PlaybackMode = .oneShot,
        pitchSemitones: Double = 0,
        volume: Double = 1,
        chokeGroup: Int? = nil,
        effects: EffectSettings = .none,
        colorIndex: Int = 0
    ) {
        self.id = id
        self.index = index
        self.sample = sample
        self.mode = mode
        self.pitchSemitones = pitchSemitones
        self.volume = volume
        self.chokeGroup = chokeGroup
        self.effects = effects
        self.colorIndex = colorIndex
    }

    var isEmpty: Bool { sample == nil }
}
