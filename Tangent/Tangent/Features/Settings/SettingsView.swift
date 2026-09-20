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
            await model.configureAI(preferences: preferences)
        }
        .onDisappear { model.resetPendingAISetup() }
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
            AIModelSetupView(model: model, usesFormRows: true)
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

}
