import SwiftUI

struct ShareKitView: View {
    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss

    @State private var isUploading = false
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("Share \(kitStore.kit.name)")
                        .font(ArcadeTheme.displayFont)
                        .foregroundStyle(ArcadeTheme.marqueeText)

                    Text("Uploads your kit's samples so anyone with the link can try the pads in a browser — no app install needed. Effects aren't previewed on the web, just playback.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if isUploading {
                        ProgressView("Uploading…")
                            .tint(ArcadeTheme.marqueeText)
                    } else if let shareURL {
                        VStack(spacing: 16) {
                            Text(shareURL.absoluteString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.white)
                                .padding()
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            ShareLink(item: shareURL) {
                                Text("SHARE LINK")
                                    .font(ArcadeTheme.displayFont)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(3)))
                        }
                        .padding(.horizontal)
                    } else {
                        Button {
                            upload()
                        } label: {
                            Text("UPLOAD & GET LINK")
                                .font(ArcadeTheme.displayFont)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(ArcadeButtonStyle(color: ArcadeTheme.padColor(1)))
                        .padding(.horizontal)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func upload() {
        errorMessage = nil
        isUploading = true
        Task {
            do {
                let url = try await ShareService.shared.shareKit(kitStore.kit, kitStore: kitStore)
                await MainActor.run {
                    shareURL = url
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }
}
