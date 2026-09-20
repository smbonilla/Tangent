import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case speechPermissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case recognitionTimedOut
    case recognitionInterrupted
    case recognitionFellBehind

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Tangent needs speech recognition access to transcribe on this device. Enable it in Settings."
        case .recognizerUnavailable:
            return "On-device transcription is not available on this device."
        case .emptyTranscript:
            return "No speech was detected in the recording."
        case .recognitionTimedOut, .recognitionInterrupted, .recognitionFellBehind:
            return "Transcription could not finish. Your recording has been kept so you can try again."
        }
    }
}

/// Live recognition and bounded file recovery both stay entirely on device.
final class OnDeviceTranscriber: LiveTranscriber {
    func startLiveTranscription() async throws -> any LiveTranscriptionSession {
        try await requestAuthorization()
        return LiveSpeechSession(recognizer: try makeOnDeviceRecognizer())
    }

    func transcribe(audioAt url: URL) async throws -> String {
        try await transcribeFile(audioAt: url, onPartial: { _ in })
    }

    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await self.transcribeFile(audioAt: url) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Recovery never submits an entire long file in one recognition request.
    /// Read small buffers into 44-second windows, overlapping by one second.
    private func transcribeFile(
        audioAt url: URL,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await requestAuthorization()
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let windowFrames = AVAudioFramePosition(format.sampleRate * 44)
        let overlapFrames = AVAudioFramePosition(format.sampleRate)
        var start: AVAudioFramePosition = 0
        var fullText = ""
        while start < file.length {
            try Task.checkCancellation()
            let session = LiveSpeechSession(recognizer: try makeOnDeviceRecognizer(), finalizationTimeout: 60)
            do {
                let end = min(start + windowFrames, file.length)
                file.framePosition = start
                while file.framePosition < end {
                    try Task.checkCancellation()
                    let count = AVAudioFrameCount(min(4096, end - file.framePosition))
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                        throw TranscriptionError.recognizerUnavailable
                    }
                    try file.read(into: buffer, frameCount: count)
                    guard buffer.frameLength > 0 else { throw TranscriptionError.recognitionInterrupted }
                    session.append(buffer)
                }
                let text = try await session.finish()
                fullText = TranscriptWindowJoiner.join(fullText, text)
                if !fullText.isEmpty { onPartial(fullText) }
                if end == file.length { break }
                start = end - overlapFrames
            } catch {
                session.cancel()
                throw error // Never silently accept only the successful windows.
            }
        }
        guard !fullText.isEmpty else { throw TranscriptionError.emptyTranscript }
        return fullText
    }

    private func makeOnDeviceRecognizer() throws -> SFSpeechRecognizer {
        for locale in [Locale.autoupdatingCurrent, Locale(identifier: "en-US")] {
            guard let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { continue }
            return recognizer
        }
        throw TranscriptionError.recognizerUnavailable
    }

    private func requestAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.speechPermissionDenied }
        try Task.checkCancellation()
    }
}
