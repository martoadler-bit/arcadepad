import SwiftUI

struct WaveformView: View {
    let peaks: [Float]
    var trimStart: Double = 0
    var trimEnd: Double = 1
    var color: Color = ArcadeTheme.marqueeText

    var body: some View {
        // Drawn with Canvas (not an HStack of bars) so the whole waveform always fits exactly
        // inside the given width, however long the recording is — an HStack's inter-bar spacing
        // was pushing the tail end of long waveforms past the right edge of the screen.
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let slotWidth = size.width / CGFloat(peaks.count)
            let barWidth = max(1.0, slotWidth - 1)

            for (index, peak) in peaks.enumerated() {
                let position = Double(index) / Double(max(peaks.count - 1, 1))
                let inTrim = position >= trimStart && position <= trimEnd
                let barHeight = max(2, CGFloat(peak) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * slotWidth,
                    y: (size.height - barHeight) / 2,
                    width: barWidth,
                    height: barHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: 1)
                context.fill(path, with: .color(inTrim ? color : color.opacity(0.25)))
            }
        }
    }
}
