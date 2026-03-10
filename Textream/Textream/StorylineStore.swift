import Foundation

@Observable
final class StorylineStore {
    private(set) var storylines: [SavedStoryline] = []

    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("Textream/Storylines", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - CRUD

    @discardableResult
    func save(_ storyline: Storyline) -> SavedStoryline {
        let saved = SavedStoryline(storyline: storyline)
        storylines.append(saved)
        writeToDisk(saved)
        sortByDate()
        return saved
    }

    func update(_ saved: SavedStoryline) {
        var updated = saved
        updated = SavedStoryline(
            storyline: saved.storyline,
            id: saved.id,
            createdAt: saved.createdAt,
            updatedAt: Date()
        )
        if let idx = storylines.firstIndex(where: { $0.id == saved.id }) {
            storylines[idx] = updated
        }
        writeToDisk(updated)
    }

    func delete(_ id: UUID) {
        storylines.removeAll { $0.id == id }
        let file = directory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    func storyline(for id: UUID) -> SavedStoryline? {
        storylines.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        storylines = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SavedStoryline.self, from: data)
            }
        sortByDate()
    }

    private func writeToDisk(_ saved: SavedStoryline) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(saved) else { return }
        let file = directory.appendingPathComponent("\(saved.id.uuidString).json")
        try? data.write(to: file, options: .atomic)
    }

    private func sortByDate() {
        storylines.sort { $0.updatedAt > $1.updatedAt }
    }
}
