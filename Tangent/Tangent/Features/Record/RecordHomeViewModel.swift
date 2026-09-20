import Foundation

@MainActor
final class RecordHomeViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentPromptQuestion: String?
    @Published private(set) var promptedQuestions: [DiaryQuestion] = []
    @Published private(set) var showsQuestionSuggestionOffer = false

    private let audioRecorder: any AudioRecorder
    private let transcriber: any Transcriber
    private let noteStore: any NoteStore
    private let languageModel: (any DiaryLanguageModel)?
    var entryDay: Date?
    private var elapsedTask: Task<Void, Never>?
    private var questionTask: Task<Void, Never>?
    private var suggestionOfferTask: Task<Void, Never>?
    private var isFinishing = false
    private let initialQuestionDelay: Duration
    private let questionInterval: Duration
    private let questionTransitionDelay: Duration

    init(
        audioRecorder: any AudioRecorder,
        transcriber: any Transcriber,
        noteStore: any NoteStore,
        languageModel: (any DiaryLanguageModel)? = nil,
        initialQuestionDelay: Duration = .seconds(3),
        questionInterval: Duration = .seconds(10),
        questionTransitionDelay: Duration = .milliseconds(2200)
    ) {
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.noteStore = noteStore
        self.languageModel = languageModel
        self.initialQuestionDelay = initialQuestionDelay
        self.questionInterval = questionInterval
        self.questionTransitionDelay = questionTransitionDelay
    }

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { isRecording || isFinishing }

    var formattedElapsed: String {
        let total = max(0, Int(elapsed))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startRecording() async {
        guard !isBusy else { return }
        switch phase {
        case .idle, .failed:
            break
        case .recording:
            return
        }

        do {
            try await audioRecorder.startRecording(to: Self.newRecordingDestination())
            elapsed = 0
            promptedQuestions = []
            currentPromptQuestion = nil
            showsQuestionSuggestionOffer = false
            phase = .recording
            startElapsedTimer()
            scheduleQuestionSuggestionOffer()

            // Warm the model while the user talks. By the time they stop and
            // the transcript is ready, the weights are already in memory.
            if let languageModel {
                Task.detached(priority: .utility) {
                    await languageModel.prepare()
                }
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    /// Stops the recording, saves the diary entry for `entryDay` (or now),
    /// and returns its id. The record screen returns to idle immediately so no
    /// transcribing UI is shown.
    func stopRecording() async -> UUID? {
        guard phase == .recording, !isFinishing else { return nil }
        isFinishing = true
        stopElapsedTimer()
        stopSuggestionOffer()
        stopQuestionStream()
        phase = .idle
        defer { isFinishing = false }

        do {
            let recordingURL = try await audioRecorder.stopRecording()
            return try await saveEntry(
                day: entryDay ?? Date(),
                transcriptPath: recordingURL.path,
                questions: promptedQuestions
            )
        } catch {
            phase = .failed(message: error.localizedDescription)
            return nil
        }
    }

    deinit {
        elapsedTask?.cancel()
        questionTask?.cancel()
        suggestionOfferTask?.cancel()
    }

    func acceptQuestionSuggestions() async {
        guard isRecording, showsQuestionSuggestionOffer else { return }
        stopSuggestionOffer()
        await startQuestionStream()
    }

    /// Saves the entry with the audio path and the questions the user was
    /// actually shown. The transcript and short summary are filled in on the
    /// daily details screen.
    func saveEntry(
        day: Date,
        transcriptPath: String,
        questions: [DiaryQuestion],
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> UUID {
        guard let user = try await noteStore.userProfiles().first else {
            throw RecordPersistenceError.missingProfile
        }

        let existing = try await noteStore.diaryEntries(profileID: user.id)
            .filter { calendar.isDate($0.day, inSameDayAs: day) }
        let id = existing.first?.id ?? UUID()
        for old in existing where old.id != id {
            try await noteStore.deleteDiaryEntry(id: old.id)
        }

        let entry = DiaryEntry(
            id: id,
            profileID: user.id,
            day: day,
            questions: questions,
            promptText: "Daily Tangent recorded and transcribed on device",
            transcriptPath: transcriptPath
        )
        try await noteStore.saveDiaryEntry(entry)
        return entry.id
    }

    nonisolated static func writeTranscript(
        _ transcript: String,
        directory: URL = URL.documentsDirectory
            .appending(path: "Transcripts", directoryHint: .isDirectory)
    ) throws -> String {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "tangent-\(UUID().uuidString).txt")
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        let startedAt = Date()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private func startQuestionStream() async {
        guard let profileID = try? await noteStore.userProfiles().first?.id,
              let questions = try? await noteStore.questions(profileID: profileID),
              !questions.isEmpty,
              isRecording
        else {
            return
        }

        let shuffledQuestions = questions.shuffled()
        questionTask?.cancel()
        questionTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: questionTransitionDelay)

            for question in shuffledQuestions {
                guard !Task.isCancelled, isRecording else { return }
                currentPromptQuestion = question.text
                if !promptedQuestions.contains(where: { $0.id == question.id }) {
                    promptedQuestions.append(
                        DiaryQuestion(id: question.id, text: question.text)
                    )
                }
                try? await Task.sleep(for: questionInterval)
                guard !Task.isCancelled, isRecording else { return }
                currentPromptQuestion = nil
                try? await Task.sleep(for: questionTransitionDelay)
            }
        }
    }

    private func stopQuestionStream() {
        questionTask?.cancel()
        questionTask = nil
        currentPromptQuestion = nil
    }

    private func scheduleQuestionSuggestionOffer() {
        suggestionOfferTask?.cancel()
        suggestionOfferTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: initialQuestionDelay)
            guard !Task.isCancelled, isRecording else { return }
            showsQuestionSuggestionOffer = true
        }
    }

    private func stopSuggestionOffer() {
        suggestionOfferTask?.cancel()
        suggestionOfferTask = nil
        showsQuestionSuggestionOffer = false
    }

    private static func newRecordingDestination() -> URL {
        let documents = URL.documentsDirectory
        let timestamp = Date.now.formatted(
            .iso8601
                .year().month().day()
                .timeSeparator(.omitted)
                .dateTimeSeparator(.standard)
        )
        return documents
            .appending(path: "Recordings", directoryHint: .isDirectory)
            .appending(path: "tangent-\(timestamp).m4a")
    }
}

private enum RecordPersistenceError: LocalizedError {
    case missingProfile

    var errorDescription: String? {
        "Your profile is needed to save this Tangent."
    }
}
