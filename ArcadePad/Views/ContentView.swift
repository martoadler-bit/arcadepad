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
    @State private var joystickUpFX: JoystickFX = Self.lastFX(.up)
    @State private var joystickDownFX: JoystickFX = Self.lastFX(.down)
    @State private var joystickLeftFX: JoystickFX = Self.lastFX(.left)
    @State private var joystickRightFX: JoystickFX = Self.lastFX(.right)

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
        var mode = pad.mode
        var pitchOffset: Double = 0
        var effects = pad.effects
        currentJoystickFX.apply(effects: &effects, mode: &mode, pitchOffset: &pitchOffset)

        let url = kitStore.sampleURL(for: sample)
        audio.play(
            sample: url,
            padIndex: pad.index,
            mode: mode,
            pitchSemitones: pad.pitchSemitones + pitchOffset,
            volume: pad.volume,
            trimStart: sample.trimStart,
            trimEnd: sample.trimEnd
        )
        audio.applyEffects(effects, toPad: pad.index)
        activePads.insert(pad.index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if pad.mode != .loop {
                activePads.remove(pad.index)
            }
        }
    }

    // MARK: Performance joystick

    private static func fxKey(_ direction: JoystickDirection) -> String {
        "ContentView.joystickFX.\(direction)"
    }

    private static func lastFX(_ direction: JoystickDirection) -> JoystickFX {
        UserDefaults.standard.string(forKey: fxKey(direction))
            .flatMap(JoystickFX.init(rawValue:)) ?? .none
    }

    private var currentJoystickFX: JoystickFX {
        switch joystickDirection {
        case .center: return .none
        case .up: return joystickUpFX
        case .down: return joystickDownFX
        case .left: return joystickLeftFX
        case .right: return joystickRightFX
        }
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

            // Each direction gets its own independent, fixed FX — 4 native menu Pickers
            // (same reliable UIKit-backed control as the segmented ones used elsewhere).
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    fxPicker("▲ UP", $joystickUpFX, .up)
                    fxPicker("▼ DOWN", $joystickDownFX, .down)
                }
                HStack(spacing: 6) {
                    fxPicker("◀ LEFT", $joystickLeftFX, .left)
                    fxPicker("▶ RIGHT", $joystickRightFX, .right)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func fxPicker(_ label: String, _ selection: Binding<JoystickFX>, _ direction: JoystickDirection) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 4)
            Picker(label, selection: selection) {
                ForEach(JoystickFX.allCases) { fx in
                    Text(fx.rawValue).tag(fx)
                }
            }
            .pickerStyle(.menu)
            .tint(selection.wrappedValue == .none ? .white.opacity(0.6) : ArcadeTheme.marqueeText)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(ArcadeTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: selection.wrappedValue) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.fxKey(direction))
        }
    }

    private var statusText: String {
        guard joystickDirection != .center else { return "Hold a direction to trigger its FX." }
        return currentJoystickFX == .none ? "No FX assigned to this direction." : "→ \(currentJoystickFX.rawValue)"
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
