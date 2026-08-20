import Foundation

/// The 5 physical positions of a digital arcade joystick (on/off microswitches per axis,
/// no analog in-between — matches the reference hardware this UI is modeled on).
enum JoystickDirection {
    case center, up, down, left, right
}

/// A fixed, self-contained performance effect a joystick direction can trigger. Each direction
/// (up/down/left/right) gets its own independent assignment — pushing that direction while
/// tapping a pad applies exactly this effect to that hit, nothing relative or direction-paired
/// about it (unlike the earlier single shared "assignment + polarity" design).
enum JoystickFX: String, CaseIterable, Identifiable, Codable {
    case none = "OFF"
    case filterOpen = "FILTER OPEN"
    case filterClosed = "FILTER CLOSED"
    case reverbWash = "REVERB"
    case delayThrow = "DELAY"
    case pitchUp = "PITCH UP"
    case pitchDown = "PITCH DOWN"
    case reverse = "REVERSE"
    case bitcrush = "BITCRUSH"

    var id: String { rawValue }

    /// Short enough for all 9 to fit in one segmented control; `rawValue` (the full name) is
    /// used anywhere there's room for it, like the "→ FILTER OPEN" status line.
    var shortLabel: String {
        switch self {
        case .none: return "OFF"
        case .filterOpen: return "OPEN"
        case .filterClosed: return "CLOSE"
        case .reverbWash: return "VERB"
        case .delayThrow: return "DLY"
        case .pitchUp: return "P.UP"
        case .pitchDown: return "P.DN"
        case .reverse: return "REV"
        case .bitcrush: return "CRSH"
        }
    }

    /// Applies this fixed effect on top of a pad's own settings — only touches the parameters
    /// it cares about, leaving everything else at the pad's stored values.
    func apply(effects: inout EffectSettings, mode: inout PlaybackMode, pitchOffset: inout Double) {
        switch self {
        case .none:
            break
        case .filterOpen:
            effects.filterCutoff = 1.0
        case .filterClosed:
            effects.filterCutoff = 0.05
        case .reverbWash:
            effects.reverbMix = 1.0
        case .delayThrow:
            effects.delayMix = 1.0
        case .pitchUp:
            pitchOffset = 7
        case .pitchDown:
            pitchOffset = -7
        case .reverse:
            mode = .reverse
        case .bitcrush:
            effects.bitcrushAmount = 1.0
        }
    }
}
