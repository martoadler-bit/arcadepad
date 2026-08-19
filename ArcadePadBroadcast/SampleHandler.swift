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
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp else { return }
        guard let audioURL = Self.audioURL() else { return }
        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer) else {
            Self.log.error("processSampleBuffer: couldn't build a PCM buffer from this sample")
            return
        }

        if audioFile == nil {
            do {
                audioFile = try AVAudioFile(forWriting: audioURL, settings: pcmBuffer.format.settings)
                Self.log.notice("processSampleBuffer: opened audio file at \(audioURL.path, privacy: .public), format: \(pcmBuffer.format.description, privacy: .public)")
            } catch {
                Self.log.error("processSampleBuffer: failed to open audio file: \(String(describing: error), privacy: .public)")
            }
        }
        do {
            try audioFile?.write(from: pcmBuffer)
            bufferCount += 1
            if bufferCount % 100 == 0 {
                Self.log.notice("processSampleBuffer: wrote \(self.bufferCount) buffers so far")
            }
        } catch {
            Self.log.error("processSampleBuffer: write failed: \(String(describing: error), privacy: .public)")
        }
    }

    override func broadcastFinished() {
        Self.log.notice("broadcastFinished: total buffers written = \(self.bufferCount)")
        audioFile = nil
        guard let markerURL = Self.markerURL() else {
            Self.log.error("broadcastFinished: App Group container is nil, can't write marker")
            return
        }
        let created = FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        Self.log.notice("broadcastFinished: marker written = \(created) at \(markerURL.path, privacy: .public)")
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

        let channelCount = Int(asbdPointer.pointee.mChannelsPerFrame)
        let srcListPointer = AudioBufferList.allocate(maximumBuffers: channelCount)
        defer { free(srcListPointer.unsafeMutablePointer) }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: srcListPointer.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: channelCount),
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
