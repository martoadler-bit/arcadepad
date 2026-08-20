import SwiftUI

/// A digital arcade joystick built directly from the 5 reference photos — one full image per
/// position (center/up/down/left/right), swapped outright rather than animated by moving a
/// separate ball sprite. Only 5 discrete positions exist (matching real arcade microswitches),
/// no analog range. Direction follows wherever your finger currently IS relative to the
/// joystick's own center, not the delta since touch-down.
struct JoystickView: View {
    var onDirectionChange: (JoystickDirection) -> Void

    @State private var direction: JoystickDirection = .center

    private let size: CGFloat = 96
    private let threshold: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .position(center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateDirection(for: CGPoint(x: value.location.x - center.x, y: value.location.y - center.y))
                        }
                        .onEnded { _ in
                            direction = .center
                            onDirectionChange(.center)
                        }
                )
        }
        .frame(width: size + 40, height: size + 40)
    }

    private var imageName: String {
        switch direction {
        case .center: return "JoystickCenter"
        case .up: return "JoystickUp"
        case .down: return "JoystickDown"
        case .left: return "JoystickLeft"
        case .right: return "JoystickRight"
        }
    }

    private func updateDirection(for offsetFromCenter: CGPoint) {
        let dx = offsetFromCenter.x
        let dy = offsetFromCenter.y
        let newDirection: JoystickDirection
        if max(abs(dx), abs(dy)) < threshold {
            newDirection = .center
        } else if abs(dx) > abs(dy) {
            newDirection = dx > 0 ? .right : .left
        } else {
            newDirection = dy > 0 ? .down : .up
        }
        if newDirection != direction {
            direction = newDirection
            onDirectionChange(newDirection)
        }
    }
}

extension JoystickDirection: Equatable {}
