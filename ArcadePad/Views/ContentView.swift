import SwiftUI

struct ContentView: View {
    @EnvironmentObject var kitStore: KitStore
    @ObservedObject private var audio = AudioEngine.shared

    @State private var activePads: Set<Int> = []
    @State private var recordingPadIndex: Int?
    @State private var editingPadIndex: Int?
    @State private var showSequencer = false
    @State private var showShareSheet = false

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
            mode: pad.mode,
            pitchSemitones: pad.pitchSemitones,
            volume: pad.volume,
            trimStart: sample.trimStart,
            trimEnd: sample.trimEnd
        )
        audio.applyEffects(pad.effects, toPad: pad.index)
        activePads.insert(pad.index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if pad.mode != .loop {
                activePads.remove(pad.index)
            }
        }
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
