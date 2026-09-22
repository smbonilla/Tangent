import Foundation

/// Plain Unicode text works in messaging, email and notes without Tangent.
enum TangentShareText {
    static func make(entry: DiaryEntry, transcript: String?) -> String {
        var sections = ["Tangent — \(entry.day.formatted(date: .complete, time: .omitted))"]
        if let startedAt = entry.recordingStartedAt {
            sections.append("Recorded at \(startedAt.formatted(date: .omitted, time: .shortened))")
        }
        let summary = entry.summaryShort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { sections.append("Summary\n\(summary)") }
        let text = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { sections.append("Transcript\n\(text)") }
        return sections.joined(separator: "\n\n")
    }
}
