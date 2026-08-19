import SwiftUI

struct PadEditorView: View {
    let padIndex: Int
    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss
    @State private var peaks: [Float] = []
    @State private var isRerecording = false
    @State private var isPickingDuplicateTarget = false

    private var padBinding: Binding<Pad> {
        Binding(
            get: {
                kitStore.kit.pads.first(where: { $0.index == padIndex }) ?? Pad(index: padIndex)
            },
            set: { newValue in
                if let idx = kitStore.kit.pads.firstIndex(where: { $0.index == padIndex }) {
                    kitStore.kit.pads[idx] = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let sample = padBinding.wrappedValue.sample {
                            waveformSection(sample: sample)
                            modeSection
                            tuningSection
                            effectsSection
                            chokeSection
                            dangerZone(sample: sample)
                        } else {
                            emptyState
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Pad \(padIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isRerecording) {
            RecordView(padIndex: padIndex).environmentObject(kitStore)
        }
        .sheet(isPresented: $isPickingDuplicateTarget) {
            DuplicatePadTargetView(sourceIndex: padIndex) { destIndex in
                kitStore.duplicatePad(from: padIndex, to: destIndex)
                isPickingDuplicateTarget = false
            }
            .environmentObject(kitStore)
        }
        .onAppear(perform: loadWaveform)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("This pad is empty.")
                .foregroundStyle(.white.opacity(0.7))
            Button {
                isRerecording = true
            } label: {
                Text("RECORD SAMPLE")
                    .font(ArcadeTheme.displayFont)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(padIndex)))
        }
    }

    private func waveformSection(sample: Sample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("SAMPLE")
                Spacer()
                Button {
                    preview(sample: sample)
                } label: {
                    Label("PREVIEW", systemImage: "play.fill")
                        .font(ArcadeTheme.labelFont)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(padIndex)))
            }
            WaveformView(peaks: peaks, trimStart: padBinding.wrappedValue.sample?.trimStart ?? 0, trimEnd: padBinding.wrappedValue.sample?.trimEnd ?? 1, color: ArcadeTheme.padColor(padIndex))
                .frame(height: 90)

            HStack {
                Text("TRIM START").font(.caption2)
                Slider(value: trimStartBinding, in: 0...1)
            }
            HStack {
                Text("TRIM END").font(.caption2)
                Slider(value: trimEndBinding, in: 0...1)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PLAYBACK MODE")
            Picker("Mode", selection: modeBinding) {
                ForEach(PlaybackMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PITCH & VOLUME")
            labeledSlider("PITCH", value: padBinding.pitchSemitones, range: -12...12, format: "%.0f st")
            labeledSlider("VOLUME", value: padBinding.volume, range: 0...1.5, format: "%.0f%%", multiplier: 100)
        }
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("EFFECTS")
            labeledSlider("FILTER", value: padBinding.effects.filterCutoff, range: 0...1, format: "%.0f%%", multiplier: 100)
            labeledSlider("DELAY", value: padBinding.effects.delayMix, range: 0...1, format: "%.0f%%", multiplier: 100)
            labeledSlider("REVERB", value: padBinding.effects.reverbMix, range: 0...1, format: "%.0f%%", multiplier: 100)
            labeledSlider("BITCRUSH", value: padBinding.effects.bitcrushAmount, range: 0...1, format: "%.0f%%", multiplier: 100)
        }
        .onChange(of: padBinding.wrappedValue.effects) { _, newValue in
            AudioEngine.shared.applyEffects(newValue, toPad: padIndex)
        }
    }

    private var chokeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("CHOKE GROUP")
            Picker("Choke Group", selection: chokeGroupBinding) {
                Text("None").tag(-1)
                ForEach(0..<4) { g in
                    Text("Group \(g + 1)").tag(g)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func dangerZone(sample: Sample) -> some View {
        VStack(spacing: 12) {
            Button {
                isRerecording = true
            } label: {
                Text("RE-RECORD")
                    .font(ArcadeTheme.labelFont)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(2)))

            Button {
                isPickingDuplicateTarget = true
            } label: {
                Text("DUPLICATE TO...")
                    .font(ArcadeTheme.labelFont)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(4)))

            Button(role: .destructive) {
                clearPad(sample: sample)
            } label: {
                Text("CLEAR PAD")
                    .font(ArcadeTheme.labelFont)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcadeButtonStyle(color: .gray))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(ArcadeTheme.labelFont)
            .foregroundStyle(ArcadeTheme.marqueeText)
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, multiplier: Double = 1) -> some View {
        HStack {
            Text(label).font(.caption2).frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue * multiplier))
                .font(.caption2.monospacedDigit())
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: Bindings

    private var modeBinding: Binding<PlaybackMode> { padBinding.mode }

    private var trimStartBinding: Binding<Double> {
        Binding(
            get: { padBinding.wrappedValue.sample?.trimStart ?? 0 },
            set: { newValue in
                guard var sample = padBinding.wrappedValue.sample else { return }
                sample.trimStart = min(newValue, sample.trimEnd - 0.01)
                padBinding.wrappedValue.sample = sample
            }
        )
    }

    private var trimEndBinding: Binding<Double> {
        Binding(
            get: { padBinding.wrappedValue.sample?.trimEnd ?? 1 },
            set: { newValue in
                guard var sample = padBinding.wrappedValue.sample else { return }
                sample.trimEnd = max(newValue, sample.trimStart + 0.01)
                padBinding.wrappedValue.sample = sample
            }
        )
    }

    private var chokeGroupBinding: Binding<Int> {
        Binding(
            get: { padBinding.wrappedValue.chokeGroup ?? -1 },
            set: { newValue in
                padBinding.wrappedValue.chokeGroup = newValue == -1 ? nil : newValue
            }
        )
    }

    private func preview(sample: Sample) {
        let pad = padBinding.wrappedValue
        let url = kitStore.sampleURL(for: sample)
        AudioEngine.shared.applyEffects(pad.effects, toPad: padIndex)
        AudioEngine.shared.play(
            sample: url,
            padIndex: padIndex,
            mode: pad.mode,
            pitchSemitones: pad.pitchSemitones,
            volume: pad.volume,
            trimStart: sample.trimStart,
            trimEnd: sample.trimEnd
        )
    }

    private func clearPad(sample: Sample) {
        kitStore.deleteSampleFile(sample)
        padBinding.wrappedValue.sample = nil
        peaks = []
    }

    private func loadWaveform() {
        guard let sample = padBinding.wrappedValue.sample else { return }
        let url = kitStore.sampleURL(for: sample)
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = WaveformLoader.loadPeaks(url: url, sampleCount: 200)
            DispatchQueue.main.async {
                peaks = loaded
            }
        }
    }
}
