import ReplayKit
import AVFoundation

/// Receives audio buffers from other apps while the user has a system broadcast running with
/// ArcadePad selected as the destination. Runs as a separate, memory-constrained process — no
/// UI, no access to the main app's in-memory state, only the shared App Group container on disk.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let appGroupID = "group.com.dlrk.arcadepad"
    private static let audioFileName = "system_audio.caf"
    private static let markerFileName = "system_audio.done"

    private var audioFile: AVAudioFile?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // The audio format isn't known until the first buffer arrives, so the file is opened
        // lazily in processSampleBuffer instead of here.
        try? FileManager.default.removeItem(at: Self.markerURL())
        try? FileManager.default.removeItem(at: Self.audioURL())
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp else { return }
        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer) else { return }

        if audioFile == nil {
            audioFile = try? AVAudioFile(forWriting: Self.audioURL(), settings: pcmBuffer.format.settings)
        }
        try? audioFile?.write(from: pcmBuffer)
    }

    override func broadcastFinished() {
        audioFile = nil
        FileManager.default.createFile(atPath: Self.markerURL().path, contents: Data())
    }

    // MARK: Shared container

    private static func containerURL() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
    }

    static func audioURL() -> URL {
        containerURL().appendingPathComponent(audioFileName)
    }

    static func markerURL() -> URL {
        containerURL().appendingPathComponent(markerFileName)
    }

    // MARK: CMSampleBuffer -> AVAudioPCMBuffer

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: asbdPointer)
        else { return nil }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0, let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
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
        guard status == noErr else { return nil }

        let dstListPointer = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        for i in 0..<min(dstListPointer.count, srcListPointer.count) {
            if let srcData = srcListPointer[i].mData, let dstData = dstListPointer[i].mData {
                memcpy(dstData, srcData, Int(srcListPointer[i].mDataByteSize))
            }
        }
        return pcmBuffer
    }
}
