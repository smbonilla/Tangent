import AVFoundation
import Foundation
import Speech

/// Owns one analyzer for the entire recording. Audio waiting for recognition
/// is strictly bounded; an overflow invalidates live results, leaving the disk
/// recording available for complete, demand-driven file transcription.
final class LiveSpeechSession: LiveTranscriptionSession, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let input: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let resultTask: Task<String, Error>
    private let lock = NSLock()
    private let converter: AnalyzerInputConverter
    private var failure: Error?
    private var ended = false

    private init(analyzer: SpeechAnalyzer, input: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
                 format: AVAudioFormat, resultTask: Task<String, Error>) {
        self.analyzer = analyzer
        self.input = input
        self.converter = AnalyzerInputConverter(analyzerFormat: format)
        self.resultTask = resultTask
    }

    static func start(transcriber: SpeechTranscriber, onPartial: @escaping @Sendable (String) -> Void) async throws -> LiveSpeechSession {
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.recognizerUnavailable
        }
        let (stream, input) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let results = Task {
            do {
                var transcript = SpeechTranscriptAccumulator()
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    transcript.appendFinal(String(result.text.characters))
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
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
            return LiveSpeechSession(analyzer: analyzer, input: input, format: format, resultTask: results)
        } catch {
            input.finish(throwing: error)
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // Called by the disk writer, never the audio render thread. The lock
        // protects conversion and end-of-input against cancellation/Stop.
        lock.withLock {
            guard !ended, failure == nil else { return }
            do {
                // Also bound bytes/duration per queued element, independently
                // of the hardware's chosen tap-buffer size.
                guard buffer.frameLength <= 16_384 else { throw TranscriptionError.recognitionFellBehind }
                for converted in try converter.convert(buffer, at: nil) {
                    try enqueue(converted)
                }
            } catch {
                failure = error
                input.finish(throwing: error)
                resultTask.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
    }

    func finish() async throws -> String {
        try await withTaskCancellationHandler {
            do {
                try lock.withLock {
                    if let failure { throw failure }
                    guard !ended else { throw TranscriptionError.recognitionInterrupted }
                    ended = true
                    // Convert held-over samples before closing input, including
                    // the last word. This is part of Apple's converter contract.
                    for converted in try converter.flush() { try enqueue(converted) }
                    input.finish()
                }
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let text = try await resultTask.value
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranscriptionError.emptyTranscript }
                return text
            } catch {
                cancel()
                throw error
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.withLock {
            ended = true
            if failure == nil { failure = CancellationError() }
            input.finish(throwing: CancellationError())
            resultTask.cancel()
        }
        Task { await analyzer.cancelAndFinishNow() }
    }

    private func enqueue(_ audio: AnalyzerInput) throws {
        switch input.yield(audio) {
        case .enqueued: break
        case .dropped: throw TranscriptionError.recognitionFellBehind
        case .terminated: throw TranscriptionError.recognitionInterrupted
        @unknown default: throw TranscriptionError.recognitionInterrupted
        }
    }
}
