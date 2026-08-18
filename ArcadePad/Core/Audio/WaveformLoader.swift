import AVFoundation

enum WaveformLoader {
    /// Downsamples a file to `sampleCount` peak values (0...1) for a cheap waveform view.
    static func loadPeaks(url: URL, sampleCount: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return [] }
        do {
            try file.read(into: buffer)
        } catch {
            return []
        }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let totalSamples = Int(buffer.frameLength)
        guard totalSamples > 0 else { return [] }
        let bucketSize = max(1, totalSamples / sampleCount)
        var peaks: [Float] = []
        peaks.reserveCapacity(sampleCount)
        var i = 0
        while i < totalSamples && peaks.count < sampleCount {
            var peak: Float = 0
            let end = min(i + bucketSize, totalSamples)
            for j in i..<end {
                peak = max(peak, abs(channelData[j]))
            }
            peaks.append(peak)
            i += bucketSize
        }
        return peaks
    }

    /// Offline-renders a reversed copy of the file at the given URL, returns the new file's URL.
    static func renderReversed(sourceURL: URL) -> URL? {
        guard let file = try? AVAudioFile(forReading: sourceURL) else { return nil }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        guard let reversed = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return nil }
        reversed.frameLength = frameCount
        let channelCount = Int(file.processingFormat.channelCount)
        let n = Int(frameCount)
        for c in 0..<channelCount {
            guard let src = buffer.floatChannelData?[c], let dst = reversed.floatChannelData?[c] else { continue }
            for i in 0..<n { dst[i] = src[n - 1 - i] }
        }
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        guard let outFile = try? AVAudioFile(forWriting: outURL, settings: file.processingFormat.settings) else { return nil }
        try? outFile.write(from: reversed)
        return outURL
    }
}
