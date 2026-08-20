import SwiftUI
import AVFoundation

struct RecordView: View {
    let padIndex: Int
    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audio = AudioEngine.shared

    // Defaults to whatever source was used last time, so returning users who mainly capture
    // System Audio don't have to re-tap the segmented control every time they open Record.
    @State private var source: RecordingSource = Self.lastUsedSource
    @State private var recordedURL: URL?
    @State private var recordedDuration: TimeInterval = 0
    @State private var sampleName = ""
    @State private var recordStart: Date?
    @State private var micPermissionDenied = false
    @State private var recordingErrorMessage: String?
    @State private var previewPlayer: AVAudioPlayer?
    @State private var isPreviewPlaying = false
    @State private var previewDelegate = PreviewPlayerDelegate()
    @State private var isSplitting = false

    private let broadcastPollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    sourcePicker

                    if source == .systemAudio {
                        systemAudioSection
                    } else {
                        levelMeter
                        recordButton
                    }

                    if let recordingErrorMessage {
                        Text(recordingErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let recordedURL {
                        previewSection(url: recordedURL)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Record → Pad \(padIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { requestMicPermission() }
        .onChange(of: source) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.lastUsedSourceKey)
        }
        .onReceive(broadcastPollTimer) { _ in
            checkForFinishedBroadcast()
        }
        .sheet(isPresented: $isSplitting) {
            if let recordedURL {
                SplitAudioView(
                    sourceURL: recordedURL,
                    sourceDuration: recordedDuration,
                    baseName: sampleName.isEmpty ? "Pad \(padIndex + 1) Sample" : sampleName,
                    onComplete: { dismiss() }
                )
                .environmentObject(kitStore)
            }
        }
    }

    private static let lastUsedSourceKey = "RecordView.lastUsedSource"

    private static var lastUsedSource: RecordingSource {
        UserDefaults.standard.string(forKey: lastUsedSourceKey)
            .flatMap(RecordingSource.init(rawValue:)) ?? .microphone
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $source) {
            ForEach(RecordingSource.allCases.filter(\.isAvailable)) { src in
                Text(src.label).tag(src)
            }
        }
        .pickerStyle(.segmented)
        .disabled(audio.isRecording)
    }

    private var systemAudioSection: some View {
        VStack(spacing: 16) {
            Text("Tap below, pick ArcadePad, then Start Broadcast. Play the sound you want from another app — a red status bar appears while it's on. Stop it from here or Control Center when you're done; ArcadePad picks up the recording automatically.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            BroadcastPickerView()
                .frame(width: 60, height: 60)

            Text("Only capture audio you have the rights to use.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            if recordedURL == nil {
                Text("Waiting for broadcast…")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var levelMeter: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.4))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ArcadeTheme.marqueeText)
                        .frame(width: geo.size.width * CGFloat(min(1, audio.inputLevel * 6)))
                }
        }
        .frame(height: 24)
    }

    private var recordButton: some View {
        Button {
            if audio.isRecording {
                finishRecording()
            } else {
                beginRecording()
            }
        } label: {
            Text(audio.isRecording ? "STOP" : "● RECORD")
                .font(ArcadeTheme.displayFont)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(ArcadeButtonStyle(color: audio.isRecording ? .red : ArcadeTheme.padColor(1), isActive: audio.isRecording))
        .disabled(micPermissionDenied)

        .overlay(alignment: .bottom) {
            if micPermissionDenied {
                Text("Microphone access denied — enable it in Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .offset(y: 24)
            }
        }
    }

    private func previewSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Sample name", text: $sampleName)
                .textFieldStyle(.roundedBorder)

            Button {
                togglePreview(url: url)
            } label: {
                Label(isPreviewPlaying ? "STOP" : "PREVIEW", systemImage: isPreviewPlaying ? "stop.fill" : "play.fill")
                    .font(ArcadeTheme.displayFont)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(1)))

            Button {
                assignToPad(url: url)
            } label: {
                Text("ASSIGN TO PAD \(padIndex + 1)")
                    .font(ArcadeTheme.displayFont)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(3)))

            Button {
                previewPlayer?.stop()
                isPreviewPlaying = false
                isSplitting = true
            } label: {
                Text("SPLIT ACROSS PADS…")
                    .font(ArcadeTheme.labelFont)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(4)))
        }
    }

    private func togglePreview(url: URL) {
        if isPreviewPlaying {
            previewPlayer?.stop()
            isPreviewPlaying = false
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            previewDelegate.onFinish = { isPreviewPlaying = false }
            player.delegate = previewDelegate
            previewPlayer = player
            player.play()
            isPreviewPlaying = true
        } catch {
            print("ArcadePad: preview playback failed: \(error)")
        }
    }

    private func requestMicPermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                micPermissionDenied = !granted
            }
        }
    }

    private func beginRecording() {
        previewPlayer?.stop()
        isPreviewPlaying = false
        recordedURL = nil
        recordingErrorMessage = nil
        recordStart = Date()
        do {
            _ = try audio.startRecording(source: source)
        } catch AudioEngine.RecordingError.noInputAvailable {
            recordingErrorMessage = "No audio input available for \(source.label). Try a different source."
        } catch {
            recordingErrorMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    private func finishRecording() {
        guard let url = audio.stopRecording() else { return }
        recordedURL = url
        recordedDuration = Date().timeIntervalSince(recordStart ?? Date())
        if sampleName.isEmpty {
            sampleName = "Pad \(padIndex + 1) Sample"
        }
    }

    private func checkForFinishedBroadcast() {
        guard source == .systemAudio, recordedURL == nil else { return }
        guard let url = BroadcastRecorder.takeFinishedRecording() else { return }
        recordedURL = url
        recordedDuration = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        if sampleName.isEmpty {
            sampleName = "Pad \(padIndex + 1) Sample"
        }
    }

    private func assignToPad(url: URL) {
        previewPlayer?.stop()
        do {
            let sample = try kitStore.importRecording(from: url, name: sampleName, duration: recordedDuration)
            if let idx = kitStore.kit.pads.firstIndex(where: { $0.index == padIndex }) {
                kitStore.kit.pads[idx].sample = sample
            }
            dismiss()
        } catch {
            print("ArcadePad: failed to assign recording: \(error)")
        }
    }
}

private final class PreviewPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
