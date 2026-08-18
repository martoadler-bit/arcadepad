import Foundation
import Combine

/// Drives step playback on a high-precision timer. Not sample-accurate (that would need an
/// AVAudioEngine render-callback clock), but tight enough for a step sequencer at pad-jam tempos.
final class SequencerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentStep = 0

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.dlrk.arcadepad.sequencer", qos: .userInteractive)

    var onStep: ((Int) -> Void)?

    func play(pattern: Pattern) {
        stop()
        isPlaying = true
        currentStep = 0

        let secondsPerStep = 60.0 / pattern.tempoBPM / 4.0 // 16th notes
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: secondsPerStep)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let step = self.currentStep
            let swungDelay = (step % 2 == 1) ? pattern.swing * secondsPerStep * 0.5 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + swungDelay) {
                self.onStep?(step)
            }
            self.currentStep = (step + 1) % pattern.stepCount
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isPlaying = false
        currentStep = 0
    }

    func updateTempo(_ pattern: Pattern) {
        guard isPlaying else { return }
        play(pattern: pattern)
    }
}
