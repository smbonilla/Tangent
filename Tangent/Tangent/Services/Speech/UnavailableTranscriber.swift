import Foundation

enum TranscriberError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "Transcription is not implemented yet."
    }
}

final class UnavailableTranscriber: Transcriber {
    func transcribe(audioAt url: URL) async throws -> String {
        throw TranscriberError.notImplemented
    }

    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: TranscriberError.notImplemented)
        }
    }
}
