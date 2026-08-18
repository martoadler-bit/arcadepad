import Foundation
import Combine
import AVFoundation

/// Loads/saves kits under Documents/Kits/<kitID>/. Keeps one "current" kit open at a time
/// (what the botonera shows), but the library (list/create/duplicate/delete/install-starter)
/// operates on any kit by id, not just the current one.
final class KitStore: ObservableObject {
    @Published var kit: Kit {
        didSet { save() }
    }

    private let fileManager = FileManager.default
    private var saveWorkItem: DispatchWorkItem?

    init() {
        if let loaded = Self.loadLastKit() {
            self.kit = loaded
        } else {
            self.kit = Kit()
        }
    }

    // MARK: Paths

    var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var kitsRootURL: URL {
        documentsURL.appendingPathComponent("Kits", isDirectory: true)
    }

    var currentKitDirectory: URL {
        directory(for: kit.id)
    }

    private func directory(for kitID: UUID) -> URL {
        let dir = kitsRootURL.appendingPathComponent(kitID.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func sampleURL(for sample: Sample) -> URL {
        currentKitDirectory.appendingPathComponent(sample.fileName)
    }

    private func kitJSONURL(for kitID: UUID) -> URL {
        directory(for: kitID).appendingPathComponent("kit.json")
    }

    private var lastKitPointerURL: URL {
        documentsURL.appendingPathComponent("last_kit_id.txt")
    }

    // MARK: Save / load (current kit)

    /// Debounced so rapid pad edits (dragging a slider) don't hammer disk I/O.
    func save() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistNow()
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func persistNow() {
        var kitToSave = kit
        kitToSave.updatedAt = Date()
        writeKitFile(kitToSave)
        try? kit.id.uuidString.write(to: lastKitPointerURL, atomically: true, encoding: .utf8)
    }

    private func writeKitFile(_ kitToWrite: Kit) {
        guard let data = try? JSONEncoder().encode(kitToWrite) else { return }
        try? data.write(to: kitJSONURL(for: kitToWrite.id), options: .atomic)
    }

    private static func loadLastKit() -> Kit? {
        let fm = FileManager.default
        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pointerURL = documentsURL.appendingPathComponent("last_kit_id.txt")
        guard let idString = try? String(contentsOf: pointerURL, encoding: .utf8) else { return nil }
        let kitDir = documentsURL.appendingPathComponent("Kits", isDirectory: true).appendingPathComponent(idString, isDirectory: true)
        let kitJSON = kitDir.appendingPathComponent("kit.json")
        guard let data = try? Data(contentsOf: kitJSON) else { return nil }
        return try? JSONDecoder().decode(Kit.self, from: data)
    }

    // MARK: Library

    /// Every saved kit, most recently updated first.
    func listSavedKits() -> [KitSummary] {
        guard let entries = try? fileManager.contentsOfDirectory(at: kitsRootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let summaries = entries.compactMap { dir -> KitSummary? in
            let jsonURL = dir.appendingPathComponent("kit.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let decoded = try? JSONDecoder().decode(Kit.self, from: data)
            else { return nil }
            return KitSummary(
                id: decoded.id,
                name: decoded.name,
                gridSize: decoded.gridSize,
                filledPadCount: decoded.pads.filter { !$0.isEmpty }.count,
                updatedAt: decoded.updatedAt
            )
        }
        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createNewKit(name: String, gridSize: GridSize = .eight) -> UUID {
        let newKit = Kit(name: name, gridSize: gridSize)
        writeKitFile(newKit)
        kit = newKit
        return newKit.id
    }

    func loadKit(id: UUID) {
        guard id != kit.id else { return }
        let jsonURL = kitJSONURL(for: id)
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode(Kit.self, from: data)
        else { return }
        kit = decoded
    }

    func renameCurrentKit(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        kit.name = trimmed
    }

    /// Renames any saved kit by id, without switching which one is currently open.
    func renameKit(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if id == kit.id {
            kit.name = trimmed
            return
        }
        let jsonURL = kitJSONURL(for: id)
        guard let data = try? Data(contentsOf: jsonURL),
              var decoded = try? JSONDecoder().decode(Kit.self, from: data)
        else { return }
        decoded.name = trimmed
        decoded.updatedAt = Date()
        writeKitFile(decoded)
    }

    /// Copies a kit's folder (samples + kit.json) under a new id, so edits to the copy never
    /// touch the original.
    @discardableResult
    func duplicateKit(id: UUID) -> UUID? {
        let sourceDir = directory(for: id)
        let sourceJSON = sourceDir.appendingPathComponent("kit.json")
        guard let data = try? Data(contentsOf: sourceJSON),
              let sourceKit = try? JSONDecoder().decode(Kit.self, from: data)
        else { return nil }

        let newID = UUID()
        let destDir = directory(for: newID)
        if let files = try? fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent != "kit.json" {
                try? fileManager.copyItem(at: file, to: destDir.appendingPathComponent(file.lastPathComponent))
            }
        }

        let newKit = Kit(
            id: newID,
            name: "\(sourceKit.name) copy",
            gridSize: sourceKit.gridSize,
            pads: sourceKit.pads,
            pattern: sourceKit.pattern
        )
        writeKitFile(newKit)
        return newID
    }

    /// Deletes a saved kit. If it was the current one, switches to the most recently
    /// updated remaining kit, or creates a fresh blank kit if none are left.
    func deleteKit(id: UUID) {
        try? fileManager.removeItem(at: directory(for: id))
        guard id == kit.id else { return }
        if let next = listSavedKits().first {
            loadKit(id: next.id)
        } else {
            kit = Kit()
        }
    }

    // MARK: Starter kits

    /// Installs a bundled starter kit as a new saved kit (copying its audio into the kit's
    /// own folder, same as any user-recorded sample) and returns its id.
    @discardableResult
    func installStarterKit(_ starter: StarterKit) -> UUID {
        let newID = UUID()
        let destDir = directory(for: newID)

        var pads: [Pad] = []
        for index in 0..<starter.gridSize.rawValue {
            guard index < starter.pads.count, let bundleURL = starter.pads[index].bundleURL else {
                pads.append(Pad(index: index, colorIndex: index % 6))
                continue
            }
            let padDef = starter.pads[index]
            let fileName = "\(UUID().uuidString).\(bundleURL.pathExtension)"
            try? fileManager.copyItem(at: bundleURL, to: destDir.appendingPathComponent(fileName))
            let duration = Self.audioDuration(of: bundleURL)
            let sample = Sample(name: padDef.name, fileName: fileName, duration: duration)
            pads.append(Pad(index: index, sample: sample, colorIndex: index % 6))
        }

        let newKit = Kit(id: newID, name: starter.name, gridSize: starter.gridSize, pads: pads)
        writeKitFile(newKit)
        return newID
    }

    // MARK: Sample import

    /// Moves a freshly recorded file (in tmp) into the kit's sample directory and returns the Sample model.
    @discardableResult
    func importRecording(from tempURL: URL, name: String, duration: TimeInterval) throws -> Sample {
        let fileName = "\(UUID().uuidString).caf"
        let destination = currentKitDirectory.appendingPathComponent(fileName)
        try fileManager.moveItem(at: tempURL, to: destination)
        return Sample(name: name, fileName: fileName, duration: duration)
    }

    func deleteSampleFile(_ sample: Sample) {
        try? fileManager.removeItem(at: sampleURL(for: sample))
    }

    private static func audioDuration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
