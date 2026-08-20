import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Multiplies brightness (HSB) by `factor`, keeping hue/saturation — used to derive the
    /// lit/shadowed gradient stops of the arcade dome material from a single base color.
    func shaded(_ factor: CGFloat) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s), brightness: min(1, max(0, b * factor)), opacity: a)
    }
}

/// Shared arcade-cabinet visual language: chunky beveled buttons, saturated neon colors,
/// dark cabinet background.
enum ArcadeTheme {
    static let cabinetBackground = Color(red: 0.07, green: 0.06, blue: 0.10)
    static let panelBackground = Color(red: 0.12, green: 0.11, blue: 0.16)
    static let marqueeText = Color(red: 1.0, green: 0.08, blue: 0.42)

    static let padColors: [Color] = [
        Color(hex: 0xFF2B2B), // red
        Color(hex: 0xFF7A00), // orange
        Color(hex: 0xFFB800), // amber
        Color(hex: 0xFFE600), // yellow
        Color(hex: 0x9DFF00), // lime
        Color(hex: 0x18D94E), // green
        Color(hex: 0x00BFA5), // emerald
        Color(hex: 0x00D9FF), // cyan
        Color(hex: 0x1677FF), // blue
        Color(hex: 0x304FFE), // indigo
        Color(hex: 0x7B2CFF), // violet
        Color(hex: 0xB026FF), // purple
        Color(hex: 0xFF1FB4), // magenta
        Color(hex: 0xFF4F8B), // pink
        Color(hex: 0xFF5C5C), // coral
        Color(hex: 0x00AFC1), // teal
    ]

    /// Names matching the `Button{Unpressed,Pressed}_<Name>` asset pairs generated from the
    /// reference photos, in the same order as `padColors`.
    static let padColorNames: [String] = [
        "Red", "Orange", "Amber", "Yellow", "Lime", "Green", "Emerald", "Cyan",
        "Blue", "Indigo", "Violet", "Purple", "Magenta", "Pink", "Coral", "Teal",
    ]

    static func padColor(_ index: Int) -> Color {
        padColors[index % padColors.count]
    }

    static func padColorName(_ index: Int) -> String {
        padColorNames[index % padColorNames.count]
    }

    static let displayFont = Font.system(.headline, design: .monospaced).weight(.heavy)
    static let labelFont = Font.system(.caption, design: .monospaced).weight(.bold)
}

/// Pad button look built from the two reference photos (glossy red arcade button, unpressed
/// and pressed) instead of a procedural gradient — swaps images on press/active state.
struct PadImageButtonStyle: ButtonStyle {
    var colorName: String = "Red"
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        configuration.label
            .background(
                Image(pressed ? "ButtonPressed_\(colorName)" : "ButtonUnpressed_\(colorName)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.07), value: pressed)
    }
}

/// A premium, physical arcade-button look: a wide, low, glossy plastic dome — not a sphere,
/// not a flat gradient circle. No bezel/ring/base; the dome is the whole button, isolated
/// on the dark cabinet background. Pressing it flattens the dome geometrically rather than
/// just darkening it, mirroring a real arcade switch.
struct ArcadeButtonStyle: ButtonStyle {
    enum Shape {
        case roundedRect(CGFloat)
        case circle
    }

    var color: Color
    var isActive: Bool = false
    var shape: Shape = .roundedRect(14)

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        return configuration.label
            .background(dome(pressed: pressed))
            .shadow(color: .black.opacity(pressed ? 0.25 : 0.45), radius: pressed ? 3 : 8, y: pressed ? 2 : 6)
            .scaleEffect(x: 1.0, y: pressed ? 0.90 : 1.0, anchor: .center)
            .scaleEffect(pressed ? 0.97 : 1.0)
            .offset(y: pressed ? 3 : 0)
            .animation(.easeOut(duration: 0.07), value: pressed)
    }

    @ViewBuilder
    private func dome(pressed: Bool) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            // Rim (glossy skirt) occupies the outer ~16% of the radius; a thin dark groove
            // separates it from the inner face, which itself recedes further when pressed.
            let rimThickness = size * 0.16
            let grooveThickness = size * 0.035
            let faceInset = pressed ? rimThickness + grooveThickness + size * 0.035 : rimThickness + grooveThickness
            let lightCenter = pressed ? UnitPoint(x: 0.42, y: 0.44) : UnitPoint(x: 0.32, y: 0.26)

            ZStack {
                // Outer glossy rim/skirt — same color family, lit from top-left, its own sheen.
                shapeView()
                    .fill(
                        LinearGradient(
                            colors: [color.shaded(1.35), color.shaded(0.95), color.shaded(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Rim highlight arc, upper-left, following the skirt's curve.
                Circle()
                    .trim(from: 0.58, to: 0.92)
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: rimThickness * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .blur(radius: rimThickness * 0.25)
                    .padding(rimThickness * 0.35)
                    .clipShape(shapeView())

                // Dark groove where the rim meets the inner face.
                shapeView()
                    .fill(Color.black.opacity(0.92))
                    .padding(rimThickness)

                // Inner face — convex dome when unpressed, recessed bowl when pressed.
                shapeView()
                    .fill(
                        RadialGradient(
                            stops: pressed
                                ? [
                                    .init(color: color.shaded(0.75), location: 0.0),
                                    .init(color: color.shaded(0.95), location: 0.55),
                                    .init(color: color.shaded(1.15), location: 0.85),
                                    .init(color: color.shaded(0.9), location: 1.0),
                                ]
                                : [
                                    .init(color: color.shaded(1.4), location: 0.0),
                                    .init(color: color.shaded(1.1), location: 0.45),
                                    .init(color: color.shaded(0.85), location: 0.8),
                                    .init(color: color.shaded(0.6), location: 1.0),
                                ],
                            center: lightCenter,
                            startRadius: 0,
                            endRadius: size * 0.55
                        )
                    )
                    .padding(faceInset)

                // Shadow crescent cast by the rim into the bowl when pressed.
                if pressed {
                    Ellipse()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: size * 0.7, height: size * 0.28)
                        .blur(radius: size * 0.05)
                        .offset(y: -size * 0.28)
                        .clipShape(shapeView())
                }

                // Main specular highlight on the inner face.
                Ellipse()
                    .fill(Color.white.opacity(pressed ? 0.22 : 0.55))
                    .frame(width: size * 0.32, height: size * 0.18)
                    .blur(radius: size * 0.045)
                    .offset(x: pressed ? -size * 0.06 : -size * 0.11, y: pressed ? -size * 0.02 : -size * 0.12)
                    .clipShape(shapeView())

                // Subtle secondary reflection, lower-right.
                Ellipse()
                    .fill(Color.white.opacity(pressed ? 0.05 : 0.10))
                    .frame(width: size * 0.24, height: size * 0.13)
                    .blur(radius: size * 0.04)
                    .offset(x: size * 0.09, y: pressed ? size * 0.08 : size * 0.11)
                    .clipShape(shapeView())
            }
            .clipShape(shapeView())
        }
    }

    private func shapeView() -> AnyShape {
        switch shape {
        case .roundedRect(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .circle:
            AnyShape(Circle())
        }
    }
}
