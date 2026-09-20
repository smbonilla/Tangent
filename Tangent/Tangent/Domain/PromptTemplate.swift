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
        text: PromptResource.load("daily_short_summary")
    )

    static let weeklyInsights = PromptTemplate(
        text: PromptResource.load("weekly_insights")
    )
}

private enum PromptResource {
    static func load(_ name: String) -> String {
        let locations: [String?] = ["Resources/Prompts", "Prompts", nil]
        let bundles = [Bundle(for: PromptBundleToken.self), Bundle.main]
        let url = bundles.lazy.compactMap { bundle in
            locations.lazy.compactMap { subdirectory in
                bundle.url(
                    forResource: name,
                    withExtension: "txt",
                    subdirectory: subdirectory
                )
            }.first
        }.first

        guard let url else {
            preconditionFailure("Missing bundled prompt resource: \(name).txt")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .newlines)
        } catch {
            preconditionFailure("Unable to read bundled prompt resource \(name).txt: \(error)")
        }
    }
}

private final class PromptBundleToken {}

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
