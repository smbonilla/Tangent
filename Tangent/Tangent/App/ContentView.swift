import SwiftUI
import UIKit

struct ContentView: View {
    let dependencies: AppDependencies

    @State private var selectedTab = PrimaryTab.diary
    @State private var diaryPath: [DiaryRoute] = []
    @State private var recordPath: [RecordRoute] = []
    @State private var recordingDay: Date?
    @State private var recordingEntryID: UUID?
    @State private var insightsPath: [InsightsRoute] = []
    @State private var coversRecordTransition = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        Self.makeTabBarTransparent()
        Self.makeNavigationBarTransparent()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $diaryPath) {
                DiaryHomeView(
                    noteStore: dependencies.noteStore,
                    modelCatalog: dependencies.modelCatalog,
                    openEntry: { diaryPath.append(.details($0)) },
                    openRecord: { startRecording(on: nil) },
                    openEmptyDay: { startRecording(on: $0) },
                    openSettings: { diaryPath.append(.settings) }
                )
                .tangentLogoToolbar(action: showDiary)
                .navigationDestination(for: DiaryRoute.self) { route in
                    switch route {
                    case .details(let diaryID):
                        DailyTangentDetailsView(
                            noteStore: dependencies.noteStore,
                            transcriber: dependencies.transcriber,
                            languageModel: dependencies.languageModel,
                            diaryID: diaryID,
                            redo: { startRecording(on: $0, replacing: diaryID) },
                            openSettings: { diaryPath.append(.settings) }
                        )
                    case .freshRecording(let diaryID):
                        DailyTangentDetailsView(
                            noteStore: dependencies.noteStore,
                            transcriber: dependencies.transcriber,
                            languageModel: dependencies.languageModel,
                            diaryID: diaryID,
                            streamsTranscript: true,
                            redo: { startRecording(on: $0, replacing: diaryID) },
                            openSettings: { diaryPath.append(.settings) }
                        )
                    case .settings:
                        SettingsView(
                            noteStore: dependencies.noteStore,
                            reminderScheduler: dependencies.reminderScheduler,
                            modelCatalog: dependencies.modelCatalog
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackgroundVisibility(.hidden, for: .tabBar)
            .tabItem {
                Image(systemName: "book.closed")
                    .accessibilityLabel("Diary")
            }
            .tag(PrimaryTab.diary)

            NavigationStack(path: $recordPath) {
                RecordHomeView(
                    audioRecorder: dependencies.audioRecorder,
                    transcriber: dependencies.transcriber,
                    noteStore: dependencies.noteStore,
                    languageModel: dependencies.languageModel,
                    entryDay: recordingDay,
                    replacingEntryID: recordingEntryID,
                    openSettings: { recordPath.append(.settings) },
                    onRecordingFinished: showDailySummary(for:),
                    isActive: selectedTab == .record
                )
                .tangentLogoToolbar(action: showDiary)
                .navigationDestination(for: RecordRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(
                            noteStore: dependencies.noteStore,
                            reminderScheduler: dependencies.reminderScheduler,
                            modelCatalog: dependencies.modelCatalog
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackgroundVisibility(.hidden, for: .tabBar)
            .tabItem {
                Image(systemName: "mic")
                    .accessibilityLabel("Record")
            }
            .tag(PrimaryTab.record)

            NavigationStack(path: $insightsPath) {
                InsightsView(
                    noteStore: dependencies.noteStore,
                    languageModel: dependencies.languageModel,
                    modelCatalog: dependencies.modelCatalog,
                    openSettings: { insightsPath.append(.settings) }
                )
                .tangentLogoToolbar(action: showDiary)
                .navigationDestination(for: InsightsRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(
                            noteStore: dependencies.noteStore,
                            reminderScheduler: dependencies.reminderScheduler,
                            modelCatalog: dependencies.modelCatalog
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarBackgroundVisibility(.hidden, for: .tabBar)
            .tabItem {
                Image(systemName: "lightbulb")
                    .accessibilityLabel("Insights")
            }
            .tag(PrimaryTab.insights)
        }
        .tint(Color.tangentPurple)
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbarBackgroundVisibility(.hidden, for: .tabBar)
        .onAppear {
            Self.makeTabBarTransparent()
            Self.makeNavigationBarTransparent()
        }
        .overlay {
            Color.tangentWash
                .ignoresSafeArea()
                .opacity(coversRecordTransition ? 1 : 0)
                .allowsHitTesting(coversRecordTransition)
        }
        .animation(.easeInOut(duration: 0.25), value: coversRecordTransition)
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
        .onChange(of: selectedTab) { _, tab in
            if tab != .record {
                recordingDay = nil
                recordingEntryID = nil
            }
        }
    }

    private func showDailySummary(for diaryID: UUID) {
        coversRecordTransition = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            recordPath = []
            diaryPath = [.freshRecording(diaryID)]
            selectedTab = .diary
            try? await Task.sleep(for: .milliseconds(40))
            coversRecordTransition = false
        }
    }

    private func showDiary() {
        diaryPath = []
        recordPath = []
        insightsPath = []
        recordingDay = nil
        recordingEntryID = nil
        selectedTab = .diary
    }

    private func startRecording(on day: Date?, replacing entryID: UUID? = nil) {
        recordingDay = day
        recordingEntryID = entryID
        diaryPath = []
        recordPath = []
        insightsPath = []
        selectedTab = .record
    }

    private static func makeTabBarTransparent() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
    }

    private static func makeNavigationBarTransparent() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().isTranslucent = true
    }
}

private extension View {
    func tangentLogoToolbar(action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                DiaryLogoButton(action: action)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

private enum PrimaryTab: Hashable {
    case diary
    case record
    case insights
}

private enum DiaryRoute: Hashable {
    case details(UUID)
    case freshRecording(UUID)
    case settings
}


private enum RecordRoute: Hashable {
    case settings
}

private enum InsightsRoute: Hashable {
    case settings
}

#Preview {
    let container = try! TangentModelContainer.make(inMemory: true)
    ContentView(
        dependencies: AppDependencies(
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            audioRecorder: UnavailableAudioRecorder(),
            transcriber: UnavailableTranscriber(),
            languageModel: UnavailableDiaryLanguageModel(),
            modelCatalog: MLXModelCatalog(),
            reminderScheduler: UnavailableReminderScheduler()
        )
    )
    .environmentObject(AppPreferences(defaults: UserDefaults(suiteName: "TangentPreview")!))
}
