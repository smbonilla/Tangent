import Combine
import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var generatedInsight: Insight?
    @Published private(set) var isGenerating = false
    @Published private(set) var isWaiting = false
    /// The insights as the model writes them, until the saved one takes over.
    @Published private(set) var streamingInsight = ""
    @Published private(set) var generationError: String?
    @Published private(set) var fromDate: Date
    @Published private(set) var toDate: Date

    private let noteStore: any NoteStore
    private let languageModel: any DiaryLanguageModel
    private let calendar: Calendar
    private let maximumToDate: Date
    @Published private(set) var selectedModel: SummaryModelID

    init(
        noteStore: any NoteStore,
        languageModel: any DiaryLanguageModel,
        selectedModel: SummaryModelID = .default,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.noteStore = noteStore
        self.languageModel = languageModel
        self.selectedModel = selectedModel
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        maximumToDate = today
        toDate = today
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        fromDate = max(
            lastWeek,
            Self.earliestDate(before: today, model: selectedModel, calendar: calendar)
        )
    }

    var earliestFromDate: Date {
        Self.earliestDate(before: toDate, model: selectedModel, calendar: calendar)
    }

    var insightSpanDescription: String {
        selectedModel.insightSpanDescription
    }

    func setSelectedModel(_ model: SummaryModelID) {
        selectedModel = model
        fromDate = min(max(fromDate, earliestFromDate), toDate)
    }

    var latestToDate: Date {
        maximumToDate
    }

    func setFromDate(_ date: Date) {
        fromDate = min(max(calendar.startOfDay(for: date), earliestFromDate), toDate)
    }

    func setToDate(_ date: Date) {
        toDate = min(calendar.startOfDay(for: date), latestToDate)
        fromDate = min(max(fromDate, earliestFromDate), toDate)
    }

    func generateInsight() async {
        guard !isGenerating else { return }
        isGenerating = true
        isWaiting = true
        generatedInsight = nil
        generationError = nil
        streamingInsight = ""
        defer { isGenerating = false; isWaiting = false }
        let requestedFrom = fromDate
        let requestedTo = toDate
        let requestedPeriod = periodDescription

        do {
            let profile = try await noteStore.userProfiles().first
            let entries = try await noteStore.diaryEntries(profileID: profile?.id)
            let endExclusive = calendar.date(
                byAdding: .day,
                value: 1,
                to: requestedTo
            ) ?? requestedTo
            let selectedEntries = entries.filter {
                $0.day >= requestedFrom && $0.day < endExclusive
            }
            let summaries = selectedEntries.compactMap(DiarySummary.init)
            guard !summaries.isEmpty else {
                throw DiaryLanguageModelError.notEnoughEntries
            }
            let generated = try await languageModel.generateInsights(
                from: summaries,
                focus: profile?.focus ?? DiaryFocus(),
                period: requestedPeriod,
                onPartial: { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.isGenerating else { return }
                        self.streamingInsight = partial
                    }
                },
                onStatus: { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.isGenerating else { return }
                        self.isWaiting = status == .waiting
                    }
                }
            )
            try Task.checkCancellation()
            let insight = Insight(
                day: Date(),
                generatedFrom: requestedFrom,
                generatedTo: requestedTo,
                promptText: generated.promptText,
                text: generated.text
            )
            try await noteStore.saveInsight(insight)
            generatedInsight = insight
            streamingInsight = ""
        } catch where error is CancellationError || error as? DiaryLanguageModelError == .aiDisabled {
            streamingInsight = ""
        } catch {
            streamingInsight = ""
            // The model says why — no model downloaded, nothing in range —
            // and that is more use than a blanket apology.
            generationError = error.localizedDescription
        }
    }

    /// Names the range back to the reader, e.g. "9 Sep 2026 to 16 Sep 2026".
    private var periodDescription: String {
        let format = Date.FormatStyle()
            .day()
            .month(.abbreviated)
            .year()
            .locale(Locale(identifier: "en_GB"))
        let from = fromDate.formatted(format)
        let to = toDate.formatted(format)
        return from == to ? from : "\(from) to \(to)"
    }

    private static func earliestDate(
        before date: Date,
        model: SummaryModelID,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            byAdding: .day,
            value: -model.maximumInsightSpanDays,
            to: date
        ) ?? date
    }
}
