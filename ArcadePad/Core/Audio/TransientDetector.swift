import AVFoundation

/// Finds natural cut points in a recording — hits, words, notes — so a long recording can be
/// split at musically/acoustically sensible places instead of blindly even slices.
enum TransientDetector {
    /// Returns up to `maxCount` onset positions as fractions of the file's duration (0...1),
    /// sorted chronologically. Uses a short-time energy envelope and picks the samples where
    /// that energy rises fastest (a simple, cheap onset-detection approach).
    static func detectTransients(url: URL, maxCount: Int) -> [Double] {
        guard maxCount > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        else { return [] }
        guard (try? file.read(into: buffer)) != nil else { return [] }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let totalSamples = Int(buffer.frameLength)
        let sampleRate = file.processingFormat.sampleRate
        guard totalSamples > 0, sampleRate > 0 else { return [] }

        let windowSize = max(1, Int(sampleRate * 0.012)) // ~12ms windows
        let windowCount = totalSamples / windowSize
        guard windowCount > 4 else { return [] }

        // Short-time energy (RMS) envelope.
        var energy = [Float](repeating: 0, count: windowCount)
        for w in 0..<windowCount {
            let start = w * windowSize
            let end = min(start + windowSize, totalSamples)
            var sum: Float = 0
            for i in start..<end { sum += channelData[i] * channelData[i] }
            energy[w] = (sum / Float(end - start)).squareRoot()
        }

        // Positive flux: how sharply the energy is rising — a hit/word onset spikes this.
        var flux = [Float](repeating: 0, count: windowCount)
        for w in 1..<windowCount {
            flux[w] = max(0, energy[w] - energy[w - 1])
        }

        let mean = flux.reduce(0, +) / Float(flux.count)
        let variance = flux.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(flux.count)
        let threshold = mean + variance.squareRoot() * 0.75

        let minSpacingWindows = max(1, Int(0.15 * sampleRate / Double(windowSize))) // 150ms apart minimum

        var candidates: [(index: Int, strength: Float)] = []
        var w = 1
        while w < windowCount {
            guard flux[w] > threshold else {
                w += 1
                continue
            }
            var peakIndex = w
            var peakValue = flux[w]
            var j = w + 1
            while j < windowCount, j - w < minSpacingWindows {
                if flux[j] > peakValue {
                    peakValue = flux[j]
                    peakIndex = j
                }
                j += 1
            }
            candidates.append((peakIndex, peakValue))
            w = peakIndex + minSpacingWindows
        }

        let strongest = candidates.sorted { $0.strength > $1.strength }.prefix(maxCount)
        return strongest.map { Double($0.index * windowSize) / Double(totalSamples) }.sorted()
    }
}
