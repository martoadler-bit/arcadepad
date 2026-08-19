import SwiftUI

/// Sheet shown from PadEditorView's "DUPLICATE TO..." button: pick which other pad should
/// receive a copy of the source pad's sample + settings. Tapping an occupied pad asks for
/// confirmation since it overwrites that pad's current sample.
struct DuplicatePadTargetView: View {
    let sourceIndex: Int
    let onPick: (Int) -> Void

    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingOverwriteIndex: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Copies this pad's sample and settings onto the pad you pick.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    PadGridView(
                        pads: kitStore.kit.pads,
                        columns: kitStore.kit.gridSize.columns,
                        activePadIndices: [],
                        onTrigger: { pad in handlePick(pad) },
                        onLongPress: { _ in }
                    )
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle("Duplicate To…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Overwrite this pad?",
                isPresented: overwriteConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Overwrite", role: .destructive) {
                    if let index = pendingOverwriteIndex {
                        onPick(index)
                    }
                    pendingOverwriteIndex = nil
                }
                Button("Cancel", role: .cancel) { pendingOverwriteIndex = nil }
            } message: {
                Text("This pad already has a sample. Duplicating here replaces it.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var overwriteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingOverwriteIndex != nil },
            set: { if !$0 { pendingOverwriteIndex = nil } }
        )
    }

    private func handlePick(_ pad: Pad) {
        guard pad.index != sourceIndex else { return }
        if pad.isEmpty {
            onPick(pad.index)
        } else {
            pendingOverwriteIndex = pad.index
        }
    }
}
