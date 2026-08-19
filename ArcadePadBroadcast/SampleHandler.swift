import ReplayKit
import AVFoundation
import os.log

/// Receives audio buffers from other apps while the user has a system broadcast running with
/// ArcadePad selected as the destination. Runs as a separate, memory-constrained process — no
/// UI, no access to the main app's in-memory state, only the shared App Group container on disk.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let appGroupID = "group.com.dlrk.arcadepad"
    private static let audioFileName = "system_audio.caf"
    private static let markerFileName = "system_audio.done"
    private static let log = Logger(subsystem: "com.dlrk.arcadepad.broadcast", category: "SampleHandler")

    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var bufferCount = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        Self.log.notice("broadcastStarted")
        guard let container = Self.containerURL() else {
            Self.log.error("broadcastStarted: App Group container is nil — check the App Group entitlement/capability on both targets")
            return
        }
        Self.log.notice("broadcastStarted: container = \(container.path, privacy: .public)")
        if let audioURL = Self.audioURL() {
            try? FileManager.default.removeItem(at: audioURL)
        }
        if let markerURL = Self.markerURL() {
            try? FileManager.default.removeItem(at: markerURL)
        }
        audioFile = nil
        converter = nil
        outputFormat = nil
        bufferCount = 0
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp else { return }
        guard let audioURL = Self.audioURL() else { return }
        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer) else {
            Self.log.error("processSampleBuffer: couldn't build a PCM buffer from this sample")
            return
        }

        // ReplayKit hands us audio in whatever raw hardware format the source app used — here
        // 16-bit big-endian integer PCM, which AVAudioFile.write(from:) cannot write directly
        // (fails with OSStatus -50/paramErr on every call). Convert every buffer to a canonical
        // Float32 format before writing; that's the format we open the file with too.
        if audioFile == nil {
            guard let canonicalFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: pcmBuffer.format.sampleRate,
                channels: pcmBuffer.format.channelCount,
                interleaved: false
            ), let converter = AVAudioConverter(from: pcmBuffer.format, to: canonicalFormat) else {
                Self.log.error("processSampleBuffer: failed to build canonical format/converter for \(pcmBuffer.format.description, privacy: .public)")
                return
            }
            self.outputFormat = canonicalFormat
            self.converter = converter
            do {
                audioFile = try AVAudioFile(forWriting: audioURL, settings: canonicalFormat.settings)
                Self.log.notice("processSampleBuffer: opened audio file at \(audioURL.path, privacy: .public), source format: \(pcmBuffer.format.description, privacy: .public), writing as: \(canonicalFormat.description, privacy: .public)")
            } catch {
                Self.log.error("processSampleBuffer: failed to open audio file: \(String(describing: error), privacy: .public)")
                return
            }
        }

        guard let converter, let outputFormat,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: pcmBuffer.frameCapacity) else {
            Self.log.error("processSampleBuffer: missing converter/outputFormat or failed to allocate converted buffer")
            return
        }

        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        guard status != .error else {
            Self.log.error("processSampleBuffer: conversion failed: \(String(describing: conversionError), privacy: .public)")
            return
        }

        do {
            try audioFile?.write(from: convertedBuffer)
            bufferCount += 1
            if bufferCount % 100 == 1 {
                let peak = Self.peakAmplitude(of: convertedBuffer)
                Self.log.notice("processSampleBuffer: wrote \(self.bufferCount) buffers so far, peak amplitude = \(peak, privacy: .public)")
            }
        } catch {
            Self.log.error("processSampleBuffer: write failed: \(String(describing: error), privacy: .public)")
        }
    }

    override func broadcastFinished() {
        Self.log.notice("broadcastFinished: total buffers written = \(self.bufferCount)")
        audioFile = nil
        if let audioURL = Self.audioURL(),
           let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int {
            Self.log.notice("broadcastFinished: audio file size = \(size, privacy: .public) bytes")
        }
        guard let markerURL = Self.markerURL() else {
            Self.log.error("broadcastFinished: App Group container is nil, can't write marker")
            return
        }
        let created = FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        Self.log.notice("broadcastFinished: marker written = \(created) at \(markerURL.path, privacy: .public)")
    }

    private static func peakAmplitude(of buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength)
        if let data = buffer.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<n { peak = max(peak, abs(data[i])) }
            return peak
        }
        if let data = buffer.int16ChannelData?[0] {
            var peak: Int16 = 0
            for i in 0..<n { peak = max(peak, abs(data[i])) }
            return Float(peak) / Float(Int16.max)
        }
        return -1
    }

    // MARK: Shared container

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func audioURL() -> URL? {
        containerURL()?.appendingPathComponent(audioFileName)
    }

    static func markerURL() -> URL? {
        containerURL()?.appendingPathComponent(markerFileName)
    }

    // MARK: CMSampleBuffer -> AVAudioPCMBuffer

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            log.error("pcmBuffer: CMSampleBufferGetFormatDescription returned nil")
            return nil
        }
        guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            log.error("pcmBuffer: CMAudioFormatDescriptionGetStreamBasicDescription returned nil")
            return nil
        }
        let asbd = asbdPointer.pointee
        guard let format = AVAudioFormat(streamDescription: asbdPointer) else {
            log.error("pcmBuffer: AVAudioFormat init failed for formatID=\(asbd.mFormatID, privacy: .public) channels=\(asbd.mChannelsPerFrame, privacy: .public) sampleRate=\(asbd.mSampleRate, privacy: .public) flags=\(asbd.mFormatFlags, privacy: .public) bitsPerChannel=\(asbd.mBitsPerChannel, privacy: .public)")
            return nil
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else {
            log.error("pcmBuffer: numSamples = 0")
            return nil
        }
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            log.error("pcmBuffer: AVAudioPCMBuffer allocation failed, frameCapacity=\(numSamples, privacy: .public)")
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Ask CMSampleBuffer how big the AudioBufferList actually needs to be instead of
        // guessing from mChannelsPerFrame — that guess undersized the allocation (status
        // -12737 = kCMSampleBufferError_ArrayTooSmall) for these buffers.
        var sizeNeeded = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard sizeStatus == noErr, sizeNeeded > 0 else {
            log.error("pcmBuffer: size query failed, status=\(sizeStatus, privacy: .public)")
            return nil
        }

        let rawList = malloc(sizeNeeded)!
        defer { free(rawList) }
        let srcListPointer = UnsafeMutableAudioBufferListPointer(rawList.assumingMemoryBound(to: AudioBufferList.self))

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: srcListPointer.unsafeMutablePointer,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            log.error("pcmBuffer: CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed, status=\(status, privacy: .public)")
            return nil
        }

        let dstListPointer = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        for i in 0..<min(dstListPointer.count, srcListPointer.count) {
            if let srcData = srcListPointer[i].mData, let dstData = dstListPointer[i].mData {
                memcpy(dstData, srcData, Int(srcListPointer[i].mDataByteSize))
            }
        }
        return pcmBuffer
    }
}
