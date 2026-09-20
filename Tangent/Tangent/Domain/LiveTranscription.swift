import AVFoundation
import Foundation

/// A single microphone capture supplies both the saved audio and recognition.
protocol LiveAudioRecorder: AudioRecorder {
    func startRecording(
        to destination: URL,
        onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) async throws
}

protocol LiveTranscriber: Transcriber {
    func startLiveTranscription() async throws -> any LiveTranscriptionSession
}

protocol LiveTranscriptionSession: AnyObject, Sendable {
    /// The caller supplies an owned buffer, not a reused audio-engine tap buffer.
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String
    func cancel()
}
