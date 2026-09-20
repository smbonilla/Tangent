import Foundation

struct UserProfile: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var interests: [String]
    var concerns: [String]
    var dailyReminder: Date?

    init(
        id: UUID = UUID(),
        name: String,
        interests: [String] = [],
        concerns: [String] = [],
        dailyReminder: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.interests = interests
        self.concerns = concerns
        self.dailyReminder = dailyReminder
    }
}

struct DiaryFocus: Equatable, Sendable {
    var interests: [String] = []
    var concerns: [String] = []
}

struct Prompt: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct Question: Identifiable, Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    var promptText: String
    var text: String

    init(
        id: UUID = UUID(),
        profileID: UUID,
        promptText: String,
        text: String
    ) {
        self.id = id
        self.profileID = profileID
        self.promptText = promptText
        self.text = text
    }
}

struct DiaryQuestion: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct DiaryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    var day: Date
    var recordingStartedAt: Date?
    var questions: [DiaryQuestion]
    var promptText: String
    var summaryShort: String
    var transcriptPath: String

    init(
        id: UUID = UUID(),
        profileID: UUID,
        day: Date,
        recordingStartedAt: Date? = nil,
        questions: [DiaryQuestion] = [],
        promptText: String,
        summaryShort: String = "",
        transcriptPath: String = ""
    ) {
        self.id = id
        self.profileID = profileID
        self.day = day
        self.recordingStartedAt = recordingStartedAt
        self.questions = questions
        self.promptText = promptText
        self.summaryShort = summaryShort
        self.transcriptPath = transcriptPath
    }
}

/// The only diary content available to insight generation.
struct DiarySummary: Equatable, Sendable {
    let day: Date
    let text: String

    init?(entry: DiaryEntry) {
        let text = entry.summaryShort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.day = entry.day
        self.text = text
    }
}

struct Insight: Identifiable, Equatable, Sendable {
    let id: UUID
    var day: Date
    var generatedFrom: Date
    var generatedTo: Date
    var promptText: String
    var text: String

    init(
        id: UUID = UUID(),
        day: Date,
        generatedFrom: Date,
        generatedTo: Date,
        promptText: String,
        text: String
    ) {
        self.id = id
        self.day = day
        self.generatedFrom = generatedFrom
        self.generatedTo = generatedTo
        self.promptText = promptText
        self.text = text
    }
}
