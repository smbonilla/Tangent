import AVFoundation
import Foundation

enum AudioRecordingError: LocalizedError {
    case microphonePermissionDenied
    case failedToStart
    case notRecording
    case writerFellBehind
    case interrupted

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Tangent needs microphone access to record. Enable it in Settings."
        case .failedToStart:
            return "The recording could not be started."
        case .notRecording:
            return "There is no recording in progress."
        case .writerFellBehind:
            return "Recording stopped because audio could not be saved quickly enough. The audio saved so far has been kept."
        case .interrupted:
            return "Recording was interrupted. The audio saved so far has been kept."
        }
    }
}

/// One microphone capture supplies the disk backup and SpeechAnalyzer.
final class AVAudioRecorderService: LiveAudioRecorder {
    var onRecordingFailure: (@Sendable (Error) -> Void)?
    private var engine: AVAudioEngine?
    private var isStarting = false
    private var sink: RecordingAudioSink?
    private var observers: [NSObjectProtocol] = []

    func startRecording(to destination: URL) async throws {
        try await startRecording(to: destination, onAudioBuffer: { _ in })
    }

    func startRecording(to destination: URL, onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        guard engine == nil, !isStarting else { throw AudioRecordingError.failedToStart }
        isStarting = true
        defer { isStarting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AudioRecordingError.microphonePermissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        if session.maximumInputNumberOfChannels > 1 {
            try? session.setPreferredInputNumberOfChannels(1)
        }
        let engine = AVAudioEngine()
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioRecordingError.failedToStart }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // CAF + PCM remains readable after an interrupted capture, without
            // an MP4 index that only becomes valid when the recording closes.
            // Int16 keeps disk use half that of float PCM, with no quality loss
            // material to speech. Audio is removed only after transcript commit.
            let file = try AVAudioFile(forWriting: destination, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            let onFailure = onRecordingFailure ?? { _ in }
            let sink = RecordingAudioSink(file: file, onAudioBuffer: onAudioBuffer, onFailure: onFailure)
            try input.installAudioTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.1), format: format) { buffer, _ in sink.append(buffer) }
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.sink = sink
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: nil) { _ in
                    onFailure(AudioRecordingError.interrupted)
                },
                center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
                    onFailure(AudioRecordingError.interrupted)
                },
                center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { _ in
                    onFailure(AudioRecordingError.interrupted)
                }
            ]
        } catch {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            deactivateSession()
            throw error
        }
    }

    func stopRecording() async throws -> URL {
        guard let engine, let sink else { throw AudioRecordingError.notRecording }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        self.sink = nil
        defer { deactivateSession() }
        return try await sink.finishRecording()
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

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        engine?.stop()
    }
}

final class RecordingAudioSink: @unchecked Sendable {
    let url: URL
    private let queue: DispatchQueue
    private let slots: DispatchSemaphore
    private let lock = NSLock()
    private var failure: Error?
    private var accepting = true
    private var file: AVAudioFile?
    private var writeFailed = false // Confined to the writer queue.
    private let onAudioBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let onFailure: @Sendable (Error) -> Void

    init(file: AVAudioFile, maximumPendingBuffers: Int = 64,
         queue: DispatchQueue = DispatchQueue(label: "Tangent.recording-audio"),
         onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
         onFailure: @escaping @Sendable (Error) -> Void = { _ in }) {
        precondition(maximumPendingBuffers > 0)
        self.file = file
        self.queue = queue
        slots = DispatchSemaphore(value: maximumPendingBuffers)
        url = file.url
        self.onAudioBuffer = onAudioBuffer
        self.onFailure = onFailure
    }

    func append(_ buffer: AVReadOnlyAudioPCMBuffer) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        // iOS 27 supplies immutable Sendable buffers. Retain at most the fixed
        // slot count, and do all mutable copying and I/O on the writer queue.
        guard buffer.frameCapacity <= 16_384, buffer.format.channelCount <= 8,
              slots.wait(timeout: .now()) == .success else {
            let error = AudioRecordingError.writerFellBehind
            accepting = false
            failure = error
            lock.unlock()
            onFailure(error)
            return
        }
        // Admission and enqueue are atomic with respect to Stop, so its drain
        // cannot overtake a buffer we have already accepted.
        queue.async {
            defer { self.slots.signal() }
            guard let file = self.file, !self.writeFailed else { return }
            do {
                let copy = AVAudioPCMBuffer(copying: buffer)
                // Drain already accepted buffers even after an overflow. Every
                // successfully saved frame remains available for file recovery.
                try file.write(from: copy)
                self.onAudioBuffer(copy)
            } catch {
                self.writeFailed = true
                self.fail(error)
            }
        }
        lock.unlock()
    }

    private func fail(_ error: Error) {
        let first = lock.withLock {
            accepting = false
            guard failure == nil else { return false }
            failure = error
            return true
        }
        if first { onFailure(error) }
    }

    func finishRecording() async throws -> URL {
        lock.withLock { accepting = false }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.file = nil
                if let error = self.lock.withLock({ self.failure }) { continuation.resume(throwing: error) }
                else { continuation.resume(returning: self.url) }
            }
        }
    }
}
