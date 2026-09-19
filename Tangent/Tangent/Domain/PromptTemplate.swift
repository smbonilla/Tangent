import Foundation

/// A reusable prompt template, mirroring the PROMPT table. Placeholders are
/// filled at generation time, and the filled result is what `prompt_text`
/// stores on the row that used it.
struct PromptTemplate: Equatable, Sendable {
    static let transcriptPlaceholder = "{transcript}"
    static let profilePlaceholder = "{user_profile}"
    static let periodPlaceholder = "{period}"
    static let dailySummariesPlaceholder = "{daily_summaries}"

    var text: String

    init(text: String) {
        self.text = text
    }

    func filled(transcript: String, profile: UserProfile) -> String {
        text
            .replacingOccurrences(
                of: Self.transcriptPlaceholder,
                with: transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            .replacingOccurrences(
                of: Self.profilePlaceholder,
                with: profile.promptDescription
            )
    }

    func filled(period: String, summaries: [DiarySummary], focus: DiaryFocus = DiaryFocus()) -> String {
        let lines = summaries.sorted { $0.day < $1.day }.map { summary in
            let day = summary.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(day): \(summary.text)"
        }
        return text
            .replacingOccurrences(of: Self.periodPlaceholder, with: period)
            .replacingOccurrences(of: Self.profilePlaceholder, with: focus.promptDescription)
            .replacingOccurrences(
                of: Self.dailySummariesPlaceholder,
                with: lines.joined(separator: "\n")
            )
    }
}

extension PromptTemplate {
    /// The single sentence stored for each diary entry.
    static let dailyShortSummary = PromptTemplate(
        text: """
        Summarise this voice diary entry in one short sentence, in the writer's voice
        using "I" and "my". Return only the sentence.

        Capture what mattered in this entry: an experience, idea, activity, feeling,
        achievement, or difficulty. It can be about any topic.
        Use the writer's interests and concerns to choose what to foreground, but
        never treat the profile as evidence that something happened today.
        Do not invent details, give advice, or add an explanation.

        USER PROFILE: {user_profile}

        TRANSCRIPT: {transcript}
        """
    )

    static let weeklyInsights = PromptTemplate(
        text: """
        Write up to five brief insights, addressing the writer as "you", in clear
        everyday language. Return only the insights.

        Look back over the dated short summaries and notice trends, recurring
        themes, changes, progress, or difficulties. Use the summaries as the
        only evidence.

        Interests and concerns, when listed, are context for what the writer may
        want to hear about. Prefer observations that speak to them when the
        summaries support that, but still report other clear patterns. If none
        are listed, draw insights only from the summaries.

        Do not invent events, reasons, or trends, and do not treat interests or
        concerns as things that happened in this period.

        INTERESTS AND CONCERNS: {user_profile}

        NOTES ({period}):
        {daily_summaries}
        """
    )
}

extension UserProfile {
    var focus: DiaryFocus {
        DiaryFocus(interests: interests, concerns: concerns)
    }

    /// Only reflection-relevant details enter a model prompt.
    var promptDescription: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([name.isEmpty ? nil : "Name: \(name)", focus.promptDescription]
            .compactMap { $0 }).joined(separator: "\n")
    }
}

extension DiaryFocus {
    var promptDescription: String {
        var lines: [String] = []
        if !interests.isEmpty { lines.append("Interests: \(interests.joined(separator: "; "))") }
        if !concerns.isEmpty { lines.append("Concerns: \(concerns.joined(separator: "; "))") }
        return lines.isEmpty ? "No interests or concerns specified." : lines.joined(separator: "\n")
    }
}
