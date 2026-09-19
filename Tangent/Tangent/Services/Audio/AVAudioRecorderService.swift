import AVFoundation
import Foundation

enum AudioRecordingError: LocalizedError {
    case microphonePermissionDenied
    case failedToStart
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Tangent needs microphone access to record. Enable it in Settings."
        case .failedToStart:
            return "The recording could not be started."
        case .notRecording:
            return "There is no recording in progress."
        }
    }
}

/// Records mono AAC audio to a file using AVAudioRecorder.
final class AVAudioRecorderService: AudioRecorder {
    private var recorder: AVAudioRecorder?

    func startRecording(to destination: URL) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AudioRecordingError.microphonePermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: destination, settings: settings)
        guard recorder.record() else {
            throw AudioRecordingError.failedToStart
        }
        self.recorder = recorder
    }

    func stopRecording() async throws -> URL {
        guard let recorder else {
            throw AudioRecordingError.notRecording
        }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        deactivateSession()
        return url
    }

    func cancelRecording() async {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        deactivateSession()
        try? FileManager.default.removeItem(at: url)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
