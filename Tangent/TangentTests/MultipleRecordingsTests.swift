import Foundation
import SwiftData
import Testing
@testable import Tangent

struct MultipleRecordingsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func timelineShowsAllSameDayEntriesInStartOrder() throws {
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        let morning = DiaryEntry(profileID: UUID(), day: day,
            recordingStartedAt: day.addingTimeInterval(9 * 3600), promptText: "", summaryShort: "Morning")
        let afternoon = DiaryEntry(profileID: morning.profileID, day: day,
            recordingStartedAt: day.addingTimeInterval(15 * 3600), promptText: "", summaryShort: "Afternoon")
        let days = DiaryHomeViewModel.makeTimeline(entries: [afternoon, morning], today: day, calendar: calendar)
        #expect(days.count == 1)
        #expect(days[0].entries.map(\.id) == [morning.id, afternoon.id])
    }

    @Test @MainActor
    func recordingStartTimePersistsSeparatelyFromAssignedPastDate() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let user = UserProfile(name: "Alex")
        try await store.saveUserProfile(user)
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        let start = Date()
        let model = RecordHomeViewModel(audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(), noteStore: store)
        let id = try await model.saveEntry(day: past, transcriptPath: "", questions: [], recordingStartedAt: start)
        let entry = try #require(await store.diaryEntry(id: id))
        #expect(entry.day == past)
        #expect(entry.recordingStartedAt == start)
        let exported = DiaryXMLExporter.makeDocument(entries: [entry], profileID: user.id)
        #expect(String(decoding: exported, as: UTF8.self).contains("<recording-started-at>"))
    }

    @Test @MainActor
    func versionFourDiaryMigratesWithoutInventingRecordingTimes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "diary.store")
        let entry = DiaryEntry(profileID: UUID(), day: Date(), promptText: "Original prompt",
            summaryShort: "Original summary", transcriptPath: "/private/original.txt")
        try autoreleasepool {
            let schema = Schema(TangentSchemaV4.models, version: TangentSchemaV4.versionIdentifier)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            container.mainContext.insert(TangentSchemaV1.DiaryEntryRecord(entry: entry))
            try container.mainContext.save()
        }
        try autoreleasepool {
            let container = try TangentModelContainer.make(storeURL: url)
            let records = try container.mainContext.fetch(FetchDescriptor<DiaryEntryRecord>())
            #expect(records.map(\.domainModel) == [entry])
            #expect(records.first?.recordingStartedAt == nil)
            let startedAt = Date()
            records.first?.recordingStartedAt = startedAt
            try container.mainContext.save()
        }
        try autoreleasepool {
            let container = try TangentModelContainer.make(storeURL: url)
            #expect(try container.mainContext.fetch(FetchDescriptor<DiaryEntryRecord>()).first?.recordingStartedAt != nil)
        }
    }
}
