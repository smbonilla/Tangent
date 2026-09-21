import Foundation

/// A durable intent written before microphone capture. On the next launch an
/// interrupted recording becomes a normal entry whose full audio can be retried.
/// Recovery uses a new id for replacement recordings, preserving the old entry.
struct PendingRecording: Codable, Sendable {
    let id: UUID
    let profileID: UUID
    let day: Date
    let startedAt: Date
    let audioPath: String

    var audioURL: URL { TranscriptFiles.url(for: audioPath) }
    var journalURL: URL { audioURL.appendingPathExtension("json") }

    func save() throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: journalURL, options: .atomic)
    }

    func removeJournal() throws { try FileManager.default.removeItem(at: journalURL) }

    static func loadAll(directory: URL = URL.documentsDirectory.appending(path: "Recordings")) throws -> [PendingRecording] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".caf.json") }
            .compactMap { try? JSONDecoder().decode(Self.self, from: Data(contentsOf: $0)) }
    }

    @MainActor
    func recover(in store: any NoteStore) async throws {
        guard FileManager.default.fileExists(atPath: journalURL.path),
              FileManager.default.fileExists(atPath: audioURL.path) else { return }
        // Idempotent if the process stopped between saving the entry and
        // removing its journal. Never replace an already completed transcript.
        if try await store.diaryEntry(id: id) == nil {
            try await store.saveDiaryEntry(DiaryEntry(
                id: id, profileID: profileID, day: day, recordingStartedAt: startedAt,
                promptText: "Recovered interrupted recording", transcriptPath: audioPath
            ))
        }
        try removeJournal()
    }
}
