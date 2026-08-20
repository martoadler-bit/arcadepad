import SwiftUI

struct ContentView: View {
    @EnvironmentObject var kitStore: KitStore
    @ObservedObject private var audio = AudioEngine.shared

    @State private var activePads: Set<Int> = []
    @State private var recordingPadIndex: Int?
    @State private var editingPadIndex: Int?
    @State private var showSequencer = false
    @State private var showShareSheet = false
    @State private var showKitLibrary = false
    @State private var showRenamePrompt = false
    @State private var renameText = ""
    @State private var joystickDirection: JoystickDirection = .center
    @State private var joystickAssignment: JoystickAssignment = Self.lastAssignment

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    header

                    if showSequencer {
                        SequencerView(onStepTriggered: trigger)
                            .environmentObject(kitStore)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ScrollView {
                        PadGridView(
                            pads: kitStore.kit.pads,
                            columns: kitStore.kit.gridSize.columns,
                            activePadIndices: activePads,
                            onTrigger: trigger,
                            onLongPress: { pad in editingPadIndex = pad.index }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }

                    performanceJoystickBar
                }
            }
            .navigationTitle("ARCADEPAD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Grid Size", selection: gridSizeBinding) {
                            ForEach(GridSize.allCases) { size in
                                Text("\(size.label) PADS").tag(size)
                            }
                        }
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Share Kit", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            renameText = kitStore.kit.name
                            showRenamePrompt = true
                        } label: {
                            Label("Rename Kit", systemImage: "pencil")
                        }
                        Button {
                            showKitLibrary = true
                        } label: {
                            Label("My Kits", systemImage: "square.stack")
                        }
                    } label: {
                        Label("Grid", systemImage: "square.grid.3x3")
                    }
                }
            }
        }
        .sheet(item: recordingPadIndexItem) { wrapped in
            RecordView(padIndex: wrapped.value).environmentObject(kitStore)
        }
        .sheet(item: editingPadIndexItem) { wrapped in
            PadEditorView(padIndex: wrapped.value).environmentObject(kitStore)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareKitView().environmentObject(kitStore)
        }
        .sheet(isPresented: $showKitLibrary) {
            KitLibraryView().environmentObject(kitStore)
        }
        .alert("Rename kit", isPresented: $showRenamePrompt) {
            TextField("Kit name", text: $renameText)
            Button("Save") { kitStore.renameCurrentKit(to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text(kitStore.kit.name.uppercased())
                .font(.system(.title2, design: .monospaced).weight(.black))
                .foregroundStyle(ArcadeTheme.marqueeText)
                .shadow(color: ArcadeTheme.marqueeText.opacity(0.6), radius: 8)

            Spacer()

            Button {
                withAnimation { showSequencer.toggle() }
            } label: {
                Image(systemName: "square.grid.4x3.fill")
                    .foregroundStyle(showSequencer ? ArcadeTheme.marqueeText : .white.opacity(0.6))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func trigger(_ pad: Pad) {
        guard let sample = pad.sample else {
            recordingPadIndex = pad.index
            return
        }
        if let group = pad.chokeGroup {
            audio.choke(group: group, exceptPadIndex: pad.index, pads: kitStore.kit.pads)
        }
        let url = kitStore.sampleURL(for: sample)
        audio.play(
            sample: url,
            padIndex: pad.index,
            mode: performanceMode(for: pad),
            pitchSemitones: pad.pitchSemitones + performancePitchOffset,
            volume: pad.volume,
            trimStart: sample.trimStart,
            trimEnd: sample.trimEnd
        )
        audio.applyEffects(performanceEffects(for: pad), toPad: pad.index)
        activePads.insert(pad.index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if pad.mode != .loop {
                activePads.remove(pad.index)
            }
        }
    }

    // MARK: Performance joystick

    private static let lastAssignmentKey = "ContentView.lastJoystickAssignment"

    private static var lastAssignment: JoystickAssignment {
        UserDefaults.standard.string(forKey: lastAssignmentKey)
            .flatMap(JoystickAssignment.init(rawValue:)) ?? .none
    }

    private var performanceJoystickBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                JoystickView { direction in
                    joystickDirection = direction
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("PERFORMANCE").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    Text(statusText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(joystickDirection == .center ? .white.opacity(0.4) : ArcadeTheme.marqueeText)
                        .animation(.easeOut(duration: 0.1), value: joystickDirection)
                }

                Spacer()
            }

            // A native segmented Picker — the same reliably-tappable control already used
            // for the record-source and pad-mode pickers elsewhere in the app — instead of
            // custom Buttons in a scroll/grid, which turned out not to register taps.
            Picker("Assignment", selection: $joystickAssignment) {
                ForEach(JoystickAssignment.allCases) { assignment in
                    Text(assignment.rawValue).tag(assignment)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .onChange(of: joystickAssignment) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.lastAssignmentKey)
        }
    }

    private var statusText: String {
        guard joystickAssignment != .none else { return "Pick a parameter above to arm the joystick." }
        guard joystickDirection != .center else { return "Hold a direction while you tap a pad." }
        switch joystickAssignment {
        case .none:
            return ""
        case .filter:
            let open = joystickDirection == .up || joystickDirection == .right
            return open ? "FILTER → wide open" : "FILTER → muffled"
        case .reverb:
            let wet = joystickDirection == .up || joystickDirection == .right
            return wet ? "REVERB → full wash" : "REVERB → dry"
        case .delay:
            let wet = joystickDirection == .up || joystickDirection == .right
            return wet ? "DELAY → full echo" : "DELAY → dry"
        case .pitchBend:
            let up = joystickDirection == .up || joystickDirection == .right
            return up ? "PITCH → +7 semitones" : "PITCH → −7 semitones"
        case .reverse:
            return "REVERSE → next hit plays backwards"
        }
    }

    /// Only "reverse" overrides the pad's own playback mode — the others layer a live effects
    /// tweak on top without changing how the sample itself is triggered.
    private func performanceMode(for pad: Pad) -> PlaybackMode {
        guard joystickAssignment == .reverse, joystickDirection != .center else { return pad.mode }
        return .reverse
    }

    private var performancePitchOffset: Double {
        guard joystickAssignment == .pitchBend else { return 0 }
        switch joystickDirection {
        case .up, .right: return 7
        case .down, .left: return -7
        case .center: return 0
        }
    }

    private func performanceEffects(for pad: Pad) -> EffectSettings {
        var effects = pad.effects
        guard joystickDirection != .center else { return effects }
        let boosted = (joystickDirection == .up || joystickDirection == .right)
        switch joystickAssignment {
        case .filter:
            effects.filterCutoff = boosted ? 1.0 : 0.05
        case .reverb:
            effects.reverbMix = boosted ? 1.0 : 0.0
        case .delay:
            effects.delayMix = boosted ? 1.0 : 0.0
        case .none, .pitchBend, .reverse:
            break
        }
        return effects
    }

    private var gridSizeBinding: Binding<GridSize> {
        Binding(
            get: { kitStore.kit.gridSize },
            set: { kitStore.kit.resizeGrid(to: $0) }
        )
    }

    private var recordingPadIndexItem: Binding<IdentifiedInt?> {
        Binding(
            get: { recordingPadIndex.map(IdentifiedInt.init) },
            set: { recordingPadIndex = $0?.value }
        )
    }

    private var editingPadIndexItem: Binding<IdentifiedInt?> {
        Binding(
            get: { editingPadIndex.map(IdentifiedInt.init) },
            set: { editingPadIndex = $0?.value }
        )
    }
}

/// Sheets need an `Identifiable` item; this wraps a bare pad index without adding a
/// global `Int: Identifiable` conformance.
private struct IdentifiedInt: Identifiable {
    let value: Int
    var id: Int { value }
}
