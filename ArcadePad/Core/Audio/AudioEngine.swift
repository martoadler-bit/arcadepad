import AVFoundation
import Combine

enum RecordingSource: String, CaseIterable, Identifiable {
    case microphone
    case lineOrUSB
    case systemAudio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .microphone: return "MICROPHONE"
        case .lineOrUSB: return "LINE / USB"
        case .systemAudio: return "SYSTEM AUDIO"
        }
    }

    /// System audio needs a Broadcast Upload Extension to actually capture other apps' output
    /// — that isn't built yet, so selecting it today would just silently record the mic under
    /// a misleading label. Disabled until the extension exists.
    var isAvailable: Bool {
        self != .systemAudio
    }
}

/// Owns the shared AVAudioEngine graph: one player node + effects chain per pad, plus the
/// recording tap used to sample new sounds. Line/USB input is handled transparently by
/// AVAudioSession routing (a class-compliant interface just becomes the active input);
/// system audio capture needs a Broadcast Upload Extension and is not wired up yet.
final class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var padChains: [Int: PadChain] = [:]

    @Published var inputLevel: Float = 0
    @Published var isRecording = false
    @Published var currentInputRouteName: String = "—"
    @Published var availableInputs: [AVAudioSessionPortDescription] = []

    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?

    private struct PadChain {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed
        let eq: AVAudioUnitEQ
        let bitcrush: AVAudioUnitDistortion
        let delay: AVAudioUnitDelay
        let reverb: AVAudioUnitReverb
    }

    /// Matches the largest grid size (GridSize.sixteen); chains are pre-built once at init
    /// rather than lazily, since attaching/connecting nodes to an already-running engine
    /// caused AVAudioPlayerNode to throw on start.
    private static let maxPads = 16

    private init() {
        configureSession()
        observeRouteChanges()
        observeInterruptions()
        buildAllPadChains()
    }

    // MARK: Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            refreshAvailableInputs()
        } catch {
            print("ArcadePad: failed to configure audio session: \(error)")
        }
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAvailableInputs()
        }
    }

    /// A phone call, Siri, another app grabbing audio, Control Center, etc. all deactivate
    /// the session out from under us. Without this, every input (mic included) silently stops
    /// working — `inputFormat(forBus:)` starts returning zero channels — until the app is
    /// force-quit and relaunched. Reactivating on `.ended` fixes it in place.
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            switch type {
            case .began:
                if self.isRecording {
                    self.engine.inputNode.removeTap(onBus: 0)
                    self.recordingFile = nil
                    self.isRecording = false
                    self.inputLevel = 0
                }
            case .ended:
                self.reactivateSession()
            @unknown default:
                break
            }
        }
    }

    private func reactivateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true, options: [])
            refreshAvailableInputs()
        } catch {
            print("ArcadePad: failed to reactivate audio session: \(error)")
        }
    }

    func refreshAvailableInputs() {
        let session = AVAudioSession.sharedInstance()
        availableInputs = session.availableInputs ?? []
        currentInputRouteName = session.currentRoute.inputs.first?.portName ?? "—"
    }

    /// Prefers a non-built-in input (USB/line/headset mic) when one is connected.
    func selectPreferredInput(for source: RecordingSource) {
        let session = AVAudioSession.sharedInstance()
        guard let inputs = session.availableInputs else { return }
        switch source {
        case .microphone:
            if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        case .lineOrUSB:
            if let external = inputs.first(where: {
                $0.portType == .usbAudio || $0.portType == .lineIn || $0.portType == .headsetMic
            }) {
                try? session.setPreferredInput(external)
            }
        case .systemAudio:
            break // handled by the (future) broadcast extension, not the session input route.
        }
        refreshAvailableInputs()
    }

    // MARK: Pad chains

    /// Builds every pad's node chain (player -> varispeed -> EQ -> bitcrush -> delay -> reverb ->
    /// mixer) up front, while the engine is still stopped. Attaching/connecting nodes to an
    /// already-running engine was causing AVAudioPlayerNode to throw an uncatchable ObjC
    /// exception on `play()`, so the whole graph is now fixed before the engine ever starts.
    private func buildAllPadChains() {
        for padIndex in 0..<Self.maxPads {
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            let bitcrush = AVAudioUnitDistortion()
            let delay = AVAudioUnitDelay()
            let reverb = AVAudioUnitReverb()

            eq.bands[0].filterType = .lowPass
            eq.bands[0].frequency = 20000
            eq.bands[0].bypass = false
            bitcrush.loadFactoryPreset(.multiDecimated2)
            bitcrush.wetDryMix = 0
            delay.delayTime = 0.28
            delay.feedback = 35
            delay.wetDryMix = 0
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = 0

            [player, varispeed, eq, bitcrush, delay, reverb].forEach { engine.attach($0) }
            engine.connect(player, to: varispeed, format: nil)
            engine.connect(varispeed, to: eq, format: nil)
            engine.connect(eq, to: bitcrush, format: nil)
            engine.connect(bitcrush, to: delay, format: nil)
            engine.connect(delay, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)

            padChains[padIndex] = PadChain(player: player, varispeed: varispeed, eq: eq, bitcrush: bitcrush, delay: delay, reverb: reverb)
        }
    }

    private func chain(for padIndex: Int) -> PadChain? {
        padChains[padIndex]
    }

    /// Starts the engine if needed. Safe to call repeatedly; the graph itself never changes
    /// after `buildAllPadChains()`, so restarting doesn't require reattaching anything.
    @discardableResult
    private func ensureEngineRunning() -> Bool {
        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            print("ArcadePad: failed to start engine: \(error)")
            return false
        }
    }

    func applyEffects(_ settings: EffectSettings, toPad padIndex: Int) {
        guard let chain = chain(for: padIndex) else { return }
        let minFreq = 200.0
        let maxFreq = 20000.0
        chain.eq.bands[0].frequency = Float(minFreq * pow(maxFreq / minFreq, settings.filterCutoff))
        chain.bitcrush.wetDryMix = Float(settings.bitcrushAmount * 100)
        chain.delay.wetDryMix = Float(settings.delayMix * 100)
        chain.reverb.wetDryMix = Float(settings.reverbMix * 100)
    }

    // MARK: Playback

    func play(sample fileURL: URL, padIndex: Int, mode: PlaybackMode, pitchSemitones: Double, volume: Double, trimStart: Double, trimEnd: Double) {
        guard let file = try? AVAudioFile(forReading: fileURL), let chain = chain(for: padIndex) else { return }
        guard ensureEngineRunning() else { return }

        chain.varispeed.rate = Float(pow(2.0, pitchSemitones / 12.0))
        chain.player.volume = Float(volume)

        let frameCount = AVAudioFrameCount(file.length)
        let startFrame = AVAudioFramePosition(Double(file.length) * trimStart)
        let endFrame = AVAudioFramePosition(Double(file.length) * trimEnd)
        let frameLength = AVAudioFrameCount(max(0, endFrame - startFrame))
        guard frameLength > 0 else { return }

        chain.player.stop()
        file.framePosition = startFrame

        // scheduleBuffer requires the buffer's format to exactly match the player node's
        // connected output format, unlike scheduleSegment (which reads straight from an
        // AVAudioFile and converts formats internally). Recorded files can be mono/a
        // different sample rate than the engine's negotiated graph format, so buffers built
        // for .reverse/.loop must be explicitly converted or AVAudioEngine crashes on play().
        let targetFormat = chain.player.outputFormat(forBus: 0)

        if mode == .reverse {
            guard let reversedBuffer = Self.reversedBuffer(from: file, startFrame: startFrame, frameCount: frameLength, targetFormat: targetFormat) else { return }
            chain.player.scheduleBuffer(reversedBuffer, at: nil, options: [.interrupts])
        } else if mode == .loop {
            guard let rawBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameLength) else { return }
            file.framePosition = startFrame
            try? file.read(into: rawBuffer, frameCount: frameLength)
            guard let loopBuffer = Self.convert(rawBuffer, to: targetFormat) else { return }
            chain.player.scheduleBuffer(loopBuffer, at: nil, options: [.loops, .interrupts])
        } else {
            chain.player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameLength,
                at: nil
            )
        }
        _ = frameCount
        chain.player.play()
    }

    func stop(padIndex: Int) {
        padChains[padIndex]?.player.stop()
    }

    func stopAll() {
        padChains.values.forEach { $0.player.stop() }
    }

    /// Choke: stops every pad sharing the given group except the one just triggered.
    func choke(group: Int, exceptPadIndex: Int, pads: [Pad]) {
        for pad in pads where pad.chokeGroup == group && pad.index != exceptPadIndex {
            stop(padIndex: pad.index)
        }
    }

    private static func reversedBuffer(from file: AVAudioFile, startFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return nil }
        file.framePosition = startFrame
        do {
            try file.read(into: raw, frameCount: frameCount)
        } catch {
            return nil
        }
        guard let forward = convert(raw, to: targetFormat) else { return nil }

        let n = Int(forward.frameLength)
        guard let reversed = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        reversed.frameLength = AVAudioFrameCount(n)
        let channelCount = Int(targetFormat.channelCount)
        for channel in 0..<channelCount {
            guard let src = forward.floatChannelData?[channel], let dst = reversed.floatChannelData?[channel] else { continue }
            for i in 0..<n {
                dst[i] = src[n - 1 - i]
            }
        }
        return reversed
    }

    /// Converts a PCM buffer into the engine's negotiated graph format. Buffers scheduled via
    /// `scheduleBuffer` must match the player node's connected format exactly, whereas a
    /// recorded file's native format (mono, a different sample rate, etc.) usually won't.
    private static func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }

        var error: NSError?
        var didProvideInput = false
        converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard error == nil else { return nil }
        return outBuffer
    }

    // MARK: Recording

    enum RecordingError: Error {
        case noInputAvailable
    }

    func startRecording(source: RecordingSource) throws -> URL {
        selectPreferredInput(for: source)

        let input = engine.inputNode
        // Query the format before starting: this locks in the hardware's sample rate and
        // must happen before engine.start(), otherwise AVAudioEngine can throw an
        // uncatchable ObjC exception on Simulator when the graph is initialized with a
        // stale/zero-channel input format.
        var format = input.inputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate == 0 {
            // A stale/interrupted session reports a dead input format. One reactivation
            // attempt recovers most cases (e.g. after a call or Control Center audio grab)
            // without forcing the user to relaunch the app.
            reactivateSession()
            format = input.inputFormat(forBus: 0)
        }
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw RecordingError.noInputAvailable
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingFile = file
        recordingURL = url

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? self?.recordingFile?.write(from: buffer)
            self?.updateLevel(from: buffer)
        }

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                recordingFile = nil
                throw error
            }
        }
        isRecording = true
        return url
    }

    func stopRecording() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        recordingFile = nil
        isRecording = false
        inputLevel = 0
        return recordingURL
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        DispatchQueue.main.async { [weak self] in
            self?.inputLevel = rms
        }
    }
}
