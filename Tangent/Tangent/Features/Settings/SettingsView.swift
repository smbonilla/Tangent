import SwiftUI

struct SettingsView: View {
    private enum ProfileField: Hashable { case name, interests, concerns }
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var model: SettingsViewModel
    @FocusState private var focusedProfileField: ProfileField?

    init(
        noteStore: any NoteStore,
        reminderScheduler: any ReminderScheduler,
        modelCatalog: (any ModelCatalog)? = nil
    ) {
        _model = StateObject(
            wrappedValue: SettingsViewModel(
                noteStore: noteStore,
                reminderScheduler: reminderScheduler,
                modelCatalog: modelCatalog
            )
        )
    }

    var body: some View {
        Form {
            profileSection
            focusSection
            reminderSection
            modelSection
            privacySection
            messageSection
        }
        .font(.system(.body))
        .foregroundStyle(Color.tangentInk)
        .scrollContentBackground(.hidden)
        .background(Color.tangentWash)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    focusedProfileField = nil
                    Task { await model.saveProfile() }
                }
                    .disabled(model.isLoading || model.isSavingProfile)
                    .accessibilityIdentifier("save-profile")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.prepareExport() }
            } label: {
                Label("Export diary", systemImage: "square.and.arrow.up")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.tangentPurple)
            .disabled(model.profileID == nil || model.isLoading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .fileExporter(
            isPresented: $model.showsExporter,
            document: model.exportDocument,
            contentType: .tangentDiaryXML,
            defaultFilename: "Tangent Diary"
        ) { result in
            model.exportCompleted(result)
        }
        .task {
            await model.load()
        }
        .task(id: preferences.aiEnabled) {
            if preferences.aiEnabled { await model.loadModels() }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: $model.name)
                .accessibilityIdentifier("profile-name")
                .focused($focusedProfileField, equals: .name)
        }
    }

    private var focusSection: some View {
        Section {
            TextField("Interests", text: $model.interests, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("profile-interests")
                .focused($focusedProfileField, equals: .interests)
            TextField("Concerns", text: $model.concerns, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("profile-concerns")
                .focused($focusedProfileField, equals: .concerns)
        } header: {
            Text("Your focus")
        }
    }

    private var reminderSection: some View {
        Section("Daily reminder") {
            Toggle("Reminder", isOn: reminderBinding)
                .disabled(model.isUpdatingReminder || model.isLoading)

            DatePicker(
                "Time",
                selection: reminderTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .disabled(
                !model.reminderEnabled
                    || model.isUpdatingReminder
                    || model.isLoading
            )
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { model.dailyReminder },
            set: { time in
                Task { await model.setReminderTime(time) }
            }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { model.reminderEnabled },
            set: { enabled in
                Task { await model.setReminderEnabled(enabled) }
            }
        )
    }

    private var modelSection: some View {
        Section {
            AIToggle()
            if preferences.aiEnabled {
                AIRequirementsNote()
                ForEach(SummaryModelID.allCases) { summaryModel in
                    modelRow(summaryModel)
                }
            }
        } header: {
            Text("Model")
        }
    }

    private var privacySection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(Color.tangentPurple)
                Text("All computation is on-device. Your data is private to you.")
                    .font(.footnote)
                    .foregroundStyle(Color.tangentInk.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.white)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let message = model.message {
            Section {
                Text(message)
                    .foregroundStyle(Color.tangentInk.opacity(0.65))
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ summaryModel: SummaryModelID) -> some View {
        let state = model.modelStates[summaryModel] ?? .notDownloaded
        let isSelected = model.selectedModel == summaryModel

        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.chooseModel(summaryModel)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(summaryModel.displayName)
                        .font(.system(.body, weight: isSelected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.tangentPurple)
                            .accessibilityLabel("Selected")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("model-\(summaryModel.rawValue)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            modelStatus(summaryModel, state: state)
        }
        .padding(.vertical, 4)
    }

    /// Everything about the weights — where they are and what to do about it —
    /// stays inside the model's own card. No sheet, no dialog.
    @ViewBuilder
    private func modelStatus(
        _ summaryModel: SummaryModelID,
        state: ModelDownloadState
    ) -> some View {
        switch state {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.stateDescription(for: summaryModel))
                        .font(.footnote)
                        .foregroundStyle(Color.tangentInk.opacity(0.75))
                }
                // The bar only appears once the total is known; before that the
                // spinner carries the "something is happening" job on its own.
                if progress.totalBytes > 0 || progress.completedFraction != nil {
                    ProgressView(value: progress.fraction)
                        .tint(Color.tangentPurple)
                }
                modelButton("Cancel", role: nil) {
                    Task { await model.cancelDownload(summaryModel) }
                }
            }

        case .ready:
            VStack(alignment: .leading, spacing: 7) {
                statusLine(summaryModel)
                modelButton("Remove", role: .destructive) {
                    Task { await model.deleteModel(summaryModel) }
                }
            }

        case .notDownloaded, .failed:
            VStack(alignment: .leading, spacing: 7) {
                if case .failed = state {
                    statusLine(summaryModel)
                }
                modelButton(downloadLabel(for: summaryModel), role: nil) {
                    Task { await model.download(summaryModel) }
                }
            }
        }
    }

    private func statusLine(_ summaryModel: SummaryModelID) -> some View {
        Text(model.stateDescription(for: summaryModel))
            .font(.footnote)
            .foregroundStyle(Color.tangentInk.opacity(0.6))
    }

    /// The size sits on the button, so the user reads what the tap will cost
    /// before making it.
    private func downloadLabel(for summaryModel: SummaryModelID) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: summaryModel.approximateDownloadBytes,
            countStyle: .file
        )
        return "Download · \(size)"
    }

    private func modelButton(
        _ title: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: action)
            .font(.system(.subheadline, weight: .medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(role == .destructive ? .red : Color.tangentPurple)
    }
}
