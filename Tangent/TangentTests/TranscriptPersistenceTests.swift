import Foundation
import SwiftData
import Testing
@testable import Tangent

struct TranscriptPersistenceTests {
    @Test
    func relativeAndLegacySandboxPathsResolveTheSameTranscript() throws {
        let text = "This transcript must survive an app-container change."
        let path = try RecordHomeViewModel.writeTranscript(text)
        defer { try? FileManager.default.removeItem(at: TranscriptFiles.url(for: path)) }
        #expect(!path.hasPrefix("/"))
        #expect(DailyTangentDetailsViewModel.loadTranscript(at: path) == text)
        let legacy = "/old-container/Documents/" + path
        #expect(DailyTangentDetailsViewModel.loadTranscript(at: legacy) == text)
    }

    @Test @MainActor
    func recoverySavesPastDayTextBeforeShowingItAndSurvivesReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "diary.store")
        let container = try TangentModelContainer.make(storeURL: storeURL)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let user = UserProfile(name: "Alex")
        try await store.saveUserProfile(user)
        let audio = directory.appending(path: "recording-\(UUID()).m4a")
        try Data("audio backup".utf8).write(to: audio)
        let entry = DiaryEntry(profileID: user.id, day: Date().addingTimeInterval(-86400 * 4),
            promptText: "", transcriptPath: audio.path)
        try await store.saveDiaryEntry(entry)
        let details = DailyTangentDetailsViewModel(noteStore: store, transcriber: PersistenceTranscriber(),
            diaryID: entry.id, streamsTranscript: true)
        let task = Task { await details.start() }
        while details.transcript == nil { await Task.yield() }
        let saved = try #require(await store.diaryEntry(id: entry.id))
        defer { try? FileManager.default.removeItem(at: TranscriptFiles.url(for: saved.transcriptPath)) }
        #expect(saved.transcriptPath.hasSuffix(".txt"))
        #expect(DailyTangentDetailsViewModel.loadTranscript(at: saved.transcriptPath) == PersistenceTranscriber.text)
        task.cancel() // Navigating away must not cancel persistence.
        await task.value
        let reopened = try TangentModelContainer.make(storeURL: storeURL)
        let reopenedStore = SwiftDataNoteStore(modelContext: reopened.mainContext)
        let fresh = DailyTangentDetailsViewModel(noteStore: reopenedStore, diaryID: entry.id)
        await fresh.start()
        #expect(fresh.transcript == PersistenceTranscriber.text)
        #expect(fresh.entry?.day == entry.day)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }

    @Test @MainActor
    func failedDiarySaveKeepsAudioAndTextUntilRecoveryCanCommit() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let base = SwiftDataNoteStore(modelContext: container.mainContext)
        let store = FailingDiaryStore(base: base)
        let user = UserProfile(name: "Alex")
        try await base.saveUserProfile(user)
        let audio = FileManager.default.temporaryDirectory.appending(path: "recover-\(UUID()).m4a")
        let textURL = TranscriptFiles.checkpointURL(for: audio)
        defer {
            try? FileManager.default.removeItem(at: audio)
            try? FileManager.default.removeItem(at: textURL)
        }
        try Data("complete audio".utf8).write(to: audio)
        let entry = DiaryEntry(profileID: user.id, day: Date(), promptText: "", transcriptPath: audio.path)
        try await base.saveDiaryEntry(entry)
        let details = DailyTangentDetailsViewModel(noteStore: store, transcriber: PersistenceTranscriber(), diaryID: entry.id)
        await details.start()
        #expect(details.loadError != nil)
        #expect(try await base.diaryEntry(id: entry.id)?.transcriptPath == audio.path)
        #expect(FileManager.default.fileExists(atPath: audio.path))
        #expect(try String(contentsOf: textURL, encoding: .utf8) == PersistenceTranscriber.text)
        #expect(DailyTangentDetailsViewModel.loadTranscript(at: audio.path) == PersistenceTranscriber.text)
        #expect(DiaryHomeViewModel.transcriptPreview(at: audio.path).hasPrefix("Beginning, middle"))
        store.failSave = false
        let reopened = DailyTangentDetailsViewModel(noteStore: store, transcriber: PersistenceTranscriber(), diaryID: entry.id)
        await reopened.start()
        #expect(reopened.transcript == PersistenceTranscriber.text)
        #expect(reopened.entry?.transcriptPath.hasSuffix(".txt") == true)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }
}

private final class PersistenceTranscriber: Transcriber {
    static let text = "Beginning, middle, and end of a past-day recording."
    func transcribe(audioAt url: URL) async throws -> String { Self.text }
    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield(Self.text); $0.finish() }
    }
}

@MainActor
private final class FailingDiaryStore: NoteStore {
    let base: any NoteStore
    var failSave = true
    init(base: any NoteStore) { self.base = base }
    func saveDiaryEntry(_ entry: DiaryEntry) async throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        try await base.saveDiaryEntry(entry)
    }
    func saveUserProfile(_ profile: UserProfile) async throws { try await base.saveUserProfile(profile) }
    func userProfile(id: UUID) async throws -> UserProfile? { try await base.userProfile(id: id) }
    func userProfiles() async throws -> [UserProfile] { try await base.userProfiles() }
    func deleteUserProfile(id: UUID) async throws { try await base.deleteUserProfile(id: id) }
    func savePrompt(_ prompt: Prompt) async throws { try await base.savePrompt(prompt) }
    func prompt(id: UUID) async throws -> Prompt? { try await base.prompt(id: id) }
    func prompts() async throws -> [Prompt] { try await base.prompts() }
    func deletePrompt(id: UUID) async throws { try await base.deletePrompt(id: id) }
    func saveQuestion(_ question: Question) async throws { try await base.saveQuestion(question) }
    func question(id: UUID) async throws -> Question? { try await base.question(id: id) }
    func questions(profileID: UUID?) async throws -> [Question] { try await base.questions(profileID: profileID) }
    func deleteQuestion(id: UUID) async throws { try await base.deleteQuestion(id: id) }
    func diaryEntry(id: UUID) async throws -> DiaryEntry? { try await base.diaryEntry(id: id) }
    func diaryEntries(profileID: UUID?) async throws -> [DiaryEntry] { try await base.diaryEntries(profileID: profileID) }
    func deleteDiaryEntry(id: UUID) async throws { try await base.deleteDiaryEntry(id: id) }
    func saveInsight(_ insight: Insight) async throws { try await base.saveInsight(insight) }
    func insight(id: UUID) async throws -> Insight? { try await base.insight(id: id) }
    func insights() async throws -> [Insight] { try await base.insights() }
    func deleteInsight(id: UUID) async throws { try await base.deleteInsight(id: id) }
}
