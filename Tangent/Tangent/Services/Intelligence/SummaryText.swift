import Foundation

/// Tidies what a model returns when it was asked for a bare sentence.
///
/// Models add a code fence, a "Short summary:" label or a pair of quotes often
/// enough that stripping them is cheaper than another generation pass.
enum SummaryText {
    private static let labels = [
        "short_summary:",
        "short summary:",
        "summary:", "notes:",
    ]

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        text = stripFence(text)

        if let label = labels.first(where: { text.lowercased().hasPrefix($0) }) {
            text = String(text.dropFirst(label.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        text = stripQuotes(text)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripFence(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var lines = text.components(separatedBy: .newlines)
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only the pair. A trailing quote on its own is the model still writing,
    /// and an opening quote is dropped so streamed text does not start with one.
    private static func stripQuotes(_ text: String) -> String {
        guard text.hasPrefix("\"") else { return text }
        var text = String(text.dropFirst())
        if text.hasSuffix("\"") {
            text = String(text.dropLast())
        }
        return text
    }
}
