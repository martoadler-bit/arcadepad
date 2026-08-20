import Foundation

/// The 5 physical positions of a digital arcade joystick (on/off microswitches per axis,
/// no analog in-between — matches the reference hardware this UI is modeled on).
enum JoystickDirection {
    case center, up, down, left, right
}

/// What the joystick performs while deflected. Applied at the moment a pad is triggered
/// (like holding a performance-FX modifier key), not continuously to already-sounding pads —
/// AVAudioEngine can't smoothly rewind a buffer that's already streaming, so "reverse" in
/// particular only makes sense at trigger time.
enum JoystickAssignment: String, CaseIterable, Identifiable, Codable {
    case none = "OFF"
    case filter = "FILTER"
    case reverb = "REVERB"
    case delay = "DELAY"
    case pitchBend = "PITCH BEND"
    case reverse = "REVERSE"

    var id: String { rawValue }
}
