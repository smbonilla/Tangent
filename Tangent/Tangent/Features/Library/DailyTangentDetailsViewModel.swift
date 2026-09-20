import Combine
import Foundation

@MainActor
final class DailyTangentDetailsViewModel: ObservableObject {
    private enum SummaryState: Equatable {
        /// Nothing decided yet: still loading, or transcribing, or about to
        /// start. The screen says nothing rather than claiming there is no
        /// summary a moment before writing one.
        case pending
        case waiting
        case generating
        case settled
        /// `needsModel` means no weights are on disk, so the fix is in Settings
        /// rather than another attempt.
        case failed(message: String, needsModel: Bool)
    }

    /// What the summary section should show. One value, so the view never has
    /// to reconcile a state with a half-arrived stream and flicker between them.
    enum SummaryDisplay: Equatable {
        case nothingYet
        case waiting
        case writing(String)
        case written(String)
        case failed(message: String, needsModel: Bool)
        case never
    }

    @Published private(set) var entry: DiaryEntry?
    @Published private(set) var transcript: String?
    @Published private(set) var isTranscribing = false
    // Read through `summaryDisplay`; the raw state is the view model's own.
    @Published private var summaryState: SummaryState = .pending
    /// The sentence as the model writes it, until the saved entry takes over.
    @Published private var streamingShortSummary = ""
    @Published private(set) var loadError: String?

    private let noteStore: any NoteStore
    private let transcriber: (any Transcriber)?
    private let languageModel: (any DiaryLanguageModel)?
    private let diaryID: UUID
    let streamsTranscript: Bool

    init(
        noteStore: any NoteStore,
        transcriber: (any Transcriber)? = nil,
        languageModel: (any DiaryLanguageModel)? = nil,
        diaryID: UUID,
        streamsTranscript: Bool = false
    ) {
        self.noteStore = noteStore
        self.transcriber = transcriber
        self.languageModel = languageModel
        self.diaryID = diaryID
        self.streamsTranscript = streamsTranscript
    }

    var isGenerating: Bool {
        if case .generating = summaryState { return true }
        if case .waiting = summaryState { return true }
        return false
    }

    var summaryDisplay: SummaryDisplay {
        switch summaryState {
        case .pending:
            return .nothingYet

        case .waiting:
            return .waiting

        case .failed(let message, let needsModel):
            return .failed(message: message, needsModel: needsModel)

        case .generating:
            return streamingShortSummary.isEmpty
                ? .nothingYet
                : .writing(streamingShortSummary)

        case .settled:
            let saved = entry?.summaryShort ?? ""
            return saved.isEmpty ? .never : .written(saved)
        }
    }

    var hasSummary: Bool {
        guard let entry else { return false }
        return !entry.summaryShort.isEmpty
    }

    func start() async {
        await load()
        if transcript == nil, streamsTranscript || hasPendingAudio {
            await transcribeFreshRecording(animate: streamsTranscript)
        }
        await generateSummaryIfNeeded()
        if case .pending = summaryState { summaryState = .settled }
    }

    func load() async {
        do {
            entry = try await noteStore.diaryEntry(id: diaryID)
            transcript = Self.storedTranscript(from: entry)
            loadError = entry == nil ? "This Tangent could not be found." : nil
        } catch {
            loadError = "This Tangent could not be loaded."
        }
    }

    /// Runs the model again for an entry that failed, or was recorded before a
    /// model was available.
    func regenerate() async {
        guard let transcript = usableTranscript,
              let profile = try? await noteStore.userProfiles().first
        else {
            return
        }
        await generateSummary(profile: profile, transcript: transcript)
    }

    nonisolated static func loadTranscript(at path: String) -> String? {
        guard !path.isEmpty,
              path.lowercased().hasSuffix(".txt"),
              let text = try? String(
                  contentsOfFile: path,
                  encoding: .utf8
              ) else {
            return nil
        }
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private static func storedTranscript(from entry: DiaryEntry?) -> String? {
        guard let entry else { return nil }
        return loadTranscript(at: entry.transcriptPath)
    }

    private var hasPendingAudio: Bool {
        let path = entry?.transcriptPath.lowercased() ?? ""
        return path.hasSuffix(".m4a") || path.hasSuffix(".caf") || path.hasSuffix(".wav")
    }

    private func transcribeFreshRecording(animate: Bool) async {
        guard let transcriber,
              let path = entry?.transcriptPath,
              !path.isEmpty
        else {
            return
        }

        isTranscribing = true
        do {
            let fullText = try await transcriber.transcribe(
                audioAt: URL(fileURLWithPath: path)
            )
            if animate {
                await reveal(fullText)
            } else {
                transcript = fullText
            }
            try await persist(fullText)
        } catch {
            if transcript == nil {
                loadError = error.localizedDescription
            }
        }
        isTranscribing = false
    }

    private func reveal(_ fullText: String) async {
        var current = ""
        for character in fullText {
            current.append(character)
            if character.isWhitespace || current.count.isMultiple(of: 3) {
                transcript = current
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
        transcript = fullText
    }

    /// Stores the transcript and points the entry at it. The summary stays
    /// empty until the model has written it.
    private func persist(_ transcript: String) async throws {
        guard var entry else { return }
        entry.transcriptPath = try writeTranscriptFile(transcript, replacing: entry.transcriptPath)
        try await noteStore.saveDiaryEntry(entry)
        self.entry = entry
        self.transcript = transcript
    }

    /// Writes a user edit of the visible summary and/or transcript. Empty
    /// summary text is stored as no summary, matching generation skip rules.
    func saveEdits(summary: String?, transcript: String) async {
        guard var entry else { return }
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript != (self.transcript ?? "") {
            do {
                entry.transcriptPath = try writeTranscriptFile(
                    trimmedTranscript,
                    replacing: entry.transcriptPath
                )
                self.transcript = trimmedTranscript.isEmpty ? nil : trimmedTranscript
            } catch {
                loadError = "This transcript could not be saved."
                return
            }
        }

        if let summary {
            entry.summaryShort = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
            try await noteStore.saveDiaryEntry(entry)
            self.entry = entry
            if summary != nil { summaryState = .settled }
            loadError = nil
        } catch {
            loadError = "This Tangent could not be saved."
        }
    }

    private func writeTranscriptFile(_ transcript: String, replacing path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        if path.lowercased().hasSuffix(".txt"), FileManager.default.fileExists(atPath: path) {
            try transcript.write(to: url, atomically: true, encoding: .utf8)
            return path
        }
        let storedPath = try RecordHomeViewModel.writeTranscript(transcript)
        if !path.isEmpty, path != storedPath {
            try? FileManager.default.removeItem(at: url)
        }
        return storedPath
    }

    private func generateSummaryIfNeeded() async {
        guard !isGenerating,
              let transcript = usableTranscript,
              let profile = try? await noteStore.userProfiles().first
        else {
            return
        }

        guard !hasSummary else { return }
        await generateSummary(profile: profile, transcript: transcript)
    }

    private func generateSummary(profile: UserProfile, transcript: String) async {
        guard let languageModel, let entry else { return }

        streamingShortSummary = ""
        summaryState = .waiting
        do {
            let short = try await languageModel.generateShortSummary(
                transcript: transcript,
                profile: profile,
                onPartial: { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.isGenerating else { return }
                        self.streamingShortSummary = partial
                    }
                },
                onStatus: { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.isGenerating else { return }
                        self.summaryState = status == .waiting ? .waiting : .generating
                    }
                }
            )

            try Task.checkCancellation()
            var updated = entry
            updated.summaryShort = short.text
            updated.promptText = short.promptText
            try await noteStore.saveDiaryEntry(updated)
            self.entry = updated
            streamingShortSummary = ""
            summaryState = .settled
        } catch where error is CancellationError || error as? DiaryLanguageModelError == .aiDisabled {
            streamingShortSummary = ""
            summaryState = .settled
        } catch {
            streamingShortSummary = ""
            summaryState = .failed(
                message: error.localizedDescription,
                needsModel: Self.needsModel(error)
            )
        }
    }

    private var usableTranscript: String? {
        guard let transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return transcript
    }

    private static func needsModel(_ error: Error) -> Bool {
        guard let error = error as? DiaryLanguageModelError else { return false }
        if case .modelNotDownloaded = error { return true }
        return false
    }
}
