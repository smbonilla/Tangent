import Combine
import Foundation

struct DiaryTimelineDay: Identifiable, Equatable {
    let date: Date
    let entries: [DiaryEntry]

    var id: Date { date }
}

@MainActor
final class DiaryHomeViewModel: ObservableObject {
    @Published private(set) var days: [DiaryTimelineDay]
    @Published private(set) var isLoading = true
    @Published private(set) var needsModel = false
    @Published private(set) var transcriptPreviews: [UUID: String] = [:]
    @Published private(set) var loadError: String?

    private let noteStore: any NoteStore
    private let calendar: Calendar
    private let modelCatalog: (any ModelCatalog)?

    init(
        noteStore: any NoteStore,
        modelCatalog: (any ModelCatalog)? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.noteStore = noteStore
        self.modelCatalog = modelCatalog
        self.calendar = calendar
        days = Self.makeTimeline(entries: [], today: Date(), calendar: calendar)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let modelCatalog {
                needsModel = !(await modelCatalog.state(of: modelCatalog.selectedModel)).isReady
            }
            let currentProfile = try await noteStore.userProfiles().first
            let entries: [DiaryEntry]
            if let currentProfile {
                entries = try await noteStore.diaryEntries(
                    profileID: currentProfile.id
                )
            } else {
                entries = []
            }

            transcriptPreviews = Dictionary(uniqueKeysWithValues: entries.map { entry in
                (entry.id, Self.transcriptPreview(at: entry.transcriptPath))
            })
            days = Self.makeTimeline(
                entries: entries,
                today: Date(),
                calendar: calendar
            )
            loadError = nil
        } catch {
            loadError = "Your diary could not be loaded."
        }
    }

    nonisolated static func transcriptPreview(at path: String) -> String {
        guard let transcript = DailyTangentDetailsViewModel.loadTranscript(at: path) else {
            return "Transcript not available"
        }
        let text = transcript.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trailingCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        return String(text.prefix(140)).trimmingCharacters(in: trailingCharacters) + "..."
    }

    nonisolated static func makeTimeline(
        entries: [DiaryEntry],
        today: Date,
        calendar: Calendar
    ) -> [DiaryTimelineDay] {
        let today = calendar.startOfDay(for: today)
        let entriesThroughToday = entries.filter {
            calendar.startOfDay(for: $0.day) <= today
        }
        let entriesByDay = Dictionary(grouping: entriesThroughToday) {
            calendar.startOfDay(for: $0.day)
        }
        let firstDay = entriesByDay.keys.min() ?? today

        var result: [DiaryTimelineDay] = []
        var date = firstDay

        while date <= today {
            let entries = (entriesByDay[date] ?? []).sorted {
                let left = $0.recordingStartedAt ?? $0.day
                let right = $1.recordingStartedAt ?? $1.day
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
            result.append(DiaryTimelineDay(date: date, entries: entries))

            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }
            date = nextDate
        }

        return result
    }
}
