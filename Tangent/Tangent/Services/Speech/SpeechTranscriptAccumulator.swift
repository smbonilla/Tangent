import Foundation

/// SpeechTranscriber emits consecutive finalized segments exactly once when
/// volatile reporting is disabled. Repeated words are real speech, not overlap.
struct SpeechTranscriptAccumulator {
    private(set) var text = ""

    mutating func appendFinal(_ segment: String) {
        // Preserve the spacing and punctuation supplied by SpeechTranscriber,
        // including languages that do not separate words with spaces.
        text += segment
    }
}
