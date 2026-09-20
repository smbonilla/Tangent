import AVFoundation
import Speech

struct SpeechRecognitionUpdate: Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let isStable: Bool
    let isFinal: Bool
}

protocol SpeechRecognitionWindow: AnyObject {
    func append(_ buffer: AVAudioPCMBuffer)
    func endAudio()
    func cancel()
}

final class OnDeviceSpeechWindow: SpeechRecognitionWindow {
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    init(recognizer: SFSpeechRecognizer, callback: @escaping @Sendable (SpeechRecognitionUpdate?, Error?) -> Void) {
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        task = recognizer.recognitionTask(with: request) { result, error in
            let update = result.map { result in
                let segments = result.bestTranscription.segments
                return SpeechRecognitionUpdate(
                    text: result.bestTranscription.formattedString,
                    start: result.speechRecognitionMetadata?.speechStartTimestamp ?? segments.first?.timestamp ?? 0,
                    end: segments.last.map { $0.timestamp + $0.duration } ?? 0,
                    isStable: result.isFinal || result.speechRecognitionMetadata != nil,
                    isFinal: result.isFinal
                )
            }
            callback(update, error)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    func endAudio() { request.endAudio() }
    func cancel() { task?.cancel() }
}
