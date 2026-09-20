import SwiftUI

/// The Record Tangent screen: a calm idle state with an animated orb that
/// starts a recording on tap, then shows a stop control and elapsed time.
/// Transcription is performed entirely on-device.
struct RecordHomeView: View {
    @StateObject private var model: RecordHomeViewModel

    private let openSettings: () -> Void
    private let onRecordingFinished: (UUID) -> Void
    private let entryDay: Date?

    /// Delay before "Tap to record" fades in. Overridable for previews.
    private let instructionDelay: TimeInterval
    /// Forces the Reduce Motion presentation in previews.
    private let forcesReducedMotion: Bool
    /// True while the Record tab is selected. The instruction fades in on each visit.
    private let isActive: Bool

    @State private var showsInstruction = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(
        audioRecorder: any AudioRecorder,
        transcriber: any Transcriber,
        noteStore: any NoteStore,
        languageModel: (any DiaryLanguageModel)? = nil,
        entryDay: Date? = nil,
        openSettings: @escaping () -> Void,
        onRecordingFinished: @escaping (UUID) -> Void,
        instructionDelay: TimeInterval = 3,
        forcesReducedMotion: Bool = false,
        isActive: Bool = true
    ) {
        _model = StateObject(
            wrappedValue: RecordHomeViewModel(
                audioRecorder: audioRecorder,
                transcriber: transcriber,
                noteStore: noteStore,
                languageModel: languageModel
            )
        )
        self.openSettings = openSettings
        self.onRecordingFinished = onRecordingFinished
        self.entryDay = entryDay
        self.instructionDelay = instructionDelay
        self.forcesReducedMotion = forcesReducedMotion
        self.isActive = isActive
    }

    private var reduceMotion: Bool {
        systemReduceMotion || forcesReducedMotion
    }

    var body: some View {
        ZStack {
            Color.tangentWash
                .ignoresSafeArea()

            orb
                .overlay(alignment: .top) {
                    promptingQuestion
                        .offset(y: -112)
                }
                .overlay(alignment: .bottom) {
                    statusBelowOrb
                        .padding(.top, 12)
                        .alignmentGuide(.bottom) { $0[.top] }
                }

            VStack {
                Spacer()
                if case .failed(let message) = model.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.tangentInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(action: openSettings)
            }
        }
        .onChange(of: entryDay) { _, day in
            model.entryDay = day
        }
        .task(id: isActive) {
            model.entryDay = entryDay
            guard isActive else {
                showsInstruction = false
                return
            }
            showsInstruction = false
            if instructionDelay > 0 {
                try? await Task.sleep(for: .seconds(instructionDelay))
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.4)) {
                showsInstruction = true
            }
        }
    }

    private var orb: some View {
        ZStack {
            TangentOrb(reduceMotion: reduceMotion)
                .frame(width: 240, height: 240)

            orbContent
        }
        .padding(24)
        .contentShape(Rectangle())
        .onTapGesture(perform: startRecordingIfIdle)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(model.isRecording ? [] : .isButton)
        .accessibilityLabel(orbAccessibilityLabel)
        .accessibilityAction {
            startRecordingIfIdle()
        }
    }

    private var promptingQuestion: some View {
        ZStack {
            if model.isRecording, let question = model.currentPromptQuestion {
                Text(question)
                    .id(question)
                    .font(.system(.title3, weight: .regular))
                    .foregroundStyle(Color.tangentInk.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 320)
                    .transition(.opacity)
                    .accessibilityLabel("Prompt: \(question)")
            } else if model.showsQuestionSuggestionOffer {
                Button {
                    Task { await model.acceptQuestionSuggestions() }
                } label: {
                    Text("Suggest prompts")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.gray)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityHint("Shows gentle questions while you record")
            }
        }
        .frame(width: 330, height: 80)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.8),
            value: model.currentPromptQuestion
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.8),
            value: model.showsQuestionSuggestionOffer
        )
    }

    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    private var showsTapToRecord: Bool {
        showsInstruction && !model.isRecording
    }

    private var orbContent: some View {
        stopButton
            .opacity(model.isRecording ? 1 : 0)
            .allowsHitTesting(model.isRecording)
            .animation(chromeAnimation, value: model.isRecording)
    }

    private var stopButton: some View {
        Button {
            Task {
                if let diaryID = await model.stopRecording() {
                    onRecordingFinished(diaryID)
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)
                .frame(width: 34, height: 34)
                .padding(18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
    }

    private var statusBelowOrb: some View {
        ZStack {
            Button(action: startRecordingIfIdle) {
                Text("Tap to record")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsTapToRecord ? 1 : 0)
            .allowsHitTesting(showsTapToRecord)
            .accessibilityHidden(!showsTapToRecord)
            .accessibilityLabel("Tap to record")

            Text("Recording · \(model.formattedElapsed)")
                .font(.body.monospacedDigit())
                .opacity(model.isRecording ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!model.isRecording)
                .accessibilityLabel("Recording, \(model.formattedElapsed)")
        }
        .foregroundStyle(Color.tangentInk.opacity(0.72))
        .animation(chromeAnimation, value: showsTapToRecord)
        .animation(chromeAnimation, value: model.isRecording)
    }

    private func startRecordingIfIdle() {
        guard !model.isBusy else { return }
        Task {
            await model.startRecording()
        }
    }

    private var orbAccessibilityLabel: String {
        switch model.phase {
        case .idle, .failed:
            return "Start recording"
        case .recording:
            return "Recording"
        }
    }
}

#Preview("Initial (instruction hidden)") {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        RecordHomeView(
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            openSettings: {},
            onRecordingFinished: { _ in },
            instructionDelay: 3600
        )
    }
}

#Preview("Ready (instruction visible)") {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        RecordHomeView(
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            openSettings: {},
            onRecordingFinished: { _ in },
            instructionDelay: 0
        )
    }
}

#Preview("Reduce Motion") {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        RecordHomeView(
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            openSettings: {},
            onRecordingFinished: { _ in },
            instructionDelay: 0,
            forcesReducedMotion: true
        )
    }
}
