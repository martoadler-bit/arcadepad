import AVFoundation

/// Offline-renders a sequencer pattern (optionally looped several times) to a WAV file, reusing
/// the same per-pad effects chain shape as the live AudioEngine (varispeed/EQ/bitcrush/delay/
/// reverb) so the export sounds like what you actually hear while jamming — just on its own
/// AVAudioEngine instance in `.offline` manual-rendering mode, independent of the live one.
enum SequencerExporter {
    enum ExportError: LocalizedError {
        case noActivePads
        case renderFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noActivePads: return "This pattern has no active steps to export."
            case .renderFailed: return "Rendering the sequence failed."
            case .writeFailed: return "Couldn't write the exported audio file."
            }
        }
    }

    /// Runs synchronously — call from a background queue. `loopCount` must be at least 1.
    static func export(kit: Kit, kitStore: KitStore, loopCount: Int) throws -> URL {
        let pattern = kit.pattern
        let sampleRate = 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw ExportError.renderFailed
        }

        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)

        struct Chain {
            let player: AVAudioPlayerNode
            let buffer: AVAudioPCMBuffer
        }
        var chains: [Int: Chain] = [:]

        for pad in kit.pads {
            guard let sample = pad.sample else { continue }
            guard pattern.steps(forPad: pad.index).contains(where: \.isActive) else { continue }

            let url = kitStore.sampleURL(for: sample)
            guard let sourceFile = try? AVAudioFile(forReading: url) else { continue }
            let totalFrames = sourceFile.length
            let startFrame = AVAudioFramePosition(Double(totalFrames) * sample.trimStart)
            let endFrame = AVAudioFramePosition(Double(totalFrames) * sample.trimEnd)
            let frameLength = AVAudioFrameCount(max(0, endFrame - startFrame))
            guard frameLength > 0,
                  let rawBuffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frameLength)
            else { continue }
            sourceFile.framePosition = startFrame
            guard (try? sourceFile.read(into: rawBuffer, frameCount: frameLength)) != nil else { continue }

            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            let bitcrush = AVAudioUnitDistortion()
            let delay = AVAudioUnitDelay()
            let reverb = AVAudioUnitReverb()

            let minFreq = 200.0, maxFreq = 20000.0
            eq.bands[0].filterType = .lowPass
            eq.bands[0].frequency = Float(minFreq * pow(maxFreq / minFreq, pad.effects.filterCutoff))
            eq.bands[0].bypass = false
            bitcrush.loadFactoryPreset(.multiDecimated2)
            bitcrush.wetDryMix = Float(pad.effects.bitcrushAmount * 100)
            delay.delayTime = 0.28
            delay.feedback = 35
            delay.wetDryMix = Float(pad.effects.delayMix * 100)
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = Float(pad.effects.reverbMix * 100)
            varispeed.rate = Float(pow(2.0, pad.pitchSemitones / 12.0))
            player.volume = Float(pad.volume)

            [player, varispeed, eq, bitcrush, delay, reverb].forEach { engine.attach($0) }
            engine.connect(player, to: varispeed, format: nil)
            engine.connect(varispeed, to: eq, format: nil)
            engine.connect(eq, to: bitcrush, format: nil)
            engine.connect(bitcrush, to: delay, format: nil)
            engine.connect(delay, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)

            let targetFormat = player.outputFormat(forBus: 0)
            let sourceBuffer = pad.mode == .reverse ? (Self.reversed(rawBuffer) ?? rawBuffer) : rawBuffer
            let playBuffer = Self.convert(sourceBuffer, to: targetFormat) ?? sourceBuffer

            chains[pad.index] = Chain(player: player, buffer: playBuffer)
        }

        guard !chains.isEmpty else { throw ExportError.noActivePads }

        try engine.start()

        let secondsPerStep = 60.0 / pattern.tempoBPM / 4.0
        let loops = max(1, loopCount)

        for loop in 0..<loops {
            for step in 0..<pattern.stepCount {
                let swungDelay = (step % 2 == 1) ? pattern.swing * secondsPerStep * 0.5 : 0
                let stepTime = Double(loop * pattern.stepCount + step) * secondsPerStep + swungDelay
                let sampleTime = AVAudioFramePosition(stepTime * sampleRate)
                let when = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)

                for pad in kit.pads {
                    guard let chain = chains[pad.index] else { continue }
                    let steps = pattern.steps(forPad: pad.index)
                    guard step < steps.count, steps[step].isActive else { continue }
                    chain.player.scheduleBuffer(chain.buffer, at: when, options: [])
                }
            }
        }

        chains.values.forEach { $0.player.play() }

        let tailSeconds = 2.0
        let totalDuration = Double(loops * pattern.stepCount) * secondsPerStep + tailSeconds
        let totalFramesToRender = AVAudioFrameCount(totalDuration * sampleRate)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(kit.name)-\(loops)x.wav")
        guard let outFile = try? AVAudioFile(forWriting: outputURL, settings: format.settings) else {
            throw ExportError.writeFailed
        }

        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw ExportError.renderFailed
        }
        var renderedFrames: AVAudioFrameCount = 0

        while renderedFrames < totalFramesToRender {
            let framesToRender = min(renderBuffer.frameCapacity, totalFramesToRender - renderedFrames)
            renderBuffer.frameLength = framesToRender
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            switch status {
            case .success:
                try outFile.write(from: renderBuffer)
                renderedFrames += framesToRender
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw ExportError.renderFailed
            @unknown default:
                throw ExportError.renderFailed
            }
        }

        return outputURL
    }

    private static func reversed(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let reversed = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        let n = Int(buffer.frameLength)
        reversed.frameLength = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        for c in 0..<channelCount {
            guard let src = buffer.floatChannelData?[c], let dst = reversed.floatChannelData?[c] else { continue }
            for i in 0..<n { dst[i] = src[n - 1 - i] }
        }
        return reversed
    }

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
}
