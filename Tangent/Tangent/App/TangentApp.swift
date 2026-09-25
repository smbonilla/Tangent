import Metal
import SwiftData
import SwiftUI

@main
@MainActor
struct TangentApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies
    private let interruptedRecordings: [PendingRecording]
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preferences: AppPreferences

    init() {
        do {
            #if DEBUG
            let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let defaults = isUITesting ? UserDefaults(suiteName: "TangentUITests")! : .standard
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
                defaults.removePersistentDomain(forName: "TangentUITests")
            }
            #else
            let isUITesting = false
            let defaults = UserDefaults.standard
            #endif
            var testStoreURL: URL?
            #if DEBUG
            if isUITesting {
                let directory = URL.applicationSupportDirectory.appending(path: "TangentUITests")
                if ProcessInfo.processInfo.arguments.contains("--reset-onboarding"), FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                testStoreURL = directory.appending(path: "diary.store")
            }
            #endif
            let modelContainer = try TangentModelContainer.make(storeURL: testStoreURL)
            let profileCount = try modelContainer.mainContext.fetchCount(FetchDescriptor<UserProfileRecord>())
            let existingInstall = !isUITesting && profileCount > 0
            let preferences = AppPreferences(defaults: defaults, existingInstall: existingInstall)
            _preferences = StateObject(wrappedValue: preferences)
            var modelResources = ModelResourceGuard()
            #if DEBUG
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--low-model-memory") {
                modelResources = ModelResourceGuard(
                    availableMemory: { 2_270_000_000 }, availableStorage: { 20_000_000_000 }
                )
            }
            #endif
            let aiService = OptionalAIService(
                preferences: preferences, languageModel: Self.makeLanguageModel(),
                catalog: MLXModelCatalog(resources: modelResources)
            )
            self.modelContainer = modelContainer
            try ProfileSeeder.seedIfNeeded(
                in: modelContainer.mainContext
            )
            try PromptSeeder.seedPrompts(
                in: modelContainer.mainContext
            )
            #if DEBUG
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--demo-data") {
                try DemoDataSeeder.seedIfNeeded(
                    in: modelContainer.mainContext,
                    recentOnly: ProcessInfo.processInfo.arguments.contains("--recent-demo-data")
                )
            }
            if isUITesting && ProcessInfo.processInfo.arguments.contains("--multiple-recordings") {
                try DemoDataSeeder.seedMultipleRecordingsForUITesting(in: modelContainer.mainContext)
            }
            #endif
            // Snapshot only at launch; scene changes must not recover the
            // recording currently being captured in this process.
            interruptedRecordings = isUITesting ? [] : ((try? PendingRecording.loadAll()) ?? [])
            dependencies = AppDependencies(
                noteStore: SwiftDataNoteStore(
                    modelContext: modelContainer.mainContext
                ),
                audioRecorder: AVAudioRecorderService(),
                transcriber: OnDeviceTranscriber(),
                languageModel: aiService,
                modelCatalog: aiService,
                reminderScheduler: LocalReminderScheduler()
            )
        } catch {
            fatalError("Unable to initialize Tangent persistence: \(error)")
        }
    }

    /// MLX needs a Metal GPU, which the simulator does not have. Summaries
    /// then fail cleanly instead of crashing inside Metal.
    private static func makeLanguageModel() -> any DiaryLanguageModel {
        #if targetEnvironment(simulator)
        UnavailableDiaryLanguageModel()
        #else
        guard MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) == true else {
            return UnavailableDiaryLanguageModel(error: .unsupportedHardware)
        }
        return MLXDiaryLanguageModel()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if preferences.onboardingCompleted {
                    ContentView(dependencies: dependencies)
                } else {
                    OnboardingView(noteStore: dependencies.noteStore, modelCatalog: dependencies.modelCatalog)
                }
            }
            .environmentObject(preferences)
            // Keep forms and presented screens consistent with Tangent's light palette.
            .preferredColorScheme(.light)
            .task(id: "\(preferences.onboardingCompleted)-\(scenePhase)") {
                guard scenePhase == .active else { return }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
                #endif
                for recording in interruptedRecordings {
                    // Keep the journal on any failure so the next launch retries.
                    try? await recording.recover(in: dependencies.noteStore)
                }
                if preferences.onboardingCompleted {
                    await RecordingPermissions.requestIfNeeded()
                }
                guard preferences.aiEnabled else { return }
                let selected = dependencies.modelCatalog.selectedModel
                let state = await dependencies.modelCatalog.state(of: selected)
                if selected == dependencies.modelCatalog.selectedModel && !state.isReady {
                    preferences.aiEnabled = false
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
