import Foundation

/// A recorded or imported audio sample stored as a file in the Kit's sample library.
struct Sample: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Filename relative to the Kit's sample directory (not an absolute path, so kits stay portable).
    var fileName: String
    var duration: TimeInterval
    /// Trim window, expressed as a fraction of the full duration (0...1).
    var trimStart: Double
    var trimEnd: Double
    var gainDB: Double

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        duration: TimeInterval,
        trimStart: Double = 0,
        trimEnd: Double = 1,
        gainDB: Double = 0
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.gainDB = gainDB
    }
}
