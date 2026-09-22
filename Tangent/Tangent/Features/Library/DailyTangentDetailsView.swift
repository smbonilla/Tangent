import SwiftUI

struct DailyTangentDetailsView: View {
    private enum Field: Hashable { case summary, transcript }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var model: DailyTangentDetailsViewModel
    @FocusState private var focusedField: Field?
    @State private var isEditing = false
    @State private var showsSummaryEditor = false
    @State private var showsRedoConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var showsOptions = false
    @State private var draftSummary = ""
    @State private var draftTranscript = ""
    private let calendar: Calendar
    private let redo: ((Date) -> Void)?
    private let openSettings: (() -> Void)?

    init(
        noteStore: any NoteStore,
        transcriber: (any Transcriber)? = nil,
        languageModel: (any DiaryLanguageModel)? = nil,
        diaryID: UUID,
        streamsTranscript: Bool = false,
        calendar: Calendar = .autoupdatingCurrent,
        redo: ((Date) -> Void)? = nil,
        openSettings: (() -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: DailyTangentDetailsViewModel(
                noteStore: noteStore,
                transcriber: transcriber,
                languageModel: languageModel,
                diaryID: diaryID,
                streamsTranscript: streamsTranscript
            )
        )
        self.calendar = calendar
        self.redo = redo
        self.openSettings = openSettings
    }

    var body: some View {
        Group {
            if let entry = model.entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(
                                    entry.day,
                                    format: .dateTime
                                        .weekday(.wide)
                                        .day()
                                        .month(.wide)
                                        .year()
                                )
                                .font(.system(.title2, design: .serif, weight: .medium))
                                .foregroundStyle(Color.tangentInk)
                                .onTapGesture(perform: dismissKeyboard)
                                if let startedAt = entry.recordingStartedAt {
                                    Text(startedAt, format: .dateTime.hour().minute())
                                        .font(.system(.body, design: .serif))
                                        .foregroundStyle(Color.tangentInk.opacity(0.65))
                                        .accessibilityLabel("Recording started at \(startedAt.formatted(date: .omitted, time: .shortened))")
                                        .accessibilityIdentifier("recording-start-time")
                                }
                            }

                        if preferences.aiEnabled {
                            summarySection
                            Divider()
                                .overlay(Color.tangentInk.opacity(0.1))
                        }

                            transcriptSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: dismissKeyboard)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            } else if let loadError = model.loadError {
                Text(loadError)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.tangentInk.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.summaryDisplay)
        .background(Color.tangentWash)
        .navigationTitle("Daily Tangent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if model.entry != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissKeyboard()
                        showsOptions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.gray)
                    }
                    .tint(.gray)
                    .accessibilityLabel("Options")
                    .accessibilityIdentifier("tangent-options")
                    .disabled(model.isDeleting)
                    .popover(isPresented: $showsOptions) {
                        VStack(spacing: 0) {
                            ShareLink(item: shareText, subject: Text("Tangent")) {
                                optionLabel("Share", systemImage: "square.and.arrow.up", color: .gray)
                            }
                            .disabled(model.isTranscribing || model.isGenerating)
                            .accessibilityIdentifier("share-tangent")
                            Button {
                                showsOptions = false
                                confirmOrRedo()
                            } label: {
                                optionLabel("Re-do", systemImage: "arrow.counterclockwise", color: .gray)
                            }
                            .disabled(redo == nil || model.isTranscribing)
                            .accessibilityIdentifier("redo-tangent")
                            Button(role: .destructive) {
                                showsOptions = false
                                showsDeleteConfirmation = true
                            } label: {
                                optionLabel("Delete", systemImage: "trash", color: .red)
                            }
                            .accessibilityIdentifier("delete-tangent")
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .frame(width: 240)
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await finishEditing() }
                    }
                    .accessibilityIdentifier("save-entry")
                }
            }
        }
        .alert("Delete this Tangent?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await model.deleteEntry() {
                        isEditing = false
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This permanently deletes this Tangent and its saved transcript or recording. Other Tangents will be kept.")
        }
        .alert("Couldn’t complete action", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
        .alert("Re-do this Tangent?", isPresented: $showsRedoConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Overwrite", role: .destructive) {
                performRedo()
            }
        } message: {
            Text("This will overwrite only this recording. Other recordings for this day will be kept.")
        }
        .task {
            await model.start()
        }
        .onChange(of: preferences.aiEnabled) { _, enabled in
            if enabled && !model.hasSummary && !model.isGenerating {
                Task { await model.regenerate() }
            }
        }
        .onDisappear {
            if isEditing {
                Task { await model.saveEdits(summary: editableSummary, transcript: draftTranscript) }
            }
        }
    }

    private func optionLabel(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(.body)
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }

    private var transcriptText: String {
        if let transcript = model.transcript, !transcript.isEmpty {
            return transcript
        }
        if model.isTranscribing {
            return "Transcribing…"
        }
        if let loadError = model.loadError {
            return loadError
        }
        return "No transcript is available for this entry."
    }

    private var canEditSummary: Bool {
        guard preferences.aiEnabled, !model.isGenerating else { return false }
        switch model.summaryDisplay {
        case .written, .never, .failed:
            return true
        default:
            return false
        }
    }

    private var canEditTranscript: Bool {
        !model.isTranscribing
    }

    private var editableSummary: String? {
        showsSummaryEditor && preferences.aiEnabled ? draftSummary : nil
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Summary")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.tangentInk)
                .onTapGesture(perform: dismissKeyboard)

            if isEditing && showsSummaryEditor {
                editableText(
                    $draftSummary,
                    placeholder: "Write a short summary.",
                    field: .summary,
                    identifier: "edit-summary"
                )
            } else {
                summaryContent
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Transcript")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.tangentInk)
                .onTapGesture(perform: dismissKeyboard)

            if isEditing && canEditTranscript {
                editableText(
                    $draftTranscript,
                    placeholder: "Write what you said today.",
                    field: .transcript,
                    identifier: "edit-transcript"
                )
            } else {
                Text(transcriptText)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.tangentInk.opacity(0.82))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canEditTranscript else { return }
                        beginEditing(.transcript)
                    }
                    .accessibilityIdentifier("transcript-text")
            }
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        switch model.summaryDisplay {
        case .waiting:
            Text("Waiting for model…")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color.tangentInk.opacity(0.6))

        case .nothingYet:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating summary…")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.tangentInk.opacity(0.6))
            }

        // Words appearing one by one say "in progress" better than a label
        // would, so nothing else is shown while they arrive.
        case .writing(let text):
            summaryText(text, editable: false)

        case .written(let text):
            summaryText(text, editable: true)

        case .failed(let message, let needsModel):
            VStack(alignment: .leading, spacing: 12) {
                Text(needsModel
                     ? "Download your preferred model in Settings to generate a summary."
                     : message)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.tangentInk.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canEditSummary else { return }
                        beginEditing(.summary)
                    }

                if needsModel, let openSettings {
                    Button("Choose a model", action: openSettings)
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(Color.tangentPurple)
                } else {
                    Button("Try again") {
                        Task { await model.regenerate() }
                    }
                    .font(.system(.subheadline, design: .serif, weight: .medium))
                    .foregroundStyle(Color.tangentPurple)
                }
            }

        case .never:
            unavailableText
        }
    }

    private var unavailableText: some View {
        summaryText("No summary available.", editable: true, faded: true)
    }

    @ViewBuilder
    private func summaryText(_ text: String, editable: Bool, faded: Bool = false) -> some View {
        Text(text)
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color.tangentInk.opacity(faded ? 0.6 : 0.9))
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard editable, canEditSummary else { return }
                beginEditing(.summary)
            }
            .id("summary")
            .accessibilityIdentifier("summary-text")
    }

    private func editableText(
        _ text: Binding<String>,
        placeholder: String,
        field: Field,
        identifier: String
    ) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color.tangentInk.opacity(0.9))
            .lineSpacing(6)
            .lineLimit(3...20)
            .focused($focusedField, equals: field)
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier(identifier)
    }

    private func beginEditing(_ field: Field) {
        if !isEditing {
            draftSummary = model.entry?.summaryShort ?? ""
            draftTranscript = model.transcript ?? ""
            isEditing = true
        }
        if field == .summary {
            if draftSummary.isEmpty {
                draftSummary = model.entry?.summaryShort ?? ""
            }
            showsSummaryEditor = true
        } else if canEditSummary {
            showsSummaryEditor = true
        }
        focusedField = field
    }

    private var shouldConfirmRedo: Bool {
        if model.isTranscribing { return true }
        guard let transcript = model.transcript else { return false }
        return !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func confirmOrRedo() {
        guard model.entry != nil else { return }
        dismissKeyboard()
        if shouldConfirmRedo {
            showsRedoConfirmation = true
        } else {
            performRedo()
        }
    }

    private var shareText: String {
        guard var entry = model.entry else { return "" }
        if isEditing, let summary = editableSummary { entry.summaryShort = summary }
        return TangentShareText.make(entry: entry, transcript: isEditing ? draftTranscript : model.transcript)
    }

    private func performRedo() {
        Task {
            // Keep edits if the user opens recording and then cancels it.
            if isEditing {
                guard await model.saveEdits(summary: editableSummary, transcript: draftTranscript) else { return }
                isEditing = false
            }
            if let day = model.entry?.day { redo?(day) }
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func finishEditing() async {
        dismissKeyboard()
        guard await model.saveEdits(summary: editableSummary, transcript: draftTranscript) else { return }
        isEditing = false
        showsSummaryEditor = false
    }
}

#Preview {
    let container = try! TangentModelContainer.make(inMemory: true)
    let store = SwiftDataNoteStore(modelContext: container.mainContext)
    NavigationStack {
        DailyTangentDetailsView(noteStore: store, diaryID: UUID())
    }
    .environmentObject(AppPreferences(defaults: UserDefaults(suiteName: "TangentPreview")!))
}

struct TangentFillButton: View {
    let title: String
    let hint: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(.body, design: .serif, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.tangentPurple)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .padding(.top, 8)
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
    }
}
