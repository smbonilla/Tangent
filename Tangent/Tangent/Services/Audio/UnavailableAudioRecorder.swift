import Foundation

enum AudioRecorderError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "Audio recording is not implemented yet."
    }
}

final class UnavailableAudioRecorder: AudioRecorder {
    func startRecording(to destination: URL) async throws {
        throw AudioRecorderError.notImplemented
    }

    func stopRecording() async throws -> URL {
        throw AudioRecorderError.notImplemented
    }

    func cancelRecording() async {}
}
