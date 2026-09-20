import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var model: SettingsViewModel
    private enum Field: Hashable { case name, interests, concerns }
    @FocusState private var focusedField: Field?

    init(noteStore: any NoteStore, modelCatalog: any ModelCatalog) {
        _model = StateObject(wrappedValue: SettingsViewModel(
            noteStore: noteStore, reminderScheduler: UnavailableReminderScheduler(),
            modelCatalog: modelCatalog
        ))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { layout in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeading("Profile")
                            TextField("Name", text: $model.name)
                                .textContentType(.givenName)
                                .accessibilityIdentifier("profile-name")
                                .focused($focusedField, equals: .name)
                                .padding(16)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeading("Your focus")
                            VStack(alignment: .leading, spacing: 16) {
                                TextField("Interests", text: $model.interests, axis: .vertical)
                                    .lineLimit(2...5)
                                    .accessibilityIdentifier("profile-interests")
                                    .focused($focusedField, equals: .interests)
                                Divider()
                                TextField("Concerns", text: $model.concerns, axis: .vertical)
                                    .lineLimit(2...5)
                                    .accessibilityIdentifier("profile-concerns")
                                    .focused($focusedField, equals: .concerns)
                            }
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        AIModelSetupView(model: model)
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        if let message = model.message {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: layout.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background {
                GeometryReader { proxy in
                    let diameter = min(proxy.size.width * 1.4, proxy.size.height * 0.85) * 0.75
                    ZStack {
                        Color.tangentWash
                        TangentOrb(reduceMotion: reduceMotion)
                            .frame(width: diameter, height: diameter)
                            .compositingGroup()
                            .opacity(0.5)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                    }
                    .clipped()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .foregroundStyle(Color.tangentInk)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button { finishOnboarding() } label: {
                        Text("Get started")
                            .font(.system(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isLoading || model.isSavingProfile || !model.aiSetupLoaded
                                  || (model.aiRequested && !model.selectedModelIsReady))
                        .accessibilityIdentifier("complete-onboarding")
                    if model.aiRequested && !model.selectedModelIsReady {
                        Button("Continue without AI") {
                            model.setAIRequested(false)
                            finishOnboarding()
                        }
                        .disabled(model.isLoading || model.isSavingProfile)
                        .accessibilityIdentifier("continue-without-ai")
                    }
                }
                .padding(20)
                .background(Color.tangentWash)
            }

            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .task {
                await model.load()
                if model.name == "You" { model.name = "" }
                await model.configureAI(preferences: preferences)
            }
            .onDisappear { model.resetPendingAISetup() }
        }
        .tint(Color.tangentPurple)
    }

    private func finishOnboarding() {
        focusedField = nil
        Task {
            if model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.name = "You" }
            if await model.saveProfile() { preferences.completeOnboarding() }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.footnote)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
    }
}
