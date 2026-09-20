import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var name = ""
    @Published var interests = ""
    @Published var concerns = ""
    @Published private(set) var isSavingProfile = false
    @Published private(set) var reminderEnabled = true
    @Published private(set) var dailyReminder = SettingsViewModel.defaultReminderTime()

    @Published private(set) var profileID: UUID?
    @Published private(set) var isLoading = true
    @Published private(set) var isUpdatingReminder = false
    @Published private(set) var message: String?
    @Published var exportDocument: SettingsExportDocument?
    @Published var showsExporter = false

    @Published private(set) var selectedModel = SummaryModelID.default
    @Published private(set) var modelStates: [SummaryModelID: ModelDownloadState] = [:]

    @Published private(set) var aiRequested = false
    @Published private(set) var aiSetupLoaded = false
    private var preferences: AppPreferences?

    var selectedModelIsReady: Bool { modelStates[selectedModel]?.isReady == true }

    func configureAI(preferences: AppPreferences) async {
        self.preferences = preferences
        aiSetupLoaded = false
        aiRequested = preferences.aiEnabled
        await loadModels()
    }

    func setAIRequested(_ requested: Bool) {
        aiRequested = requested
        if !requested {
            for model in SummaryModelID.allCases { modelCatalog?.cancelDownload(model) }
        }
        updateAIAvailability()
    }

    func resetPendingAISetup() {
        if !selectedModelIsReady { setAIRequested(false) }
    }

    private func updateAIAvailability() {
        guard let preferences else { return }
        let enabled = aiRequested && selectedModelIsReady
        if preferences.aiEnabled != enabled { preferences.aiEnabled = enabled }
    }

    private let noteStore: any NoteStore
    private let reminderScheduler: any ReminderScheduler
    private let modelCatalog: (any ModelCatalog)?
    private var profile: UserProfile?

    init(
        noteStore: any NoteStore,
        reminderScheduler: any ReminderScheduler,
        modelCatalog: (any ModelCatalog)? = nil
    ) {
        self.noteStore = noteStore
        self.reminderScheduler = reminderScheduler
        self.modelCatalog = modelCatalog
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let profile = try await noteStore.userProfiles().first else {
                message = "No user profile is available."
                return
            }
            apply(profile)
            if let reminder = profile.dailyReminder {
                try await reminderScheduler.scheduleDailyReminder(at: reminder)
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func setReminderEnabled(_ enabled: Bool) async {
        guard var profile, !isUpdatingReminder else { return }
        let previousReminder = profile.dailyReminder
        reminderEnabled = enabled
        isUpdatingReminder = true
        defer { isUpdatingReminder = false }

        do {
            if enabled {
                profile.dailyReminder = dailyReminder
                try await reminderScheduler.scheduleDailyReminder(
                    at: dailyReminder
                )
            } else {
                profile.dailyReminder = nil
                reminderScheduler.cancelDailyReminder()
            }
            try await noteStore.saveUserProfile(profile)
            self.profile = profile
            message = nil
        } catch {
            reminderEnabled = previousReminder != nil
            profile.dailyReminder = previousReminder
            self.profile = profile
            message = error.localizedDescription
        }
    }

    @discardableResult
    func saveProfile() async -> Bool {
        guard var profile, !isSavingProfile else { return false }
        isSavingProfile = true
        defer { isSavingProfile = false }
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.interests = Self.lines(interests)
        profile.concerns = Self.lines(concerns)
        do {
            try await noteStore.saveUserProfile(profile)
            self.profile = profile
            message = "Profile saved."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func setReminderTime(_ time: Date) async {
        guard var profile, reminderEnabled, !isUpdatingReminder else { return }
        let previousReminder = profile.dailyReminder
        dailyReminder = time
        isUpdatingReminder = true
        defer { isUpdatingReminder = false }

        do {
            profile.dailyReminder = time
            try await reminderScheduler.scheduleDailyReminder(at: time)
            try await noteStore.saveUserProfile(profile)
            self.profile = profile
            message = nil
        } catch {
            dailyReminder = previousReminder ?? Self.defaultReminderTime()
            profile.dailyReminder = previousReminder
            self.profile = profile
            message = error.localizedDescription
        }
    }

    func prepareExport() async {
        guard let profileID else { return }
        do {
            let entries = try await noteStore.diaryEntries(profileID: profileID)
            exportDocument = SettingsExportDocument(
                data: DiaryXMLExporter.makeDocument(
                    entries: entries,
                    profileID: profileID
                )
            )
            showsExporter = true
            message = nil
        } catch {
            message = "Your diary could not be prepared for export."
        }
    }

    func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            message = "Diary exported."
        case .failure:
            message = "Your diary could not be exported."
        }
    }

    // MARK: - Models

    func loadModels() async {
        guard let modelCatalog else { return }
        selectedModel = modelCatalog.selectedModel
        for model in SummaryModelID.allCases {
            modelStates[model] = await modelCatalog.state(of: model)
        }
        if !aiSetupLoaded && !selectedModelIsReady { aiRequested = false }
        aiSetupLoaded = true
        updateAIAvailability()
        await followDownloads()
    }

    /// A download started here keeps reporting through its own callback, but a
    /// download begun before this screen was reopened has no one listening, so
    /// its progress is read back from the catalog until it finishes.
    private func followDownloads() async {
        guard let modelCatalog else { return }
        while !Task.isCancelled,
              modelStates.values.contains(where: { $0.isDownloading }) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            for model in SummaryModelID.allCases
            where modelStates[model]?.isDownloading == true {
                modelStates[model] = await modelCatalog.state(of: model)
            }
            updateAIAvailability()
        }
    }

    /// Choosing a model only chooses it. Downloading is its own button on the
    /// card, labelled with the size, so a multi-gigabyte transfer never starts
    /// from a tap that looked like a preference.
    func chooseModel(_ model: SummaryModelID) {
        guard let modelCatalog else { return }
        modelCatalog.select(model)
        selectedModel = model
        updateAIAvailability()
    }

    func download(_ model: SummaryModelID) async {
        guard let modelCatalog else { return }
        modelStates[model] = .downloading(
            DownloadProgress(completedBytes: 0, totalBytes: 0)
        )
        do {
            try await modelCatalog.download(model) { [weak self] progress in
                self?.modelStates[model] = .downloading(progress)
            }
            modelStates[model] = await modelCatalog.state(of: model)
        } catch is CancellationError {
            modelStates[model] = await modelCatalog.state(of: model)
        } catch {
            modelStates[model] = .failed(message: error.localizedDescription)
        }
        updateAIAvailability()
    }

    func cancelDownload(_ model: SummaryModelID) async {
        guard let modelCatalog else { return }
        modelCatalog.cancelDownload(model)
        modelStates[model] = await modelCatalog.state(of: model)
        updateAIAvailability()
    }

    func deleteModel(_ model: SummaryModelID) async {
        guard let modelCatalog else { return }
        do {
            try await modelCatalog.delete(model)
            message = "\(model.displayName) removed."
        } catch {
            message = "\(model.displayName) could not be removed."
        }
        modelStates[model] = await modelCatalog.state(of: model)
        if model == selectedModel && !selectedModelIsReady { aiRequested = false }
        updateAIAvailability()
    }

    func stateDescription(for model: SummaryModelID) -> String {
        switch modelStates[model] ?? .notDownloaded {
        case .notDownloaded:
            "Not on this device"
        case .downloading(let progress):
            Self.downloadDescription(progress)
        case .ready(let bytes):
            "On this device · \(Self.size(bytes))"
        case .failed(let message):
            message
        }
    }

    private static func downloadDescription(_ progress: DownloadProgress) -> String {
        if progress.completedFraction != nil {
            return "Downloading · \(Int(progress.fraction * 100))%"
        }
        guard progress.totalBytes > 0 else { return "Starting download…" }
        return "Downloading · \(size(progress.completedBytes)) of \(size(progress.totalBytes))"
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var formattedReminderTime: String {
        guard reminderEnabled else { return "—" }
        return dailyReminder.formatted(date: .omitted, time: .shortened)
    }

    private func apply(_ profile: UserProfile) {
        self.profile = profile
        profileID = profile.id
        name = profile.name
        interests = profile.interests.joined(separator: "\n")
        concerns = profile.concerns.joined(separator: "\n")
        reminderEnabled = profile.dailyReminder != nil
        dailyReminder = profile.dailyReminder ?? Self.defaultReminderTime()
    }

    nonisolated private static func defaultReminderTime(
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.date(
            bySettingHour: 21,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}
