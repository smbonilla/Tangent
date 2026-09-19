import Foundation
import SwiftData

@MainActor
final class SwiftDataNoteStore: NoteStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveUserProfile(_ profile: UserProfile) async throws {
        if let record = try userProfileRecord(id: profile.id) {
            record.update(from: profile)
        } else {
            modelContext.insert(UserProfileRecord(profile: profile))
        }
        try modelContext.save()
    }

    func userProfile(id: UUID) async throws -> UserProfile? {
        try userProfileRecord(id: id)?.domainModel
    }

    func userProfiles() async throws -> [UserProfile] {
        let descriptor = FetchDescriptor<UserProfileRecord>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func deleteUserProfile(id: UUID) async throws {
        if let record = try userProfileRecord(id: id) {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func savePrompt(_ prompt: Prompt) async throws {
        if let record = try promptRecord(id: prompt.id) {
            record.text = prompt.text
        } else {
            modelContext.insert(PromptRecord(prompt: prompt))
        }
        try modelContext.save()
    }

    func prompt(id: UUID) async throws -> Prompt? {
        try promptRecord(id: id)?.domainModel
    }

    func prompts() async throws -> [Prompt] {
        let descriptor = FetchDescriptor<PromptRecord>(
            sortBy: [SortDescriptor(\.text)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func deletePrompt(id: UUID) async throws {
        if let record = try promptRecord(id: id) {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func saveQuestion(_ question: Question) async throws {
        if let record = try questionRecord(id: question.id) {
            record.update(from: question)
        } else {
            modelContext.insert(QuestionRecord(question: question))
        }
        try modelContext.save()
    }

    func question(id: UUID) async throws -> Question? {
        try questionRecord(id: id)?.domainModel
    }

    func questions(profileID: UUID?) async throws -> [Question] {
        var descriptor = FetchDescriptor<QuestionRecord>(
            sortBy: [SortDescriptor(\.text)]
        )
        if let profileID {
            descriptor.predicate = #Predicate { $0.profileID == profileID }
        }
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func deleteQuestion(id: UUID) async throws {
        if let record = try questionRecord(id: id) {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func saveDiaryEntry(_ entry: DiaryEntry) async throws {
        if let record = try diaryEntryRecord(id: entry.id) {
            record.update(from: entry)
        } else {
            modelContext.insert(DiaryEntryRecord(entry: entry))
        }
        try modelContext.save()
    }

    func diaryEntry(id: UUID) async throws -> DiaryEntry? {
        try diaryEntryRecord(id: id)?.domainModel
    }

    func diaryEntries(profileID: UUID?) async throws -> [DiaryEntry] {
        var descriptor = FetchDescriptor<DiaryEntryRecord>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        if let profileID {
            descriptor.predicate = #Predicate { $0.profileID == profileID }
        }
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func deleteDiaryEntry(id: UUID) async throws {
        if let record = try diaryEntryRecord(id: id) {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func saveInsight(_ insight: Insight) async throws {
        if let record = try insightRecord(id: insight.id) {
            record.update(from: insight)
        } else {
            modelContext.insert(InsightRecord(insight: insight))
        }
        try modelContext.save()
    }

    func insight(id: UUID) async throws -> Insight? {
        try insightRecord(id: id)?.domainModel
    }

    func insights() async throws -> [Insight] {
        let descriptor = FetchDescriptor<InsightRecord>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func deleteInsight(id: UUID) async throws {
        if let record = try insightRecord(id: id) {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    private func userProfileRecord(id: UUID) throws -> UserProfileRecord? {
        let descriptor = FetchDescriptor<UserProfileRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func promptRecord(id: UUID) throws -> PromptRecord? {
        let descriptor = FetchDescriptor<PromptRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func questionRecord(id: UUID) throws -> QuestionRecord? {
        let descriptor = FetchDescriptor<QuestionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func diaryEntryRecord(id: UUID) throws -> DiaryEntryRecord? {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func insightRecord(id: UUID) throws -> InsightRecord? {
        let descriptor = FetchDescriptor<InsightRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }
}
