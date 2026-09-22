import Foundation
import SwiftData
import Testing
@testable import Tangent

struct TangentActionsTests {
    @Test
    func sharingIncludesReadableContentWithoutInternalMetadata() {
        let entry = DiaryEntry(profileID: UUID(), day: Date(), recordingStartedAt: Date(),
            promptText: "PRIVATE MODEL PROMPT", summaryShort: "A good day.", transcriptPath: "/private/diary.txt")
        let text = TangentShareText.make(entry: entry, transcript: "I visited a café. 👋\nThen walked home.")
        #expect(text.contains("Summary\nA good day."))
        #expect(text.contains("Transcript\nI visited a café. 👋\nThen walked home."))
        #expect(text.contains("Recorded at"))
        #expect(!text.contains(entry.promptText))
        #expect(!text.contains(entry.transcriptPath))
        #expect(!text.contains(entry.profileID.uuidString))
        var noSummary = entry
        noSummary.summaryShort = ""
        #expect(!TangentShareText.make(entry: noSummary, transcript: "My words").contains("Summary\n"))
    }

    @Test @MainActor
    func deletingOneTangentPreservesOthersAndCannotBeUndoneByAutosave() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let path = try RecordHomeViewModel.writeTranscript("Delete these words")
        let otherPath = try RecordHomeViewModel.writeTranscript("Keep these words")
        defer {
            try? FileManager.default.removeItem(at: TranscriptFiles.url(for: path))
            try? FileManager.default.removeItem(at: TranscriptFiles.url(for: otherPath))
        }
        let entry = DiaryEntry(profileID: UUID(), day: Date(), promptText: "", transcriptPath: path)
        let other = DiaryEntry(profileID: entry.profileID, day: entry.day, promptText: "", transcriptPath: otherPath)
        try await store.saveDiaryEntry(entry)
        try await store.saveDiaryEntry(other)
        let model = DailyTangentDetailsViewModel(noteStore: store, diaryID: entry.id)
        await model.start()
        #expect(await model.deleteEntry())
        #expect(!(await model.saveEdits(summary: "Late edit", transcript: "Late words")))
        await model.load()
        #expect(model.entry == nil)
        #expect(try await store.diaryEntry(id: entry.id) == nil)
        #expect(try await store.diaryEntry(id: other.id) == other)
        #expect(!FileManager.default.fileExists(atPath: TranscriptFiles.url(for: path).path))
        #expect(DailyTangentDetailsViewModel.loadTranscript(at: otherPath) == "Keep these words")
    }

    @Test @MainActor
    func deletingAnEntryDoesNotRemoveATranscriptReferencedByAnother() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let path = try RecordHomeViewModel.writeTranscript("Shared legacy transcript")
        defer { try? FileManager.default.removeItem(at: TranscriptFiles.url(for: path)) }
        let entry = DiaryEntry(profileID: UUID(), day: Date(), promptText: "", transcriptPath: path)
        let other = DiaryEntry(profileID: entry.profileID, day: entry.day, promptText: "", transcriptPath: path)
        try await store.saveDiaryEntry(entry)
        try await store.saveDiaryEntry(other)
        let model = DailyTangentDetailsViewModel(noteStore: store, diaryID: entry.id)
        await model.start()
        #expect(await model.deleteEntry())
        #expect(DailyTangentDetailsViewModel.loadTranscript(at: path) == "Shared legacy transcript")
    }

    @Test @MainActor
    func redoingOneTangentKeepsOtherRecordingsOnTheSameDay() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let profile = UserProfile(name: "Alex")
        try await store.saveUserProfile(profile)
        let entry = DiaryEntry(profileID: profile.id, day: Date(), promptText: "", summaryShort: "Old summary")
        let other = DiaryEntry(profileID: profile.id, day: entry.day, promptText: "", summaryShort: "Keep")
        try await store.saveDiaryEntry(entry)
        try await store.saveDiaryEntry(other)
        let model = RecordHomeViewModel(audioRecorder: UnavailableAudioRecorder(), transcriber: UnavailableTranscriber(), noteStore: store)
        let id = try await model.saveEntry(day: entry.day, transcriptPath: "Transcripts/replacement.txt", questions: [], replacingEntryID: entry.id)
        #expect(id == entry.id)
        #expect(try await store.diaryEntry(id: entry.id)?.summaryShort == "")
        #expect(try await store.diaryEntry(id: other.id) == other)
        #expect(try await store.diaryEntries(profileID: nil).count == 2)
    }
    @Test @MainActor
    func lateTranscriptionCannotRestoreADeletedTangent() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let audio = URL.documentsDirectory.appending(path: "Recordings/delete-\(UUID()).caf")
        let checkpoint = TranscriptFiles.checkpointURL(for: audio)
        try TranscriptFiles.write("Audio placeholder", to: audio)
        try TranscriptFiles.write("Partial transcript", to: checkpoint)
        defer {
            try? FileManager.default.removeItem(at: audio)
            try? FileManager.default.removeItem(at: checkpoint)
        }
        let entry = DiaryEntry(profileID: UUID(), day: Date(), promptText: "", transcriptPath: TranscriptFiles.reference(for: audio))
        try await store.saveDiaryEntry(entry)
        let transcriber = DelayedActionTranscriber()
        let model = DailyTangentDetailsViewModel(noteStore: store, transcriber: transcriber, diaryID: entry.id)
        let task = Task { await model.start() }
        while transcriber.continuation == nil { await Task.yield() }
        #expect(await model.deleteEntry())
        transcriber.continuation?.resume(returning: "Late complete transcript")
        await task.value
        #expect(try await store.diaryEntry(id: entry.id) == nil)
        #expect(model.entry == nil)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        #expect(!FileManager.default.fileExists(atPath: checkpoint.path))
    }

}


@MainActor
private final class DelayedActionTranscriber: Transcriber {
    var continuation: CheckedContinuation<String, Never>?
    func transcribe(audioAt url: URL) async throws -> String {
        await withCheckedContinuation { continuation = $0 }
    }
    nonisolated func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
