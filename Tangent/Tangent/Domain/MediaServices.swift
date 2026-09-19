import Foundation

protocol AudioRecorder: AnyObject {
    func startRecording(to destination: URL) async throws
    func stopRecording() async throws -> URL
    func cancelRecording() async
}

protocol Transcriber: AnyObject {
    func transcribe(audioAt url: URL) async throws -> String
    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error>
}
