import AVFoundation
import Foundation
import Speech
import SwiftData
import Testing
@testable import Tangent

struct LiveTranscriptionTests {
    @Test
    func finalizedSegmentsKeepTheWholeRecordingAcrossPausesAndRepetition() {
        var transcript = SpeechTranscriptAccumulator()
        for text in ["The beginning.", "", " Much later.", " Thank you.", " Thank you."] {
            transcript.appendFinal(text)
        }
        #expect(transcript.text == "The beginning. Much later. Thank you. Thank you.")
    }

    @Test
    func audioBackupContainsEveryAcceptedBuffer() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "audio-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = RecordingAudioSink(file: try Self.file(url), onAudioBuffer: { _ in })
        for _ in 0..<30 { sink.append(try Self.buffer()) }
        #expect(try await sink.finishRecording() == url)
        #expect(try AVAudioFile(forReading: url).length == 30_000)
    }

    @Test
    func audioBackupOwnsItsCopyBeforeTheMicrophoneReusesTheBuffer() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "audio-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DispatchQueue(label: "Tangent.tests.buffer-ownership")
        let sink = RecordingAudioSink(file: try Self.file(url), queue: queue, onAudioBuffer: { _ in })
        let buffer = try Self.buffer()
        queue.suspend()
        buffer.floatChannelData?[0].update(repeating: 0.25, count: 1000)
        sink.append(buffer)
        buffer.floatChannelData?[0].update(repeating: -0.5, count: 1000)
        queue.resume()
        _ = try await sink.finishRecording()
        let file = try AVAudioFile(forReading: url)
        let saved = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1000))
        try file.read(into: saved)
        #expect(saved.frameLength == 1000)
        let samples = try #require(saved.floatChannelData?[0])
        #expect((0..<1000).allSatisfy { abs(samples[$0] - 0.25) < 0.0001 })
    }

    @Test
    func cafBackupRemainsReadableWithoutNormalClose() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = directory.appending(path: "live.caf")
        let interrupted = directory.appending(path: "interrupted.caf")
        let writer = try Self.file(recording)
        for _ in 0..<30 { try writer.write(from: Self.buffer()) }
        // Snapshot the bytes before the writer's destructor finalizes the file.
        try FileManager.default.copyItem(at: recording, to: interrupted)
        withExtendedLifetime(writer) {
            #expect(FileManager.default.fileExists(atPath: interrupted.path))
        }
        let recovered = try AVAudioFile(forReading: interrupted)
        #expect(recovered.length == 30_000)
    }

    @Test
    func checkpointsAppendUnicodeAndReplaceRecoveryRevisions() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "checkpoint-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let checkpoint = TranscriptCheckpoint(url: url)
        try checkpoint.save("First café.")
        try checkpoint.save("First café. Later 👋.")
        try checkpoint.save("First café. Later 👋.")
        #expect(try String(contentsOf: url, encoding: .utf8) == "First café. Later 👋.")
        try checkpoint.save("Recovered complete text.")
        #expect(try String(contentsOf: url, encoding: .utf8) == "Recovered complete text.")
    }

    @Test
    func stalledWriterHasABoundedQueueAndDrainsAcceptedAudio() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "audio-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DispatchQueue(label: "Tangent.tests.stalled-writer")
        queue.suspend()
        let sink = RecordingAudioSink(file: try Self.file(url), maximumPendingBuffers: 2,
                                      queue: queue, onAudioBuffer: { _ in })
        let buffer = try Self.buffer()
        sink.append(buffer)
        sink.append(buffer)
        for _ in 0..<1000 { sink.append(buffer) }
        queue.resume()
        await #expect(throws: AudioRecordingError.self) { try await sink.finishRecording() }
        #expect(try AVAudioFile(forReading: url).length == 2000)
    }

    @Test
    func converterFlushPreservesAllSamples() throws {
        let sourceFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let targetFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = SpeechAudioConverter(analyzerFormat: targetFormat)
        var seconds = 0.0
        for _ in 0..<100 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 480))
            buffer.frameLength = 480
            buffer.floatChannelData?[0].initialize(repeating: 0.25, count: 480)
            for input in try converter.convert(buffer) {
                seconds += Double(input.buffer.frameLength) / input.buffer.format.sampleRate
            }
        }
        for input in try converter.flush() {
            seconds += Double(input.buffer.frameLength) / input.buffer.format.sampleRate
        }
        #expect(abs(seconds - 1) < 0.002)
        #expect(try converter.flush().isEmpty)
    }

    @Test @MainActor
    func interruptedRecordingRecoveryIsDurableAndIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let profile = UserProfile(name: "Alex")
        try await store.saveUserProfile(profile)
        let pending = PendingRecording(id: UUID(), profileID: profile.id,
            day: Date().addingTimeInterval(-86400), startedAt: Date(),
            audioPath: directory.appending(path: "recording.caf").path)
        try pending.save()
        try Data("Saved audio".utf8).write(to: pending.audioURL)
        let loaded = try #require(PendingRecording.loadAll(directory: directory).first)
        try await loaded.recover(in: store)
        try await loaded.recover(in: store)
        let entry = try #require(await store.diaryEntry(id: pending.id))
        #expect(entry.transcriptPath == pending.audioPath)
        #expect(entry.day == pending.day)
        #expect(entry.recordingStartedAt == pending.startedAt)
        #expect(FileManager.default.fileExists(atPath: pending.audioURL.path))
        #expect(!FileManager.default.fileExists(atPath: pending.journalURL.path))
    }

    @Test @MainActor
    func recordingFeedsSpeechBeforeStopAndSavesCompletedTranscript() async throws {
        let session = TestLiveSession(text: "Beginning middle and end.")
        let transcriber = TestLiveTranscriber(session: session)
        let recorder = TestLiveRecorder()
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        try await store.saveUserProfile(UserProfile(name: "Alex"))
        let model = RecordHomeViewModel(audioRecorder: recorder, transcriber: transcriber, noteStore: store)
        let pastDay = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400 * 3))
        model.entryDay = pastDay
        let beforeStart = Date()
        await model.startRecording()
        let afterStart = Date()
        #expect(model.isRecording)
        #expect(session.frames == 1000)
        transcriber.onPartial?("Beginning middle")
        let checkpoint = TranscriptFiles.checkpointURL(for: try #require(recorder.url))
        #expect(try String(contentsOf: checkpoint, encoding: .utf8) == "Beginning middle")
        let id = try #require(await model.stopRecording())
        let entry = try #require(await store.diaryEntry(id: id))
        defer {
            try? FileManager.default.removeItem(at: TranscriptFiles.url(for: entry.transcriptPath))
            if let url = recorder.url { try? FileManager.default.removeItem(at: url) }
        }
        let startedAt = try #require(entry.recordingStartedAt)
        #expect(startedAt >= beforeStart && startedAt <= afterStart)
        #expect(entry.transcriptPath.hasSuffix(".txt"))
        #expect(try String(contentsOf: TranscriptFiles.url(for: entry.transcriptPath), encoding: .utf8) == "Beginning middle and end.")
        #expect(transcriber.fileRequests == 0)
        let reopened = DailyTangentDetailsViewModel(noteStore: store, diaryID: id)
        await reopened.start()
        #expect(reopened.entry?.day == pastDay)
        #expect(reopened.transcript == "Beginning middle and end.")
        #expect(!FileManager.default.fileExists(atPath: try #require(recorder.url).path))
    }

    @Test @MainActor
    func liveFailureKeepsFullAudioForFileRecovery() async throws {
        let transcriber = TestLiveTranscriber(session: TestLiveSession(text: "Incomplete tail", fails: true))
        let recorder = TestLiveRecorder()
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        try await store.saveUserProfile(UserProfile(name: "Alex"))
        let model = RecordHomeViewModel(audioRecorder: recorder, transcriber: transcriber, noteStore: store)
        await model.startRecording()
        let id = try #require(await model.stopRecording())
        let entry = try #require(await store.diaryEntry(id: id))
        defer { try? FileManager.default.removeItem(at: TranscriptFiles.url(for: entry.transcriptPath)) }
        #expect(TranscriptFiles.url(for: entry.transcriptPath) == recorder.url)
        #expect(FileManager.default.fileExists(atPath: TranscriptFiles.url(for: entry.transcriptPath).path))
        #expect(!entry.transcriptPath.hasSuffix(".txt"))
    }

    @Test @MainActor
    func unavailableSpeechAssetsStillAllowRecordingAndFileRecovery() async throws {
        let recorder = TestLiveRecorder()
        let transcriber = TestLiveTranscriber(session: TestLiveSession(text: "Unused"))
        transcriber.failsStart = true
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        try await store.saveUserProfile(UserProfile(name: "Alex"))
        let model = RecordHomeViewModel(audioRecorder: recorder, transcriber: transcriber, noteStore: store)
        await model.startRecording()
        #expect(model.isRecording)
        let id = try #require(await model.stopRecording())
        let entry = try #require(await store.diaryEntry(id: id))
        let audio = TranscriptFiles.url(for: entry.transcriptPath)
        defer { try? FileManager.default.removeItem(at: audio) }
        #expect(audio == recorder.url)
        #expect(FileManager.default.fileExists(atPath: audio.path))
        #expect(!FileManager.default.fileExists(atPath: audio.appendingPathExtension("json").path))
    }

    @Test @MainActor
    func writerFailureStillSavesTheAudioPrefixAsARecoverableEntry() async throws {
        let recorder = TestLiveRecorder()
        recorder.failsStop = true
        let transcriber = TestLiveTranscriber(session: TestLiveSession(text: "Incomplete"))
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        try await store.saveUserProfile(UserProfile(name: "Alex"))
        let model = RecordHomeViewModel(audioRecorder: recorder, transcriber: transcriber, noteStore: store)
        await model.startRecording()
        #expect(await model.stopRecording() == nil)
        guard case .failed = model.phase else { Issue.record("Expected a visible recording error"); return }
        let entry = try #require(await store.diaryEntries(profileID: nil).first)
        let audio = TranscriptFiles.url(for: entry.transcriptPath)
        defer { try? FileManager.default.removeItem(at: audio) }
        #expect(audio == recorder.url)
        #expect(try String(contentsOf: audio, encoding: .utf8) == "Full audio backup")
        #expect(!entry.transcriptPath.hasSuffix(".txt"))
    }

    private static func file(_ url: URL) throws -> AVAudioFile {
        try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 1000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
    }

    fileprivate static func buffer() throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 1000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1000))
        buffer.frameLength = 1000
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 1000)
        return buffer
    }
}

private final class TestLiveSession: LiveTranscriptionSession, @unchecked Sendable {
    private let lock = NSLock()
    private var frameCount = 0
    var frames: Int { lock.withLock { frameCount } }
    let text: String
    let fails: Bool
    init(text: String, fails: Bool = false) { self.text = text; self.fails = fails }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { frameCount += Int(buffer.frameLength) } }
    func finish() async throws -> String {
        if fails { throw TranscriptionError.recognitionInterrupted }
        return text
    }
    func cancel() {}
}

private final class TestLiveRecorder: LiveAudioRecorder {
    var onRecordingFailure: (@Sendable (Error) -> Void)?
    var url: URL?
    var failsStop = false
    func startRecording(to destination: URL) async throws {
        try await startRecording(to: destination, onAudioBuffer: { _ in })
    }
    func startRecording(to destination: URL, onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        url = destination
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Full audio backup".utf8).write(to: destination)
        onAudioBuffer(try LiveTranscriptionTests.buffer())
    }
    func stopRecording() async throws -> URL {
        if failsStop { throw AudioRecordingError.writerFellBehind }
        return try #require(url)
    }
    func cancelRecording() async {}
}

private final class TestLiveTranscriber: LiveTranscriber {
    let session: any LiveTranscriptionSession
    var fileRequests = 0
    var failsStart = false
    var onPartial: (@Sendable (String) -> Void)?
    init(session: any LiveTranscriptionSession) { self.session = session }
    func startLiveTranscription(onPartial: @escaping @Sendable (String) -> Void) async throws -> any LiveTranscriptionSession {
        self.onPartial = onPartial
        if failsStart { throw TranscriptionError.recognizerUnavailable }
        return session
    }
    func transcribe(audioAt url: URL) async throws -> String { fileRequests += 1; return "Recovered full audio" }
    func transcribeStreaming(audioAt url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
