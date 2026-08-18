import SwiftUI
import AVFoundation

struct RecordView: View {
    let padIndex: Int
    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audio = AudioEngine.shared

    @State private var source: RecordingSource = .microphone
    @State private var recordedURL: URL?
    @State private var recordedDuration: TimeInterval = 0
    @State private var sampleName = ""
    @State private var recordStart: Date?
    @State private var micPermissionDenied = false
    @State private var recordingErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    sourcePicker

                    levelMeter

                    recordButton

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
                assignToPad(url: url)
            } label: {
                Text("ASSIGN TO PAD \(padIndex + 1)")
                    .font(ArcadeTheme.displayFont)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(3)))
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

    private func assignToPad(url: URL) {
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
