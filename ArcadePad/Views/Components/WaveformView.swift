import SwiftUI

struct WaveformView: View {
    let peaks: [Float]
    var trimStart: Double = 0
    var trimEnd: Double = 1
    var color: Color = ArcadeTheme.marqueeText

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let barWidth = max(1.0, width / CGFloat(max(peaks.count, 1)))

            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1) {
                    ForEach(Array(peaks.enumerated()), id: \.offset) { index, peak in
                        let inTrim = Double(index) / Double(max(peaks.count - 1, 1)) >= trimStart
                            && Double(index) / Double(max(peaks.count - 1, 1)) <= trimEnd
                        RoundedRectangle(cornerRadius: 1)
                            .fill(inTrim ? color : color.opacity(0.25))
                            .frame(width: barWidth, height: max(2, CGFloat(peak) * height))
                    }
                }
                .frame(height: height)
            }
        }
    }
}
