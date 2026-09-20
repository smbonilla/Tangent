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

/// One engine tap writes the full AAC backup and feeds on-device recognition.
/// No second microphone capture competes with the recording session.
final class AVAudioRecorderService: LiveAudioRecorder {
    private var engine: AVAudioEngine?
    private var sink: RecordingAudioSink?

    func startRecording(to destination: URL) async throws {
        try await startRecording(to: destination, onAudioBuffer: { _ in })
    }

    func startRecording(
        to destination: URL,
        onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) async throws {
        guard engine == nil else { throw AudioRecordingError.failedToStart }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AudioRecordingError.microphonePermissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
        let engine = AVAudioEngine()
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw AudioRecordingError.failedToStart
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let file = try AVAudioFile(
                forWriting: destination,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ],
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            let sink = RecordingAudioSink(file: file, onAudioBuffer: onAudioBuffer)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                sink.append(buffer)
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.sink = sink
        } catch {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            deactivateSession()
            throw error
        }
    }

    func stopRecording() async throws -> URL {
        guard let engine, let sink else { throw AudioRecordingError.notRecording }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        self.sink = nil
        defer { deactivateSession() }
        return try sink.finish()
    }

    func cancelRecording() async {
        guard let sink else { return }
        let url = sink.url
        _ = try? await stopRecording()
        try? FileManager.default.removeItem(at: url)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

final class RecordingAudioSink: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "Tangent.recording-audio")
    private var file: AVAudioFile?
    private var failure: Error?
    private let onAudioBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(file: AVAudioFile, onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.file = file
        url = file.url
        self.onAudioBuffer = onAudioBuffer
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // Engine tap buffers are reused. Own the samples before leaving the tap;
        // disk encoding and speech recognition run off the audio render thread.
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            queue.async { self.failure = AudioRecordingError.failedToStart }
            return
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (source, destination) in zip(source, destination) {
            if let from = source.mData, let to = destination.mData {
                memcpy(to, from, Int(source.mDataByteSize))
            }
        }
        queue.async {
            guard let file = self.file, self.failure == nil else { return }
            do {
                try file.write(from: copy)
                self.onAudioBuffer(copy)
            } catch {
                self.failure = error
            }
        }
    }

    func finish() throws -> URL {
        try queue.sync {
            file = nil // Flush and close AAC before handing it to file recovery.
            if let failure { throw failure }
            return url
        }
    }
}
