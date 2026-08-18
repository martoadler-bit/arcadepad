import SwiftUI

struct PadButtonView: View {
    let pad: Pad
    let isPlaying: Bool
    let onTrigger: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTrigger) {
            VStack(spacing: 4) {
                Text(labelText)
                    .font(ArcadeTheme.labelFont)
                    .foregroundStyle(.black.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(pad.index + 1)")
                    .font(ArcadeTheme.displayFont)
                    .foregroundStyle(.black.opacity(0.85))
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(pad.colorIndex), isActive: isPlaying))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress() }
        )
        .opacity(pad.isEmpty ? 0.35 : 1.0)
    }

    private var labelText: String {
        pad.sample?.name ?? "EMPTY"
    }
}
