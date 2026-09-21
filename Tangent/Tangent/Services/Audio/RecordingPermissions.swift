import AVFoundation

/// SpeechAnalyzer processes audio on device and needs no legacy Speech
/// Recognition authorization. Only microphone capture requires permission.
enum RecordingPermissions {
    @MainActor
    static func requestIfNeeded() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}
