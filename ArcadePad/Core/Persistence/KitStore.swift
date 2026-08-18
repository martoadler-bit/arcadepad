import Foundation
import Combine

/// Loads/saves the active Kit and its sample audio files under Documents/Kits/<kitID>/.
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
        let dir = kitsRootURL.appendingPathComponent(kit.id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func sampleURL(for sample: Sample) -> URL {
        currentKitDirectory.appendingPathComponent(sample.fileName)
    }

    private var kitJSONURL: URL {
        currentKitDirectory.appendingPathComponent("kit.json")
    }

    private var lastKitPointerURL: URL {
        documentsURL.appendingPathComponent("last_kit_id.txt")
    }

    // MARK: Save / load

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
        guard let data = try? JSONEncoder().encode(kitToSave) else { return }
        try? data.write(to: kitJSONURL, options: .atomic)
        try? kit.id.uuidString.write(to: lastKitPointerURL, atomically: true, encoding: .utf8)
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
}
