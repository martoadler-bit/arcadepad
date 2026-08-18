import SwiftUI

struct SequencerView: View {
    @EnvironmentObject var kitStore: KitStore
    @StateObject private var sequencer = SequencerEngine()
    let onStepTriggered: (Pad) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transport

            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(kitStore.kit.pads) { pad in
                        stepRow(for: pad)
                    }
                }
            }
        }
        .onAppear { sequencer.onStep = handleStep }
        .onDisappear { sequencer.stop() }
    }

    private var transport: some View {
        HStack(spacing: 16) {
            Button {
                if sequencer.isPlaying {
                    sequencer.stop()
                } else {
                    sequencer.play(pattern: kitStore.kit.pattern)
                }
            } label: {
                Text(sequencer.isPlaying ? "■ STOP" : "▶ PLAY")
                    .font(ArcadeTheme.displayFont)
                    .frame(width: 110, height: 44)
            }
            .buttonStyle(ArcadeButtonStyle(color: sequencer.isPlaying ? .red : ArcadeTheme.padColor(3), isActive: sequencer.isPlaying))

            VStack(alignment: .leading) {
                Text("TEMPO \(Int(kitStore.kit.pattern.tempoBPM)) BPM").font(.caption2)
                Slider(
                    value: Binding(
                        get: { kitStore.kit.pattern.tempoBPM },
                        set: { kitStore.kit.pattern.tempoBPM = $0; sequencer.updateTempo(kitStore.kit.pattern) }
                    ),
                    in: 60...200
                )
            }

            VStack(alignment: .leading) {
                Text("SWING \(Int(kitStore.kit.pattern.swing * 100))%").font(.caption2)
                Slider(value: $kitStore.kit.pattern.swing, in: 0...1)
            }
        }
    }

    private func stepRow(for pad: Pad) -> some View {
        let steps = kitStore.kit.pattern.steps(forPad: pad.index)
        return HStack(spacing: 4) {
            Text(pad.sample?.name ?? "Pad \(pad.index + 1)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .leading)
                .lineLimit(1)

            ForEach(Array(steps.enumerated()), id: \.offset) { stepIndex, step in
                Button {
                    kitStore.kit.pattern.toggleStep(padIndex: pad.index, step: stepIndex)
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(step.isActive ? ArcadeTheme.padColor(pad.colorIndex) : Color.white.opacity(0.08))
                        .frame(height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(sequencer.currentStep == stepIndex && sequencer.isPlaying ? Color.white : .clear, lineWidth: 2)
                        )
                }
                .disabled(pad.isEmpty)
            }
        }
    }

    private func handleStep(_ step: Int) {
        for pad in kitStore.kit.pads {
            let steps = kitStore.kit.pattern.steps(forPad: pad.index)
            guard step < steps.count, steps[step].isActive, !pad.isEmpty else { continue }
            onStepTriggered(pad)
        }
    }
}
