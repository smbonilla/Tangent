import AVFoundation
import Foundation
import Speech

/// Only one recognition task runs at a time. Rotate before Speech's request
/// duration limit, buffering at most 15 seconds while the old task finalizes.
/// If recognition cannot keep up, fail explicitly and use the saved audio.
final class LiveSpeechSession: LiveTranscriptionSession, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Tangent.live-speech")
    private let makeWindow: (@escaping @Sendable (SpeechRecognitionUpdate?, Error?) -> Void) -> any SpeechRecognitionWindow
    private let onPartial: @Sendable (String) -> Void
    private let finalizationTimeout: TimeInterval
    private let windowDuration: TimeInterval
    private var request: (any SpeechRecognitionWindow)?
    private var timeout: DispatchWorkItem?
    private var accumulator = SpeechTranscriptAccumulator()
    private var completedText = ""
    private var windowSeconds: TimeInterval = 0
    private var tail: [AVAudioPCMBuffer] = []
    private var tailSeconds: TimeInterval = 0
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingSeconds: TimeInterval = 0
    private var hasPendingNewAudio = false
    private var closing = false
    private var finishing = false
    private var failure: Error?
    private var result: String?
    private var completion: CheckedContinuation<String, Error>?
    private var generation = 0

    convenience init(recognizer: SFSpeechRecognizer, finalizationTimeout: TimeInterval = 15, onPartial: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(finalizationTimeout: finalizationTimeout, onPartial: onPartial) { callback in
            OnDeviceSpeechWindow(recognizer: recognizer, callback: callback)
        }
    }

    init(
        windowDuration: TimeInterval = 45,
        finalizationTimeout: TimeInterval = 15,
        onPartial: @escaping @Sendable (String) -> Void = { _ in },
        makeWindow: @escaping (@escaping @Sendable (SpeechRecognitionUpdate?, Error?) -> Void) -> any SpeechRecognitionWindow
    ) {
        self.onPartial = onPartial
        self.windowDuration = windowDuration
        self.finalizationTimeout = finalizationTimeout
        self.makeWindow = makeWindow
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            guard !finishing, failure == nil, result == nil else { return }
            if closing {
                pending.append(buffer)
                pendingSeconds += duration(buffer)
                hasPendingNewAudio = true
                if pendingSeconds > 15 { fail(TranscriptionError.recognitionFellBehind) }
            } else {
                if request == nil { beginWindow() }
                feed(buffer)
            }
        }
    }

    func finish() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let failure = self.failure {
                        continuation.resume(throwing: failure)
                    } else if let result = self.result {
                        continuation.resume(returning: result)
                    } else {
                        guard self.completion == nil else {
                            continuation.resume(throwing: TranscriptionError.recognitionInterrupted)
                            return
                        }
                        self.completion = continuation
                        self.finishing = true
                        if self.request != nil { self.closeWindow() }
                        else { self.complete() }
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        queue.async { self.fail(CancellationError()) }
    }

    private func beginWindow() {
        generation += 1
        let currentGeneration = generation
        accumulator = SpeechTranscriptAccumulator()
        windowSeconds = 0
        tail = []
        tailSeconds = 0
        closing = false
        request = makeWindow { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard self.generation == currentGeneration, self.failure == nil,
                      self.request != nil else { return }
                if let result {
                    self.accumulator.update(
                        text: result.text, start: result.start, end: result.end,
                        isStable: result.isStable
                    )
                    self.onPartial(TranscriptWindowJoiner.join(self.completedText, self.accumulator.text))
                    if result.isFinal {
                        // An unsolicited final result could have ignored audio
                        // still arriving. Never publish it as a complete diary.
                        guard self.closing else {
                            self.fail(TranscriptionError.recognitionInterrupted)
                            return
                        }
                        self.finishWindow()
                        return
                    }
                }
                if let error {
                    let nsError = error as NSError
                    if self.closing, nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110,
                       self.accumulator.text.isEmpty {
                        self.finishWindow() // A window containing only silence.
                    } else {
                        self.fail(error)
                    }
                }
            }
        }
    }

    private func feed(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
        let seconds = duration(buffer)
        windowSeconds += seconds
        tail.append(buffer)
        tailSeconds += seconds
        while tail.count > 1, tailSeconds - duration(tail[0]) >= 1 {
            tailSeconds -= duration(tail.removeFirst())
        }
        if windowSeconds >= windowDuration { closeWindow() }
    }

    private func closeWindow() {
        guard !closing, let request else { return }
        closing = true
        pending = tail
        pendingSeconds = tailSeconds
        hasPendingNewAudio = false
        request.endAudio()
        let timeout = DispatchWorkItem { [weak self] in
            self?.fail(TranscriptionError.recognitionTimedOut)
        }
        self.timeout = timeout
        queue.asyncAfter(deadline: .now() + finalizationTimeout, execute: timeout)
    }

    private func finishWindow() {
        timeout?.cancel()
        timeout = nil
        completedText = TranscriptWindowJoiner.join(completedText, accumulator.text)
        request = nil
        closing = false
        if finishing && !hasPendingNewAudio {
            complete()
            return
        }
        let buffered = pending
        pending = []
        pendingSeconds = 0
        hasPendingNewAudio = false
        beginWindow()
        for buffer in buffered { feed(buffer) }
        if finishing { closeWindow() }
    }

    private func complete() {
        result = completedText
        pending = []
        tail = []
        completion?.resume(returning: completedText)
        completion = nil
    }

    private func fail(_ error: Error) {
        guard failure == nil, result == nil else { return }
        failure = error
        timeout?.cancel()
        timeout = nil
        request?.cancel()
        request = nil
        pending = []
        tail = []
        completion?.resume(throwing: error)
        completion = nil
    }

    private func duration(_ buffer: AVAudioPCMBuffer) -> TimeInterval {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }
}
