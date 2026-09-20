import Foundation
import SwiftData

@Model
final class UserProfileRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    private var interestsData: Data?
    private var concernsData: Data?
    var dailyReminder: Date?

    var interests: [String] {
        get { StringArrayStorage.decode(interestsData) }
        set { interestsData = StringArrayStorage.encode(newValue) }
    }

    var concerns: [String] {
        get { StringArrayStorage.decode(concernsData) }
        set { concernsData = StringArrayStorage.encode(newValue) }
    }

    init(profile: UserProfile) {
        id = profile.id
        name = profile.name
        interestsData = StringArrayStorage.encode(profile.interests)
        concernsData = StringArrayStorage.encode(profile.concerns)
        dailyReminder = profile.dailyReminder
    }

    func update(from profile: UserProfile) {
        name = profile.name
        interests = profile.interests
        concerns = profile.concerns
        dailyReminder = profile.dailyReminder
    }

    var domainModel: UserProfile {
        UserProfile(
            id: id,
            name: name,
            interests: interests,
            concerns: concerns,
            dailyReminder: dailyReminder
        )
    }
}

private enum StringArrayStorage {
    static func encode(_ strings: [String]) -> Data {
        (try? JSONEncoder().encode(strings)) ?? Data("[]".utf8)
    }

    static func decode(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

@Model
final class PromptRecord {
    @Attribute(.unique) var id: UUID
    var text: String

    init(prompt: Prompt) {
        id = prompt.id
        text = prompt.text
    }

    var domainModel: Prompt {
        Prompt(id: id, text: text)
    }
}

@Model
final class QuestionRecord {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var promptText: String
    var text: String

    init(question: Question) {
        id = question.id
        profileID = question.profileID
        promptText = question.promptText
        text = question.text
    }

    func update(from question: Question) {
        profileID = question.profileID
        promptText = question.promptText
        text = question.text
    }

    var domainModel: Question {
        Question(
            id: id,
            profileID: profileID,
            promptText: promptText,
            text: text
        )
    }
}

@Model
final class DiaryEntryRecord {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var day: Date
    var questions: [DiaryQuestion]
    var promptText: String
    var summaryShort: String
    var transcriptPath: String

    init(entry: DiaryEntry) {
        id = entry.id
        profileID = entry.profileID
        day = entry.day
        questions = entry.questions
        promptText = entry.promptText
        summaryShort = entry.summaryShort
        transcriptPath = entry.transcriptPath
    }

    func update(from entry: DiaryEntry) {
        profileID = entry.profileID
        day = entry.day
        questions = entry.questions
        promptText = entry.promptText
        summaryShort = entry.summaryShort
        transcriptPath = entry.transcriptPath
    }

    var domainModel: DiaryEntry {
        DiaryEntry(
            id: id,
            profileID: profileID,
            day: day,
            questions: questions,
            promptText: promptText,
            summaryShort: summaryShort,
            transcriptPath: transcriptPath
        )
    }
}

@Model
final class InsightRecord {
    @Attribute(.unique) var id: UUID
    var day: Date
    var generatedFrom: Date
    var generatedTo: Date
    var promptText: String
    var text: String

    init(insight: Insight) {
        id = insight.id
        day = insight.day
        generatedFrom = insight.generatedFrom
        generatedTo = insight.generatedTo
        promptText = insight.promptText
        text = insight.text
    }

    func update(from insight: Insight) {
        day = insight.day
        generatedFrom = insight.generatedFrom
        generatedTo = insight.generatedTo
        promptText = insight.promptText
        text = insight.text
    }

    var domainModel: Insight {
        Insight(
            id: id,
            day: day,
            generatedFrom: generatedFrom,
            generatedTo: generatedTo,
            promptText: promptText,
            text: text
        )
    }
}
