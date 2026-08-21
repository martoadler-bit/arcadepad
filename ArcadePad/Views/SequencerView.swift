import SwiftUI

struct SequencerView: View {
    @EnvironmentObject var kitStore: KitStore
    @StateObject private var sequencer = SequencerEngine()
    let onStepTriggered: (Pad) -> Void

    @State private var exportLoopCount = 4
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transport
            exportRow

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

    private var exportRow: some View {
        HStack(spacing: 10) {
            Stepper("LOOPS: \(exportLoopCount)", value: $exportLoopCount, in: 1...16)
                .font(.caption2)
                .fixedSize()
                .onChange(of: exportLoopCount) { _, _ in exportedURL = nil }

            if isExporting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 90, height: 36)
            } else if let exportedURL {
                ShareLink(item: exportedURL) {
                    Text("SHARE ▸")
                        .font(ArcadeTheme.labelFont)
                        .frame(width: 90, height: 36)
                }
                .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(5)))
            } else {
                Button {
                    exportSequence()
                } label: {
                    Text("EXPORT")
                        .font(ArcadeTheme.labelFont)
                        .frame(width: 90, height: 36)
                }
                .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(6)))
            }

            if let exportError {
                Text(exportError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private func exportSequence() {
        exportError = nil
        exportedURL = nil
        isExporting = true
        let kit = kitStore.kit
        let store = kitStore
        let loops = exportLoopCount
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try SequencerExporter.export(kit: kit, kitStore: store, loopCount: loops)
                DispatchQueue.main.async {
                    isExporting = false
                    exportedURL = url
                }
            } catch {
                DispatchQueue.main.async {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private func stepRow(for pad: Pad) -> some View {
        let steps = kitStore.kit.pattern.steps(forPad: pad.index)
        return HStack(spacing: 4) {
            Image("ButtonUnpressed_\(ArcadeTheme.padColorName(pad.colorIndex))")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .opacity(pad.isEmpty ? 0.3 : 1)

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
