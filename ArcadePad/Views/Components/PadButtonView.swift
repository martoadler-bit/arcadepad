import SwiftUI

struct PadButtonView: View {
    let pad: Pad
    let isPlaying: Bool
    let onTrigger: () -> Void
    let onLongPress: () -> Void

    @EnvironmentObject var kitStore: KitStore
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onTrigger) {
                Color.clear
                    .frame(minWidth: 76, minHeight: 76)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PadImageButtonStyle(colorName: ArcadeTheme.padColorName(pad.colorIndex), isActive: isPlaying))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress() }
            )
            .opacity(pad.isEmpty ? 0.35 : 1.0)

            Button {
                renameText = pad.customLabel ?? ""
                isRenaming = true
            } label: {
                Text(pad.displayLabel)
                    .font(ArcadeTheme.labelFont)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .alert("Rename pad", isPresented: $isRenaming) {
            TextField("Pad \(pad.index + 1)", text: $renameText)
            Button("Save") { save() }
            Button("Use Number", role: .destructive) {
                renameText = ""
                save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save() {
        guard let idx = kitStore.kit.pads.firstIndex(where: { $0.index == pad.index }) else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        kitStore.kit.pads[idx].customLabel = trimmed.isEmpty ? nil : trimmed
    }
}
