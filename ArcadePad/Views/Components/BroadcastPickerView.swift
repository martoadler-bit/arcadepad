import SwiftUI
import ReplayKit

/// Wraps the system's own broadcast picker button — the only way to start a broadcast
/// (screen + system audio) is through this exact control; apps can't trigger it in code.
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = "com.dlrk.arcadepad.broadcast"
        picker.showsMicrophoneButton = false
        // The system glyph renders using tintColor — against our dark cabinet background it's
        // otherwise invisible (defaults to near-black).
        picker.tintColor = .white
        // TEMP DEBUG: bright background so we can tell "view exists but icon is invisible"
        // apart from "view has zero size" while diagnosing why the button isn't showing.
        picker.backgroundColor = .systemRed
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
