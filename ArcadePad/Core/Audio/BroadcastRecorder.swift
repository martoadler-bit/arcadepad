import Foundation

/// Reads what the ArcadePadBroadcast extension wrote to the shared App Group container.
/// The extension and the app never talk directly — this is a mailbox on disk.
enum BroadcastRecorder {
    private static let appGroupID = "group.com.dlrk.arcadepad"
    private static let audioFileName = "system_audio.caf"
    private static let markerFileName = "system_audio.done"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var audioURL: URL? {
        containerURL?.appendingPathComponent(audioFileName)
    }

    private static var markerURL: URL? {
        containerURL?.appendingPathComponent(markerFileName)
    }

    /// True once a broadcast has finished and left a recording behind.
    static var hasFinishedRecording: Bool {
        guard let markerURL else { return false }
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Moves the finished recording into a temp file the caller owns (mirroring how mic
    /// recordings are handed off) and clears the mailbox for next time.
    static func takeFinishedRecording() -> URL? {
        guard hasFinishedRecording, let audioURL, FileManager.default.fileExists(atPath: audioURL.path) else {
            return nil
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        do {
            try FileManager.default.moveItem(at: audioURL, to: destination)
        } catch {
            return nil
        }
        if let markerURL {
            try? FileManager.default.removeItem(at: markerURL)
        }
        return destination
    }
}
