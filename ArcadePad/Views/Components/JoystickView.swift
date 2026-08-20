import SwiftUI

/// A digital arcade joystick — base socket + ball knob, built from the reference photos.
/// Only 5 discrete positions exist (matching real arcade microswitches), no analog range:
/// direction follows wherever your finger currently IS relative to the joystick's own center
/// (not the delta since touch-down — that read as "drifting" the moment you didn't press
/// exactly on the knob), and releasing snaps back to center.
struct JoystickView: View {
    var onDirectionChange: (JoystickDirection) -> Void

    @State private var direction: JoystickDirection = .center

    private let baseSize: CGFloat = 84
    private let knobSize: CGFloat = 60
    private let throwDistance: CGFloat = 22
    private let threshold: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Image("JoystickBase")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: baseSize, height: baseSize)
                    .position(center)

                Image("JoystickKnob")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: knobSize, height: knobSize)
                    .position(x: center.x + knobOffset.width, y: center.y + knobOffset.height)
                    .animation(.spring(response: 0.18, dampingFraction: 0.6), value: direction)
            }
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
        .frame(width: baseSize + 40, height: baseSize + 40)
    }

    private var knobOffset: CGSize {
        switch direction {
        case .center: return .zero
        case .up: return CGSize(width: 0, height: -throwDistance)
        case .down: return CGSize(width: 0, height: throwDistance)
        case .left: return CGSize(width: -throwDistance, height: 0)
        case .right: return CGSize(width: throwDistance, height: 0)
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
