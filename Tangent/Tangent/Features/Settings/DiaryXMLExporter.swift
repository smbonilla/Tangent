import Foundation

enum DiaryXMLExporter {
    static func makeDocument(
        entries: [DiaryEntry],
        profileID: UUID,
        generatedAt: Date = Date()
    ) -> Data {
        let sortedEntries = entries.sorted { $0.day < $1.day }
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<tangent-diary profile-id=\"\(profileID.uuidString)\" generated-at=\"\(dateString(generatedAt))\">",
        ]

        for entry in sortedEntries {
            lines.append("  <entry id=\"\(entry.id.uuidString)\">")
            lines.append("    <profile-id>\(entry.profileID.uuidString)</profile-id>")
            lines.append("    <day>\(dateString(entry.day))</day>")
            lines.append("    <questions>")
            for question in entry.questions {
                lines.append("      <question id=\"\(question.id.uuidString)\">\(escaped(question.text))</question>")
            }
            lines.append("    </questions>")
            lines.append("    <prompt-text>\(escaped(entry.promptText))</prompt-text>")
            lines.append("    <summary-short>\(escaped(entry.summaryShort))</summary-short>")
            lines.append("    <transcript-path>\(escaped(entry.transcriptPath))</transcript-path>")
            lines.append("  </entry>")
        }

        lines.append("</tangent-diary>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
