import SwiftUI

struct KitLibraryView: View {
    @EnvironmentObject var kitStore: KitStore
    @Environment(\.dismiss) private var dismiss

    @State private var savedKits: [KitSummary] = []
    @State private var showNewKitPrompt = false
    @State private var newKitName = ""
    @State private var renamingSummary: KitSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ArcadeTheme.cabinetBackground.ignoresSafeArea()
                List {
                    Section {
                        ForEach(savedKits) { summary in
                            kitRow(summary)
                        }
                    } header: {
                        Text("MY KITS").foregroundStyle(ArcadeTheme.marqueeText)
                    }

                    Section {
                        ForEach(StarterKit.all) { starter in
                            starterRow(starter)
                        }
                    } header: {
                        Text("STARTER KITS").foregroundStyle(ArcadeTheme.marqueeText)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Kit Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        newKitName = "New Kit"
                        showNewKitPrompt = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: refresh)
        .alert("Name your kit", isPresented: $showNewKitPrompt) {
            TextField("Kit name", text: $newKitName)
            Button("Create") {
                kitStore.createNewKit(name: newKitName.isEmpty ? "New Kit" : newKitName)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename kit", isPresented: Binding(get: { renamingSummary != nil }, set: { if !$0 { renamingSummary = nil } })) {
            TextField("Kit name", text: $renameText)
            Button("Save") {
                if let summary = renamingSummary {
                    rename(summary, to: renameText)
                }
                renamingSummary = nil
            }
            Button("Cancel", role: .cancel) { renamingSummary = nil }
        }
    }

    private func kitRow(_ summary: KitSummary) -> some View {
        Button {
            kitStore.loadKit(id: summary.id)
            dismiss()
        } label: {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(summary.id == kitStore.kit.id ? ArcadeTheme.marqueeText : ArcadeTheme.padColor(summary.gridSize.rawValue % 6))
                    .frame(width: 8, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.name)
                        .font(ArcadeTheme.labelFont)
                        .foregroundStyle(.white)
                    Text("\(summary.filledPadCount)/\(summary.gridSize.rawValue) pads · \(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if summary.id == kitStore.kit.id {
                    Text("OPEN")
                        .font(.caption2.bold())
                        .foregroundStyle(ArcadeTheme.marqueeText)
                }
            }
        }
        .listRowBackground(ArcadeTheme.panelBackground)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                kitStore.deleteKit(id: summary.id)
                refresh()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                kitStore.duplicateKit(id: summary.id)
                refresh()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
            Button {
                renameText = summary.name
                renamingSummary = summary
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func starterRow(_ starter: StarterKit) -> some View {
        Button {
            let id = kitStore.installStarterKit(starter)
            kitStore.loadKit(id: id)
            refresh()
            dismiss()
        } label: {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(ArcadeTheme.marqueeText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(starter.name)
                        .font(ArcadeTheme.labelFont)
                        .foregroundStyle(.white)
                    Text(starter.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("USE")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ArcadeTheme.padColor(2))
                    .clipShape(Capsule())
            }
        }
        .listRowBackground(ArcadeTheme.panelBackground)
    }

    private func refresh() {
        savedKits = kitStore.listSavedKits()
    }

    private func rename(_ summary: KitSummary, to newName: String) {
        kitStore.renameKit(id: summary.id, to: newName)
        refresh()
    }
}
