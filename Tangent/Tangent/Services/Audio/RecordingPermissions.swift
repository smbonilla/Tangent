import AVFoundation
import Speech

/// Asks for microphone and on-device speech access as soon as Tangent is
/// usable, so the first recording can transcribe without waiting on a prompt.
enum RecordingPermissions {
    @MainActor
    static func requestIfNeeded() async {
        _ = await AVAudioApplication.requestRecordPermission()
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }
    }
}
