import SwiftUI

/// Slices one long recording across several pads. Each segment keeps the full source audio
/// file but plays back a different trim window — the same trim mechanism used elsewhere for a
/// single sample, just applied across N pad copies of the same recording.
struct SplitAudioView: View {
    let sourceURL: URL
    let sourceDuration: TimeInterval
    let baseName: String
    var onComplete: () -> Void = {}

    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss

    @State private var peaks: [Float] = []
    @State private var mode: SplitMode = .equal
    @State private var segments: [Segment] = []
    @State private var errorMessage: String?
    @State private var isDetecting = false

    enum SplitMode: String, CaseIterable, Identifiable {
        case equal = "EQUAL"
        case smart = "SMART"
        case manual = "MANUAL"
        var id: String { rawValue }
    }

    struct Segment: Identifiable {
        let id = UUID()
        var start: Double
        var end: Double
        var padIndex: Int?
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        WaveformView(peaks: peaks, trimStart: 0, trimEnd: 1, color: ArcadeTheme.padColor(2))
                            .frame(height: 90)

                        Picker("Mode", selection: $mode) {
                            ForEach(SplitMode.allCases) { m in Text(m.rawValue).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, _ in applyModeChange() }

                        if mode == .smart {
                            HStack(spacing: 8) {
                                Text(isDetecting ? "Detecting transients…" : "Cuts placed at the loudest onsets — hits, words, notes.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Button {
                                    detectAndApply()
                                } label: {
                                    Label("RE-DETECT", systemImage: "waveform.badge.magnifyingglass")
                                        .font(.caption)
                                }
                                .disabled(isDetecting)
                            }
                        }

                        VStack(spacing: 10) {
                            ForEach($segments) { $segment in
                                segmentRow(segment: $segment)
                            }
                        }

                        HStack {
                            Button {
                                addSegment()
                            } label: {
                                Label("ADD SEGMENT", systemImage: "plus")
                                    .font(ArcadeTheme.labelFont)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(4)))
                            .disabled(segments.count >= kitStore.kit.gridSize.rawValue)

                            if segments.count > 2 {
                                Button(role: .destructive) {
                                    segments.removeLast()
                                    onSegmentCountChanged()
                                } label: {
                                    Label("REMOVE", systemImage: "minus")
                                        .font(ArcadeTheme.labelFont)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(ArcadeButtonStyle(color: .gray))
                            }
                        }

                        if !canApply {
                            Text("Give each segment its own pad.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(.red)
                        }

                        Button {
                            apply()
                        } label: {
                            Text("SPLIT ACROSS \(segments.count) PADS")
                                .font(ArcadeTheme.displayFont)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(3)))
                        .disabled(!canApply)
                    }
                    .padding()
                }
            }
            .navigationTitle("Split Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadWaveform()
            if segments.isEmpty {
                let emptyIndices = kitStore.kit.pads.filter(\.isEmpty).map(\.index).sorted()
                segments = [
                    Segment(start: 0, end: 0.5, padIndex: emptyIndices.first),
                    Segment(start: 0.5, end: 1, padIndex: emptyIndices.count > 1 ? emptyIndices[1] : nil),
                ]
            }
        }
    }

    private var canApply: Bool {
        let padIndices = segments.compactMap(\.padIndex)
        return !isDetecting && segments.count >= 2 && padIndices.count == segments.count && Set(padIndices).count == segments.count
    }

    private func segmentRow(segment: Binding<Segment>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: "%.1fs – %.1fs", segment.wrappedValue.start * sourceDuration, segment.wrappedValue.end * sourceDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Picker("Pad", selection: Binding(
                    get: { segment.wrappedValue.padIndex ?? -1 },
                    set: { segment.wrappedValue.padIndex = $0 == -1 ? nil : $0 }
                )) {
                    Text("Choose Pad").tag(-1)
                    ForEach(0..<kitStore.kit.gridSize.rawValue, id: \.self) { i in
                        Text("Pad \(i + 1)").tag(i)
                    }
                }
                .pickerStyle(.menu)
                .tint(ArcadeTheme.marqueeText)
            }
            if mode == .manual {
                HStack(spacing: 8) {
                    Text("START").font(.caption2).frame(width: 44, alignment: .leading)
                    Slider(value: Binding(
                        get: { segment.wrappedValue.start },
                        set: { segment.wrappedValue.start = min($0, segment.wrappedValue.end - 0.01) }
                    ), in: 0...1)
                }
                HStack(spacing: 8) {
                    Text("END").font(.caption2).frame(width: 44, alignment: .leading)
                    Slider(value: Binding(
                        get: { segment.wrappedValue.end },
                        set: { segment.wrappedValue.end = max($0, segment.wrappedValue.start + 0.01) }
                    ), in: 0...1)
                }
            }
        }
        .padding(10)
        .background(ArcadeTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func addSegment() {
        guard segments.count < kitStore.kit.gridSize.rawValue else { return }
        let usedPads = Set(segments.compactMap(\.padIndex))
        let nextPad = kitStore.kit.pads
            .filter { $0.isEmpty && !usedPads.contains($0.index) }
            .map(\.index)
            .sorted()
            .first
        segments.append(Segment(start: 0, end: 1, padIndex: nextPad))
        onSegmentCountChanged()
    }

    private func applyModeChange() {
        switch mode {
        case .equal: recomputeEqualIfNeeded()
        case .smart: detectAndApply()
        case .manual: break
        }
    }

    private func onSegmentCountChanged() {
        switch mode {
        case .equal: recomputeEqualIfNeeded()
        case .smart: detectAndApply()
        case .manual: break
        }
    }

    private func recomputeEqualIfNeeded() {
        guard !segments.isEmpty else { return }
        let n = segments.count
        for i in segments.indices {
            segments[i].start = Double(i) / Double(n)
            segments[i].end = Double(i + 1) / Double(n)
        }
    }

    private func detectAndApply() {
        guard !segments.isEmpty else { return }
        isDetecting = true
        let count = segments.count
        let url = sourceURL
        DispatchQueue.global(qos: .userInitiated).async {
            let onsets = TransientDetector.detectTransients(url: url, maxCount: count - 1)
            DispatchQueue.main.async {
                applyBoundaries(onsets)
                isDetecting = false
            }
        }
    }

    private func applyBoundaries(_ onsets: [Double]) {
        let bounds = ([0.0] + onsets + [1.0]).sorted()
        guard bounds.count >= segments.count + 1 else {
            // Not enough distinct transients found for the requested segment count — fall
            // back to an even split rather than leaving segments with stale/overlapping bounds.
            recomputeEqualIfNeeded()
            return
        }
        for i in segments.indices {
            segments[i].start = bounds[i]
            segments[i].end = bounds[i + 1]
        }
    }

    private func apply() {
        errorMessage = nil
        for (i, segment) in segments.enumerated() {
            guard let padIndex = segment.padIndex else { continue }
            do {
                try kitStore.assignSplitSegment(
                    from: sourceURL,
                    name: "\(baseName) \(i + 1)",
                    duration: sourceDuration,
                    trimStart: segment.start,
                    trimEnd: segment.end,
                    toPadIndex: padIndex
                )
            } catch {
                errorMessage = "Couldn't split audio: \(error.localizedDescription)"
                return
            }
        }
        dismiss()
        onComplete()
    }

    private func loadWaveform() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = WaveformLoader.loadPeaks(url: sourceURL, sampleCount: 200)
            DispatchQueue.main.async { peaks = loaded }
        }
    }
}
