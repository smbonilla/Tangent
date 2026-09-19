import Metal
import SwiftData
import SwiftUI

@main
@MainActor
struct TangentApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies
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
            let aiService = OptionalAIService(
                preferences: preferences, languageModel: Self.makeLanguageModel(), catalog: MLXModelCatalog()
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
                try DemoDataSeeder.seedIfNeeded(in: modelContainer.mainContext)
            }
            #endif
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
                    OnboardingView(noteStore: dependencies.noteStore)
                }
            }
            .environmentObject(preferences)
        }
        .modelContainer(modelContainer)
    }
}
