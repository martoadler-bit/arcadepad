import SwiftUI

/// Shared arcade-cabinet visual language: chunky beveled buttons, saturated neon colors,
/// dark cabinet background.
enum ArcadeTheme {
    static let cabinetBackground = Color(red: 0.07, green: 0.06, blue: 0.10)
    static let panelBackground = Color(red: 0.12, green: 0.11, blue: 0.16)
    static let marqueeText = Color(red: 1.0, green: 0.08, blue: 0.42)

    static let padColors: [Color] = [
        Color(red: 1.00, green: 0.20, blue: 0.20), // red
        Color(red: 1.00, green: 0.55, blue: 0.05), // orange
        Color(red: 1.00, green: 0.85, blue: 0.05), // yellow
        Color(red: 0.15, green: 0.85, blue: 0.35), // green
        Color(red: 0.10, green: 0.75, blue: 0.95), // cyan
        Color(red: 0.75, green: 0.25, blue: 1.00), // purple
    ]

    static func padColor(_ index: Int) -> Color {
        padColors[index % padColors.count]
    }

    static let displayFont = Font.system(.headline, design: .monospaced).weight(.heavy)
    static let labelFont = Font.system(.caption, design: .monospaced).weight(.bold)
}

/// A chunky physical-arcade-button look: beveled top, glowing when pressed/active.
struct ArcadeButtonStyle: ButtonStyle {
    var color: Color
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: pressed
                                ? [color.opacity(0.9), color.opacity(0.6)]
                                : [color, color.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.55), lineWidth: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(pressed ? 0.15 : 0.45), lineWidth: 1.5)
                    .blendMode(.overlay)
            )
            .shadow(color: color.opacity(pressed ? 0.9 : 0.0), radius: pressed ? 14 : 0)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .offset(y: pressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}
