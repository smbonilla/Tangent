import SwiftUI
import UIKit

struct ContentView: View {
    let dependencies: AppDependencies

    @State private var selectedTab = PrimaryTab.diary
    @State private var diaryPath: [DiaryRoute] = []
    @State private var recordPath: [RecordRoute] = []
    @State private var coversRecordTransition = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        Self.makeTabBarTransparent()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $diaryPath) {
                DiaryHomeView(
                    noteStore: dependencies.noteStore,
                    modelCatalog: dependencies.modelCatalog,
                    openEntry: { diaryPath.append(.details($0)) },
                    openRecord: { selectedTab = .record },
                    openSettings: { diaryPath.append(.settings) }
                )
                .tangentLogoToolbar()
                .navigationDestination(for: DiaryRoute.self) { route in
                    switch route {
                    case .details(let diaryID):
                        DailyTangentDetailsView(
                            noteStore: dependencies.noteStore,
                            transcriber: dependencies.transcriber,
                            languageModel: dependencies.languageModel,
                            diaryID: diaryID,
                            redoToday: startNewRecording,
                            openSettings: { diaryPath.append(.settings) }
                        )
                    case .freshRecording(let diaryID):
                        DailyTangentDetailsView(
                            noteStore: dependencies.noteStore,
                            transcriber: dependencies.transcriber,
                            languageModel: dependencies.languageModel,
                            diaryID: diaryID,
                            streamsTranscript: true,
                            redoToday: startNewRecording,
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
                    openSettings: { recordPath.append(.settings) },
                    onRecordingFinished: showDailySummary(for:),
                    isActive: selectedTab == .record
                )
                .tangentLogoToolbar()
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

            NavigationStack {
                InsightsView(
                    noteStore: dependencies.noteStore,
                    languageModel: dependencies.languageModel,
                    modelCatalog: dependencies.modelCatalog
                )
                .tangentLogoToolbar()
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
        .onAppear(perform: Self.makeTabBarTransparent)
        .overlay {
            Color.tangentWash
                .ignoresSafeArea()
                .opacity(coversRecordTransition ? 1 : 0)
                .allowsHitTesting(coversRecordTransition)
        }
        .animation(.easeInOut(duration: 0.25), value: coversRecordTransition)
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
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

    private func startNewRecording() {
        diaryPath = []
        recordPath = []
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
}

private extension View {
    func tangentLogoToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .accessibilityLabel("Tangent")
            }
        }
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
