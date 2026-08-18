import SwiftUI

struct PadGridView: View {
    let pads: [Pad]
    let columns: Int
    let activePadIndices: Set<Int>
    let onTrigger: (Pad) -> Void
    let onLongPress: (Pad) -> Void

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(pads) { pad in
                PadButtonView(
                    pad: pad,
                    isPlaying: activePadIndices.contains(pad.index),
                    onTrigger: { onTrigger(pad) },
                    onLongPress: { onLongPress(pad) }
                )
            }
        }
    }
}
