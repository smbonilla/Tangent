import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Tangent

struct LiveTranscriptionTests {
    @Test
    func audioBackupContainsEveryCapturedBuffer() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "audio-\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let sink = RecordingAudioSink(file: try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1
        ]), onAudioBuffer: { _ in })
        for _ in 0..<30 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
            buffer.frameLength = 1600
            buffer.floatChannelData?[0].initialize(repeating: 0, count: 1600)
            sink.append(buffer)
        }
        #expect(try sink.finish() == url)
        let recorded = try AVAudioFile(forReading: url)
        #expect(recorded.length >= 48_000)
        #expect(Double(recorded.length) / recorded.processingFormat.sampleRate < 3.2)
    }

    @Test
    func keepsEarlierUtterancesWhenSpeechResultsResetAfterPauses() {
        var transcript = SpeechTranscriptAccumulator()
        transcript.update(text: "The beginning of my day.", start: 0, end: 8, isStable: true)
        transcript.update(text: "The middle", start: 15, end: 19, isStable: false)
        transcript.update(text: "The middle of my day.", start: 15, end: 24, isStable: true)
        transcript.update(text: "The last ten seconds.", start: 70, end: 80, isStable: true)
        #expect(transcript.text == "The beginning of my day. The middle of my day. The last ten seconds.")
    }

    @Test
    func keepsEarlierSpeechWhenAnUtteranceBoundaryHasNoMetadata() {
        var transcript = SpeechTranscriptAccumulator()
        transcript.update(text: "Earlier speech.", start: 0, end: 4, isStable: false)
        transcript.update(text: "Later speech.", start: 12, end: 15, isStable: false)
        transcript.update(text: "Later speech.", start: 12, end: 15, isStable: true)
        #expect(transcript.text == "Earlier speech. Later speech.")
    }

    @Test
    func partialRevisionsAndRepeatedFinalCallbacksDoNotDuplicateSpeech() {
        var transcript = SpeechTranscriptAccumulator()
        transcript.update(text: "I walked", start: 0, end: 2, isStable: false)
        transcript.update(text: "I walked home.", start: 0, end: 3, isStable: true)
        transcript.update(text: "I walked home.", start: 0, end: 3, isStable: true)
        transcript.update(text: "I walked home.", start: 0, end: 3, isStable: false)
        #expect(transcript.text == "I walked home.")
        transcript.update(text: "Then I cooked.", start: 6, end: 8, isStable: true)
        transcript.update(text: "I walked home. Then I cooked.", start: 0, end: 8, isStable: true)
        #expect(transcript.text == "I walked home. Then I cooked.")
    }

    @Test
    func repeatedWordsInSeparateUtterancesArePreserved() {
        var transcript = SpeechTranscriptAccumulator()
        transcript.update(text: "Thank you.", start: 0, end: 1, isStable: true)
        transcript.update(text: "Thank you.", start: 5, end: 6, isStable: true)
        #expect(transcript.text == "Thank you. Thank you.")
        #expect(TranscriptWindowJoiner.join("I went to the park.", "the park was quiet.") == "I went to the park. was quiet.")
    }

    @Test
    func liveRecognitionRotatesAndKeepsTheWholeTwoMinuteRecording() async throws {
        let factory = TestSpeechFactory(texts: ["Opening thoughts at the park", "the park and the middle of my day", "my day ended well"])
        let session = LiveSpeechSession(makeWindow: factory.make)
        for _ in 0..<120 { session.append(try Self.buffer()) }
        #expect(factory.windows.count == 3)
        #expect(factory.windows.filter(\.ended).count == 2) // Transcribed before Stop.
        let result = try await session.finish()
        #expect(result == "Opening thoughts at the park and the middle of my day ended well")
        #expect(factory.windows.allSatisfy { $0.frames <= 45_000 })
        #expect(factory.windows.reduce(0) { $0 + $1.frames } == 122_000) // One-second overlaps.
    }

    @Test
    func anErrorNeverReturnsTheLastPartialTranscriptAsSuccess() async throws {
        let factory = TestSpeechFactory(texts: ["Only the last ten seconds"], behavior: .error)
        let session = LiveSpeechSession(makeWindow: factory.make)
        session.append(try Self.buffer())
        await #expect(throws: NSError.self) { try await session.finish() }
    }

    @Test
    func pendingAudioIsBoundedWhenRecognitionFallsBehind() async throws {
        let factory = TestSpeechFactory(texts: [""], behavior: .neverFinishes)
        let session = LiveSpeechSession(makeWindow: factory.make)
        for _ in 0..<65 { session.append(try Self.buffer()) }
        await #expect(throws: TranscriptionError.self) { try await session.finish() }
        #expect(factory.windows.first?.cancelled == true)
    }

    @Test
    func finalizationTimeoutAndCancellationDoNotHang() async throws {
        let factory = TestSpeechFactory(texts: [""], behavior: .neverFinishes)
        let session = LiveSpeechSession(finalizationTimeout: 0.01, makeWindow: factory.make)
        session.append(try Self.buffer())
        await #expect(throws: TranscriptionError.self) { try await session.finish() }
        let cancelled = LiveSpeechSession(makeWindow: factory.make)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.finish() }
    }

    @Test @MainActor
    func recordingFeedsSpeechBeforeStopAndSavesCompletedTranscript() async throws {
        let factory = TestSpeechFactory(texts: ["Beginning middle and end."])
        let transcriber = TestLiveTranscriber(session: LiveSpeechSession(makeWindow: factory.make))
        let recorder = TestLiveRecorder()
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        try await store.saveUserProfile(UserProfile(name: "Alex"))
        let model = RecordHomeViewModel(audioRecorder: recorder, transcriber: transcriber, noteStore: store)
        await model.startRecording()
        #expect(model.isRecording)
        #expect(factory.windows.first?.frames == 1000)
        let id = try #require(await model.stopRecording())
        let entry = try #require(await store.diaryEntry(id: id))
        defer {
            try? FileManager.default.removeItem(atPath: entry.transcriptPath)
            if let url = recorder.url { try? FileManager.default.removeItem(at: url) }
        }
        #expect(entry.transcriptPath.hasSuffix(".txt"))
        #expect(try String(contentsOfFile: entry.transcriptPath, encoding: .utf8) == "Beginning middle and end.")
        #expect(transcriber.fileRequests == 0)
        #expect(!FileManager.default.fileExists(atPath: try #require(recorder.url).path))
    }

    @Test @MainActor
    func liveFailureKeepsFullAudioForFileRecovery() async throws {
        let factory = TestSpeechFactory(texts: ["Incomplete tail"], behavior: .error)
        let transcriber = TestLiveTranscriber(session: LiveSpeechSession(makeWindow: factory.make))
        let recorder = TestLiveRecorder()
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        try await store.saveUserProfile(UserProfile(name: "Alex"))
        let model = RecordHomeViewModel(audioRecorder: recorder, transcriber: transcriber, noteStore: store)
        await model.startRecording()
        let id = try #require(await model.stopRecording())
        let entry = try #require(await store.diaryEntry(id: id))
        defer { try? FileManager.default.removeItem(atPath: entry.transcriptPath) }
        #expect(entry.transcriptPath == recorder.url?.path)
        #expect(FileManager.default.fileExists(atPath: entry.transcriptPath))
        #expect(!entry.transcriptPath.hasSuffix(".txt"))
    }

    fileprivate static func buffer() throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 1000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1000))
        buffer.frameLength = 1000
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 1000)
        return buffer
    }
}

private final class TestSpeechFactory: @unchecked Sendable {
    enum Behavior { case final, error, neverFinishes }
    private let lock = NSLock()
    private var storage: [TestSpeechWindow] = []
    private let texts: [String]
    private let behavior: Behavior
    var windows: [TestSpeechWindow] { lock.withLock { storage } }

    init(texts: [String], behavior: Behavior = .final) {
        self.texts = texts
        self.behavior = behavior
    }

    func make(callback: @escaping @Sendable (SpeechRecognitionUpdate?, Error?) -> Void) -> any SpeechRecognitionWindow {
        lock.withLock {
            let text = texts[min(storage.count, texts.count - 1)]
            let window = TestSpeechWindow(text: text, behavior: behavior, callback: callback)
            storage.append(window)
            return window
        }
    }
}

private final class TestSpeechWindow: SpeechRecognitionWindow, @unchecked Sendable {
    private let lock = NSLock()
    private var frameCount = 0
    private var didEnd = false
    private var didCancel = false
    var frames: Int { lock.withLock { frameCount } }
    var ended: Bool { lock.withLock { didEnd } }
    var cancelled: Bool { lock.withLock { didCancel } }
    let text: String
    let behavior: TestSpeechFactory.Behavior
    let callback: @Sendable (SpeechRecognitionUpdate?, Error?) -> Void

    init(text: String, behavior: TestSpeechFactory.Behavior, callback: @escaping @Sendable (SpeechRecognitionUpdate?, Error?) -> Void) {
        self.text = text
        self.behavior = behavior
        self.callback = callback
    }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { frameCount += Int(buffer.frameLength) } }
    func endAudio() {
        lock.withLock { didEnd = true }
        guard behavior != .neverFinishes else { return }
        callback(SpeechRecognitionUpdate(text: text, start: 0, end: 10, isStable: true, isFinal: behavior == .final), nil)
        if behavior == .error { callback(nil, NSError(domain: "TestSpeechFailure", code: 1)) }
    }
    func cancel() { lock.withLock { didCancel = true } }
}

private final class TestLiveRecorder: LiveAudioRecorder {
    var url: URL?
    func startRecording(to destination: URL) async throws {
        try await startRecording(to: destination, onAudioBuffer: { _ in })
    }
    func startRecording(to destination: URL, onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        url = destination
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Full audio backup".utf8).write(to: destination)
        onAudioBuffer(try LiveTranscriptionTests.buffer())
    }
    func stopRecording() async throws -> URL { try #require(url) }
    func cancelRecording() async {}
}

private final class TestLiveTranscriber: LiveTranscriber {
    let session: any LiveTranscriptionSession
    var fileRequests = 0
    init(session: any LiveTranscriptionSession) { self.session = session }
    func startLiveTranscription() async throws -> any LiveTranscriptionSession { session }
    func transcribe(audioAt url: URL) async throws -> String { fileRequests += 1; return "Recovered full audio" }
    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
