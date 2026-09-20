import Foundation

/// Speech results may describe only the latest utterance after a pause. Keep
/// completed utterances by audio time, while replacing revisions of that utterance.
struct SpeechTranscriptAccumulator {
    private struct Utterance {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }
    private var completed: [Utterance] = []
    private var partial: Utterance?

    mutating func update(text: String, start: TimeInterval, end: TimeInterval, isStable: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Preserve an earlier result if the recognizer advances to a later
        // audio interval without sending a metadata-bearing utterance boundary.
        if let previous = partial, start >= previous.end, start > previous.start + 0.05 {
            completed.append(previous)
            partial = nil
        }
        // Both partial and final results can revise already-settled speech.
        // Audio time identifies a revision; matching words alone would also
        // discard a phrase that the speaker genuinely says again later.
        completed.removeAll {
            abs($0.start - start) < 0.05 || (start < $0.end - 0.05 && end > $0.start + 0.05)
        }
        let utterance = Utterance(start: start, end: end, text: text)
        if isStable {
            completed.append(utterance)
            partial = nil
        } else {
            partial = utterance
        }
    }

    var text: String {
        var utterances = completed
        if let partial { utterances.append(partial) }
        return utterances.sorted { $0.start < $1.start }.map(\.text).joined(separator: " ")
    }
}

/// Adjacent recognition windows share a short audio overlap, so words at the
/// boundary are heard in full. Remove only a matching suffix/prefix there.
enum TranscriptWindowJoiner {
    static func join(_ earlier: String, _ later: String) -> String {
        let left = earlier.split(whereSeparator: \.isWhitespace).map(String.init)
        let right = later.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !left.isEmpty else { return later }
        guard !right.isEmpty else { return earlier }
        func normalized(_ word: String) -> String {
            word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        let maximumOverlap = min(12, left.count, right.count)
        for count in stride(from: maximumOverlap, through: 1, by: -1) {
            if left.suffix(count).map(normalized) == right.prefix(count).map(normalized) {
                return (left + right.dropFirst(count)).joined(separator: " ")
            }
        }
        return earlier + " " + later
    }
}
