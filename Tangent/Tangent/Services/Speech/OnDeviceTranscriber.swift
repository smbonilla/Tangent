import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case unsupportedLocale
    case emptyTranscript
    case recognitionInterrupted
    case recognitionFellBehind

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "On-device transcription is not available on this device. Your audio is saved."
        case .unsupportedLocale:
            return "On-device transcription does not support your current language. Your audio is saved."
        case .emptyTranscript:
            return "No speech was detected in the recording."
        case .recognitionInterrupted, .recognitionFellBehind:
            return "Transcription could not finish. Your recording has been kept so you can try again."
        }
    }
}

/// iOS 26's long-form, on-device speech engine. Silence is part of the input,
/// never a reason to end the session or discard earlier finalized segments.
final class OnDeviceTranscriber: LiveTranscriber {
    func startLiveTranscription(onPartial: @escaping @Sendable (String) -> Void) async throws -> any LiveTranscriptionSession {
        let transcriber = try await makeTranscriber(downloadIfNeeded: false)
        return try await LiveSpeechSession.start(transcriber: transcriber, onPartial: onPartial)
    }

    func transcribe(audioAt url: URL) async throws -> String {
        try await transcribeFile(audioAt: url, onPartial: { _ in })
    }

    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
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

    private func transcribeFile(audioAt url: URL, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        let transcriber = try await makeTranscriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let checkpoint = TranscriptCheckpoint(url: TranscriptFiles.checkpointURL(for: url))
        let results = Task {
            do {
                var transcript = SpeechTranscriptAccumulator()
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    transcript.appendFinal(String(result.text.characters))
                    try checkpoint.save(transcript.text)
                    onPartial(transcript.text)
                }
                return transcript.text
            } catch {
                // Stop input consumption promptly if result delivery or a
                // checkpoint fails; do not keep processing an unread stream.
                await analyzer.cancelAndFinishNow()
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            do {
                // Apple's provider reads and converts on demand rather than
                // eagerly enqueuing an entire long recording in memory.
                let source = try AVAudioFile(forReading: url)
                if let end = try await analyzer.analyzeSequence(from: source) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let text = try await results.value
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranscriptionError.emptyTranscript }
                return text
            } catch {
                await analyzer.cancelAndFinishNow()
                results.cancel()
                throw error
            }
        } onCancel: {
            results.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func makeTranscriber(downloadIfNeeded: Bool = true) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.recognizerUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .autoupdatingCurrent) else {
            throw TranscriptionError.unsupportedLocale
        }
        // Only finalized segments: no repeated full-document writes for every
        // speculative word. Final results arrive throughout a long recording.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        if !downloadIfNeeded, await AssetInventory.status(forModules: [transcriber]) != .installed {
            throw TranscriptionError.recognizerUnavailable
        }
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        return transcriber
    }
}
