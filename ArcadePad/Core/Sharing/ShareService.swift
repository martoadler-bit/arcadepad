import Foundation
import AVFoundation

/// Uploads a Kit to Supabase Storage (via REST, no SDK) and returns a public web-preview
/// URL, served as a static page from GitHub Pages. Auth is anonymous and silent: the
/// `share` bucket's policies only need to know the request is authenticated, not by whom.
final class ShareService {
    static let shared = ShareService()

    /// Where the static preview page (web/) is published.
    private static let previewPageURL = "https://martoadler-bit.github.io/arcadepad/"

    enum ShareError: LocalizedError {
        case notConfigured
        case authFailed
        case uploadFailed(String)
        case emptyKit

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Sharing isn't set up yet (missing Supabase config)."
            case .authFailed: return "Couldn't authenticate with the share service."
            case .uploadFailed(let detail): return "Upload failed: \(detail)"
            case .emptyKit: return "This kit has no samples to share yet."
            }
        }
    }

    private var cachedAccessToken: String?

    private init() {}

    func shareKit(_ kit: Kit, kitStore: KitStore) async throws -> URL {
        guard SupabaseConfig.isConfigured else { throw ShareError.notConfigured }
        let filledPads = kit.pads.filter { !$0.isEmpty }
        guard !filledPads.isEmpty else { throw ShareError.emptyKit }

        let accessToken = try await authenticatedToken()
        let shareID = Self.randomID()

        var sharedPads: [SharedKitManifest.SharedPad] = []
        for pad in filledPads {
            guard let sample = pad.sample else { continue }
            let localURL = kitStore.sampleURL(for: sample)
            // Recordings are saved as .caf, which only Safari's Web Audio can decode —
            // Chrome and Firefox reject it outright. Convert to 16-bit PCM WAV, which every
            // browser's decodeAudioData understands.
            let audioData = try Self.wavData(fromLocalFile: localURL)
            let storagePath = "\(shareID)/pad\(pad.index).wav"
            let downloadURL = try await upload(
                data: audioData,
                path: storagePath,
                contentType: "audio/wav",
                accessToken: accessToken
            )
            sharedPads.append(
                SharedKitManifest.SharedPad(
                    index: pad.index,
                    name: sample.name,
                    mode: pad.mode,
                    pitchSemitones: pad.pitchSemitones,
                    volume: pad.volume,
                    trimStart: sample.trimStart,
                    trimEnd: sample.trimEnd,
                    colorIndex: pad.colorIndex,
                    audioURL: downloadURL
                )
            )
        }

        let manifest = SharedKitManifest(
            id: shareID,
            name: kit.name,
            gridSize: kit.gridSize.rawValue,
            pads: sharedPads,
            createdAt: Date()
        )
        let manifestData = try JSONEncoder.shareEncoder.encode(manifest)
        _ = try await upload(
            data: manifestData,
            path: "\(shareID)/manifest.json",
            contentType: "application/json",
            accessToken: accessToken
        )

        return URL(string: "\(Self.previewPageURL)?id=\(shareID)")!
    }

    // MARK: Auth

    /// Supabase's anonymous sign-in: POST /auth/v1/signup with no credentials creates a
    /// throwaway user and returns a session, as long as "Anonymous Sign-Ins" is enabled on
    /// the project.
    private func authenticatedToken() async throws -> String {
        if let cachedAccessToken { return cachedAccessToken }

        let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([String: String]())

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String
        else { throw ShareError.authFailed }

        cachedAccessToken = accessToken
        return accessToken
    }

    // MARK: Upload

    private func upload(data: Data, path: String, contentType: String, accessToken: String) async throws -> String {
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let url = URL(string: "\(SupabaseConfig.projectURL)/storage/v1/object/share/\(encodedPath)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let bodyText = String(data: responseData, encoding: .utf8) ?? "unknown error"
            throw ShareError.uploadFailed(bodyText)
        }

        return "\(SupabaseConfig.projectURL)/storage/v1/object/public/share/\(encodedPath)"
    }

    private static func randomID(length: Int = 9) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Reads a local recording and re-encodes it as 16-bit PCM WAV for universal browser support.
    private static func wavData(fromLocalFile sourceURL: URL) throws -> Data {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = sourceFile.processingFormat
        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard frameCount > 0, let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw ShareError.uploadFailed("empty or unreadable recording")
        }
        try sourceFile.read(into: sourceBuffer)

        guard let wavFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: true
        ), let converter = AVAudioConverter(from: sourceFormat, to: wavFormat),
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: wavFormat, frameCapacity: frameCount)
        else {
            throw ShareError.uploadFailed("couldn't prepare WAV conversion")
        }

        var conversionError: NSError?
        var didProvideInput = false
        converter.convert(to: convertedBuffer, error: &conversionError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        if let conversionError { throw conversionError }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let outFile = try AVAudioFile(forWriting: tempURL, settings: wavFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        try outFile.write(from: convertedBuffer)
        return try Data(contentsOf: tempURL)
    }
}

private extension JSONEncoder {
    static let shareEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
