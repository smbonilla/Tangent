import Foundation
import SwiftData
import Testing
@testable import Tangent

@MainActor
struct OptionalAITests {
    @Test
    func preferencesPersistAndExistingInstallsKeepTheirWorkflow() {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(!preferences.aiEnabled)
        #expect(!preferences.onboardingCompleted)
        preferences.completeOnboarding()
        preferences.aiEnabled = true
        let relaunched = AppPreferences(defaults: defaults)
        #expect(relaunched.onboardingCompleted)
        #expect(relaunched.aiEnabled)
        relaunched.aiEnabled = false
        #expect(!AppPreferences(defaults: defaults, existingInstall: true).aiEnabled)
        defaults.removePersistentDomain(forName: suite)
        let upgraded = AppPreferences(defaults: defaults, existingInstall: true)
        #expect(upgraded.aiEnabled)
        #expect(upgraded.onboardingCompleted)
    }

    @Test
    func disabledAIBlocksGenerationButAllowsExplicitModelSetup() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let languageModel = ControlledLanguageModel()
        let catalog = SpyModelCatalog()
        let service = OptionalAIService(preferences: preferences, languageModel: languageModel, catalog: catalog)
        await service.prepare()
        try await service.download(.default, onProgress: { _ in })
        #expect(!preferences.aiEnabled)
        await #expect(throws: DiaryLanguageModelError.aiDisabled) {
            try await service.generateInsights(from: [], focus: DiaryFocus(), period: "Today", onPartial: nil)
        }
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let profile = UserProfile(name: "Alex")
        try await store.saveUserProfile(profile)
        let path = try RecordHomeViewModel.writeTranscript("I went for a walk.\nThen I drew a tree.")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let entry = DiaryEntry(profileID: profile.id, day: Date(), promptText: "", transcriptPath: path)
        try await store.saveDiaryEntry(entry)
        let details = DailyTangentDetailsViewModel(noteStore: store, languageModel: service, diaryID: entry.id)
        await details.start()
        #expect(details.transcript == "I went for a walk.\nThen I drew a tree.")
        #expect(try await store.diaryEntry(id: entry.id)?.summaryShort == "")
        #expect(await languageModel.calls == 0)
        #expect(catalog.downloads == 1)
        #expect(DiaryHomeViewModel.transcriptPreview(at: path) == "I went for a walk. Then I drew a tree.")
        #expect(DiaryHomeViewModel.transcriptPreview(at: "/missing.txt") == "Transcript not available")

        preferences.aiEnabled = true
        #expect(catalog.downloads == 1) // Enabling AI retains explicit download consent.
        catalog.downloaded = false
        let diary = DiaryHomeViewModel(noteStore: store, modelCatalog: catalog)
        await diary.load()
        #expect(diary.needsModel)
        await details.regenerate()
        #expect(details.summaryDisplay == .failed(message: DiaryLanguageModelError.modelNotDownloaded(.default).localizedDescription, needsModel: true))
        #expect(await languageModel.calls == 0)
        #expect(!preferences.aiEnabled)
        catalog.downloaded = true
        preferences.aiEnabled = true
        await diary.load()
        #expect(!diary.needsModel)
        await details.regenerate()
        #expect(try await store.diaryEntry(id: entry.id)?.summaryShort == "A walk and a drawing.")
    }

    @Test
    func modelSetupOnlyEnablesAIWhenSelectedModelIsReady() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let catalog = SpyModelCatalog()
        catalog.downloaded = false
        let service = OptionalAIService(preferences: preferences, languageModel: ControlledLanguageModel(), catalog: catalog)
        let container = try TangentModelContainer.make(inMemory: true)
        let model = SettingsViewModel(
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            reminderScheduler: UnavailableReminderScheduler(), modelCatalog: service
        )
        await model.configureAI(preferences: preferences)
        model.setAIRequested(true)
        model.chooseModel(.gemma3_1B)
        #expect(catalog.selectedModel == .gemma3_1B)
        #expect(!preferences.aiEnabled)
        #expect(!model.selectedModelIsReady)
        #expect(catalog.downloads == 0)

        catalog.downloadError = URLError(.notConnectedToInternet)
        await model.download(.gemma3_1B)
        #expect(!preferences.aiEnabled)
        #expect(!model.selectedModelIsReady)

        let memoryError = ModelResourceError.downloadMemory(required: 2_800_000_000, available: 2_270_000_000)
        catalog.downloadError = memoryError
        await model.download(.gemma3_1B)
        #expect(model.modelStates[.gemma3_1B] == .failed(message: memoryError.localizedDescription))
        #expect(!preferences.aiEnabled)
        #expect(!model.selectedModelIsReady)

        catalog.downloadError = nil
        await model.download(.gemma3_1B)
        #expect(model.selectedModelIsReady)
        #expect(preferences.aiEnabled)

        await model.deleteModel(.gemma3_1B)
        #expect(!preferences.aiEnabled)
        #expect(!model.aiRequested)
        #expect(!model.selectedModelIsReady)

        model.setAIRequested(true)
        model.resetPendingAISetup()
        #expect(!model.aiRequested)
        await model.download(.gemma3_1B)
        #expect(!preferences.aiEnabled) // Finishing a download cannot undo opting out.
    }

    @Test
    func setupTurnsOffPersistedAIWithoutDownloadedModel() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.aiEnabled = true
        let catalog = SpyModelCatalog()
        catalog.downloaded = false
        let container = try TangentModelContainer.make(inMemory: true)
        let model = SettingsViewModel(
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            reminderScheduler: UnavailableReminderScheduler(), modelCatalog: catalog
        )
        await model.configureAI(preferences: preferences)
        #expect(!preferences.aiEnabled)
        #expect(!model.aiRequested)
    }

    @Test
    func disablingAIRejectsLateResultsEvenAfterReenabling() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.aiEnabled = true
        let languageModel = ControlledLanguageModel(paused: true)
        let catalog = SpyModelCatalog()
        let service = OptionalAIService(preferences: preferences, languageModel: languageModel, catalog: catalog)
        let task = Task {
            try await service.generateShortSummary(transcript: "A walk.", profile: UserProfile(name: "Alex"), onPartial: nil)
        }
        for _ in 0..<1000 {
            if await languageModel.isWaiting { break }
            await Task.yield()
        }
        #expect(await languageModel.isWaiting)
        preferences.aiEnabled = false
        preferences.aiEnabled = true
        await languageModel.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Set(catalog.cancelled) == Set(SummaryModelID.allCases))
    }
}

private actor ControlledLanguageModel: DiaryLanguageModel {
    private(set) var calls = 0
    private let paused: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    init(paused: Bool = false) { self.paused = paused }
    func resume() { continuation?.resume(); continuation = nil }
    func prepare() async { calls += 1 }
    func generateShortSummary(transcript: String, profile: UserProfile, onPartial: (@Sendable (String) -> Void)?) async throws -> GeneratedText {
        calls += 1
        if paused { await withCheckedContinuation { continuation = $0 } }
        return GeneratedText(text: "A walk and a drawing.", promptText: "A prompt")
    }
    func generateInsights(from summaries: [DiarySummary], focus: DiaryFocus, period: String, onPartial: (@Sendable (String) -> Void)?) async throws -> GeneratedText {
        calls += 1
        return GeneratedText(text: "Creative afternoons.", promptText: "A prompt")
    }
}

@MainActor
private final class SpyModelCatalog: ModelCatalog {
    var selectedModel = SummaryModelID.default
    var downloaded = true
    var downloads = 0
    var downloadError: Error?
    var cancelled: [SummaryModelID] = []
    func select(_ model: SummaryModelID) { selectedModel = model }
    func state(of model: SummaryModelID) async -> ModelDownloadState { downloaded ? .ready(bytesOnDisk: 1) : .notDownloaded }
    func download(_ model: SummaryModelID, onProgress: @escaping @MainActor (DownloadProgress) -> Void) async throws {
        downloads += 1
        if let downloadError { throw downloadError }
        downloaded = true
    }
    func cancelDownload(_ model: SummaryModelID) { cancelled.append(model) }
    func delete(_ model: SummaryModelID) async throws { downloaded = false }
}

struct ModelResourceGuardTests {
    @Test
    func downloadCapacityIncludesTemporaryFilesAndOtherDownloads() throws {
        let model = SummaryModelID.qwen3_0_6B
        let budget = ModelResourceGuard.downloadBudget(for: model)
        let guardWithSpace = ModelResourceGuard(availableMemory: { 10_000_000_000 }, availableStorage: { budget })
        try guardWithSpace.checkDownload(model)
        #expect(throws: ModelResourceError.storage(required: budget + 1, available: budget)) {
            try guardWithSpace.checkDownload(model, reservedBytes: 1)
        }
        #expect(budget > model.approximateDownloadBytes * 2)
        let unknown = ModelResourceGuard(availableStorage: { throw CocoaError(.fileReadUnknown) })
        #expect(throws: ModelResourceError.capacityUnavailable) { try unknown.checkDownload(model) }
    }

    @Test(arguments: SummaryModelID.allCases)
    func downloadRequiresMemoryToLoadAndGenerate(model: SummaryModelID) throws {
        let required = ModelResourceGuard.runBudget(weightBytes: model.approximateDownloadBytes)
        let storage = ModelResourceGuard.downloadBudget(for: model)
        let insufficient = ModelResourceGuard(availableMemory: { required - 1 }, availableStorage: { storage })
        #expect(throws: ModelResourceError.downloadMemory(required: required, available: required - 1)) {
            try insufficient.checkDownload(model)
        }
        try ModelResourceGuard(availableMemory: { required }, availableStorage: { storage }).checkDownload(model)
        #expect(required >= ModelResourceGuard.loadBudget(weightBytes: model.approximateDownloadBytes))
        #expect(required >= model.approximateDownloadBytes + ModelResourceGuard.generationBudget(inputTokens: 4_096, outputTokens: 400))
    }

    @Test
    func downloadRejectsReportedPhoneMemoryDespiteAmpleStorage() {
        let model = SummaryModelID.qwen3_1_7B
        let available: Int64 = 2_270_000_000
        let resources = ModelResourceGuard(availableMemory: { available }, availableStorage: { 20_000_000_000 })
        #expect(throws: ModelResourceError.downloadMemory(
            required: ModelResourceGuard.runBudget(weightBytes: model.approximateDownloadBytes), available: available
        )) {
            try resources.checkDownload(model)
        }
    }

    @Test
    func memoryBudgetsCheckAvailableHeadroomAndInputLength() throws {
        let weights: Int64 = 350_000_000
        let needed = weights * 2 + ModelResourceGuard.reserve * 3
        try ModelResourceGuard(availableMemory: { needed }).checkLoad(weightBytes: weights)
        #expect(throws: ModelResourceError.memory(required: needed, available: needed - 1)) {
            try ModelResourceGuard(availableMemory: { needed - 1 }).checkLoad(weightBytes: weights)
        }
        let ample = ModelResourceGuard(availableMemory: { 10_000_000_000 })
        try ample.checkGeneration(inputTokens: 4_096, outputTokens: 400)
        #expect(throws: ModelResourceError.inputTooLong) {
            try ample.checkGeneration(inputTokens: 4_097, outputTokens: 400)
        }
        #expect(throws: ModelResourceError.memory(required: ModelResourceGuard.reserve, available: 0)) {
            try ModelResourceGuard(availableMemory: { 0 }).checkMemory()
        }
    }

    @Test
    func decliningMemoryCancelsWorkAndDoesNotReturnPartialOutput() async {
        let probe = ResourceCancellationProbe()
        let guardWithLowMemory = ModelResourceGuard(availableMemory: { 0 })
        await #expect(throws: ModelResourceError.memory(required: ModelResourceGuard.reserve, available: 0)) {
            try await guardWithLowMemory.monitoring { try await probe.work() }
        }
        #expect(await probe.cancelled)
    }

    @Test
    func decliningStorageCancelsDownloadWork() async {
        let probe = ResourceCancellationProbe()
        let guardWithLowStorage = ModelResourceGuard(availableStorage: { 0 })
        await #expect(throws: ModelResourceError.storage(required: ModelResourceGuard.reserve, available: 0)) {
            try await guardWithLowStorage.monitoring(storage: true) { try await probe.work() }
        }
        #expect(await probe.cancelled)
    }

    @Test @MainActor
    func memoryWarningPreservesTranscriptAndDoesNotSaveSummary() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let profile = UserProfile(name: "Alex")
        try await store.saveUserProfile(profile)
        let path = try RecordHomeViewModel.writeTranscript("Today I drew a tree.")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let entry = DiaryEntry(profileID: profile.id, day: Date(), promptText: "", transcriptPath: path)
        try await store.saveDiaryEntry(entry)
        let details = DailyTangentDetailsViewModel(noteStore: store, languageModel: LowMemoryLanguageModel(), diaryID: entry.id)
        await details.start()
        #expect(details.transcript == "Today I drew a tree.")
        #expect(try await store.diaryEntry(id: entry.id)?.summaryShort == "")
        #expect(details.summaryDisplay == .failed(message: ModelResourceError.memoryPressure.localizedDescription, needsModel: false))
    }
}

private actor ResourceCancellationProbe {
    private(set) var cancelled = false
    func work() async throws -> String {
        do {
            try await Task.sleep(for: .seconds(30))
            return "Must not be returned"
        } catch {
            cancelled = Task.isCancelled
            throw error
        }
    }
}

private final class LowMemoryLanguageModel: DiaryLanguageModel {
    func prepare() async {}
    func generateShortSummary(transcript: String, profile: UserProfile, onPartial: (@Sendable (String) -> Void)?) async throws -> GeneratedText {
        onPartial?("An unfinished summary")
        throw ModelResourceError.memoryPressure
    }
    func generateInsights(from summaries: [DiarySummary], focus: DiaryFocus, period: String, onPartial: (@Sendable (String) -> Void)?) async throws -> GeneratedText {
        throw ModelResourceError.memoryPressure
    }
}

@MainActor
struct ModelQueueTests {
    @Test
    func insightWaitsUntilSummaryFinishes() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.aiEnabled = true
        let languageModel = ControlledLanguageModel(paused: true)
        let service = OptionalAIService(preferences: preferences, languageModel: languageModel, catalog: SpyModelCatalog())
        let summary = Task {
            try await service.generateShortSummary(transcript: "A walk.", profile: UserProfile(name: "Alex"), onPartial: nil)
        }
        for _ in 0..<1000 {
            if await languageModel.isWaiting { break }
            await Task.yield()
        }
        #expect(await languageModel.isWaiting)
        let waiting = QueueSignal()
        let insight = Task {
            try await service.generateInsights(from: [], focus: DiaryFocus(), period: "Today", onPartial: nil, onStatus: { status in
                if status == .waiting { Task { await waiting.send() } }
            })
        }
        await waiting.wait()
        #expect(await languageModel.calls == 1)
        await languageModel.resume()
        _ = try await summary.value
        _ = try await insight.value
        #expect(await languageModel.calls == 2)
    }

    @Test
    func disablingAICancelsQueuedInsightWithoutRunningIt() async throws {
        let suite = "TangentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.aiEnabled = true
        let languageModel = ControlledLanguageModel(paused: true)
        let service = OptionalAIService(preferences: preferences, languageModel: languageModel, catalog: SpyModelCatalog())
        let summary = Task {
            try await service.generateShortSummary(transcript: "A walk.", profile: UserProfile(name: "Alex"), onPartial: nil)
        }
        for _ in 0..<1000 {
            if await languageModel.isWaiting { break }
            await Task.yield()
        }
        let waiting = QueueSignal()
        let insight = Task {
            try await service.generateInsights(from: [], focus: DiaryFocus(), period: "Today", onPartial: nil, onStatus: { status in
                if status == .waiting { Task { await waiting.send() } }
            })
        }
        await waiting.wait()
        preferences.aiEnabled = false
        await #expect(throws: CancellationError.self) { try await insight.value }
        await languageModel.resume()
        await #expect(throws: CancellationError.self) { try await summary.value }
        #expect(await languageModel.calls == 1)
        preferences.aiEnabled = true
        // Cancellation must release the lease for a later request.
        _ = try await service.generateInsights(from: [], focus: DiaryFocus(), period: "Today", onPartial: nil)
        #expect(await languageModel.calls == 2)
    }
}

private actor QueueSignal {
    private var sent = false
    private var continuation: CheckedContinuation<Void, Never>?
    func send() { sent = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if !sent { await withCheckedContinuation { continuation = $0 } }
    }
}
