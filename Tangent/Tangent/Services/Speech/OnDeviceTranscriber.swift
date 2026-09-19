import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case speechPermissionDenied
    case recognizerUnavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Tangent needs speech recognition access to transcribe on this device. Enable it in Settings."
        case .recognizerUnavailable:
            return "On-device transcription is not available on this device."
        case .emptyTranscript:
            return "No speech was detected in the recording."
        }
    }
}

/// Transcribes recorded audio with Apple's on-device speech recognizer.
///
/// `requiresOnDeviceRecognition` is always set, so the request fails rather
/// than uploading audio to Apple's servers. Nothing is sent off the device.
final class OnDeviceTranscriber: Transcriber {
    func transcribe(audioAt url: URL) async throws -> String {
        try await requestAuthorization()
        let recognizer = try makeOnDeviceRecognizer()

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        let state = RecognitionState()

        return try await withCheckedThrowingContinuation { continuation in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    state.update(result.bestTranscription.formattedString)
                    if result.isFinal {
                        state.resumeOnce { transcript in
                            if transcript.isEmpty {
                                continuation.resume(throwing: TranscriptionError.emptyTranscript)
                            } else {
                                continuation.resume(returning: transcript)
                            }
                        }
                    }
                } else if let error {
                    state.resumeOnce { transcript in
                        if transcript.isEmpty {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: transcript)
                        }
                    }
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(90))
                state.resumeOnce { transcript in
                    task.cancel()
                    if transcript.isEmpty {
                        continuation.resume(throwing: TranscriptionError.emptyTranscript)
                    } else {
                        continuation.resume(returning: transcript)
                    }
                }
            }
        }
    }

    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await self.transcribe(audioAt: url)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeOnDeviceRecognizer() throws -> SFSpeechRecognizer {
        let candidates = [Locale.autoupdatingCurrent, Locale(identifier: "en-US")]
        for locale in candidates {
            guard
                let recognizer = SFSpeechRecognizer(locale: locale),
                recognizer.isAvailable,
                recognizer.supportsOnDeviceRecognition
            else {
                continue
            }
            return recognizer
        }
        throw TranscriptionError.recognizerUnavailable
    }

    private func requestAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw TranscriptionError.speechPermissionDenied
        }
    }
}

private final class RecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTranscript = ""
    private var hasResumed = false

    func update(_ text: String) {
        lock.lock()
        lastTranscript = text
        lock.unlock()
    }

    func resumeOnce(_ resume: (String) -> Void) {
        lock.lock()
        let alreadyResumed = hasResumed
        let transcript = lastTranscript
        if !alreadyResumed {
            hasResumed = true
        }
        lock.unlock()
        guard !alreadyResumed else { return }
        resume(transcript)
    }
}
