import Foundation
import SwiftData

enum DemoDataSeeder {
    #if DEBUG
    @MainActor
    static func seedMultipleRecordingsForUITesting(in context: ModelContext) throws {
        guard let profile = try context.fetch(FetchDescriptor<UserProfileRecord>()).first else { return }
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        for (id, hour, text) in [
            ("11111111-1111-1111-1111-111111111111", 9, "A morning walk gave me a new idea."),
            ("22222222-2222-2222-2222-222222222222", 15, "I made progress on that idea in the afternoon.")
        ] {
            let uuid = UUID(uuidString: id)!
            if try context.fetch(FetchDescriptor<DiaryEntryRecord>()).contains(where: { $0.id == uuid }) { continue }
            let entry = DiaryEntry(
                id: uuid, profileID: profile.id, day: today,
                recordingStartedAt: today.addingTimeInterval(Double(hour) * 3600),
                promptText: demoPrompt, summaryShort: text,
                transcriptPath: try RecordHomeViewModel.writeTranscript(text)
            )
            context.insert(DiaryEntryRecord(entry: entry))
        }
        try context.save()
    }
    #endif

    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext, recentOnly: Bool = false) throws {
        #if DEBUG
        // The user is seeded in every build by `ProfileSeeder`; this only
        // adds demo history on top of them.
        guard let profile = try modelContext.fetch(
            FetchDescriptor<UserProfileRecord>(sortBy: [SortDescriptor(\.name)])
        ).first else {
            return
        }

        // Questions belong to ProfileSeeder, which runs first in every build
        // and owns the user's real standing set.

        let existingEntries = try modelContext.fetch(
            FetchDescriptor<DiaryEntryRecord>()
        )
        let profileEntries = existingEntries.filter { $0.profileID == profile.id }
        let hasRealEntries = profileEntries.contains {
            $0.promptText != Self.demoPrompt
        }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        if !hasRealEntries {
            for entry in profileEntries {
                modelContext.delete(entry)
            }

            // A couple of empty gaps (including yesterday) so filled vs empty
            // cards stay easy to tell apart. Today stays empty for recording.
            let examples: [(daysAgo: Int, summary: String)] = [
                (14, "I started sketching ideas for a small creative project."),
                (13, "A conversation with a friend helped me see my idea differently."),
                (12, "I kept switching tasks and left my draft unfinished."),
                (10, "I made progress after setting aside a quiet hour."),
                (9, "I learned a new guitar chord and enjoyed practising it."),
                (8, "I struggled to find time for reading after a busy day."),
                (7, "I finished a chapter and wrote down an idea to try."),
                (6, "I asked for feedback and found one useful change to make."),
                (4, "I felt pleased with the progress on my draft."),
                (3, "I tried a new recipe with friends and enjoyed the evening."),
                (2, "I chose one task to focus on tomorrow instead of a long list."),
            ]

            for example in examples where !recentOnly || example.daysAgo <= 3 {
                guard let day = calendar.date(
                    byAdding: .day,
                    value: -example.daysAgo,
                    to: today
                ) else {
                    continue
                }

                let entry = DiaryEntry(
                    profileID: profile.id,
                    day: day,
                    questions: [
                        DiaryQuestion(text: "What stood out to you today?")
                    ],
                    promptText: Self.demoPrompt,
                    summaryShort: example.summary,
                    transcriptPath: try demoTranscriptPath(
                        daysAgo: example.daysAgo,
                        summary: example.summary
                    )
                )
                modelContext.insert(DiaryEntryRecord(entry: entry))
            }
        }

        let existingInsights = try modelContext.fetch(
            FetchDescriptor<InsightRecord>()
        )
        // Refresh only the built-in demo insight; keep user-generated insights.
        for insight in existingInsights where insight.promptText == Self.demoInsightPrompt {
            modelContext.delete(insight)
        }
        if existingInsights.allSatisfy({ $0.promptText == Self.demoInsightPrompt }),
           let generatedFrom = calendar.date(
               byAdding: .day,
               value: -14,
               to: today
           ),
           let generatedTo = calendar.date(
               byAdding: .day,
               value: -2,
               to: today
           ) {
            let insight = Insight(
                day: today,
                generatedFrom: generatedFrom,
                generatedTo: generatedTo,
                promptText: Self.demoInsightPrompt,
                text: "You returned to your creative project several times. Setting aside a quiet hour and asking for feedback appeared in the entries where you described progress."
            )
            modelContext.insert(InsightRecord(insight: insight))
        }

        try modelContext.save()
        #endif
    }

    /// Removes the temporary DEBUG dummy past day used to check Fill in Tangent.
    @MainActor
    static func removeDummyPastDayIfNeeded(in modelContext: ModelContext) throws {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let dummyEntries = try modelContext.fetch(FetchDescriptor<DiaryEntryRecord>())
            .filter { $0.promptText == dummyPastDayPrompt || $0.promptText == layoutPreviewPrompt }
        for entry in dummyEntries {
            if !entry.transcriptPath.isEmpty {
                try? FileManager.default.removeItem(at: TranscriptFiles.url(for: entry.transcriptPath))
            }
            modelContext.delete(entry)
        }
        for directoryName in ["DummyTranscripts", "LayoutPreviewTranscripts"] {
            let dummyDirectory = URL.applicationSupportDirectory
                .appending(path: directoryName, directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: dummyDirectory)
        }
        guard !dummyEntries.isEmpty else { return }
        try modelContext.save()
        #endif
    }

    private static let demoPrompt = "Demo diary prompt for Taylor"
    private static let demoInsightPrompt = "Demo insight prompt for Taylor"
    private static let dummyPastDayPrompt = "DEBUG dummy past day"
    private static let layoutPreviewPrompt = "DEBUG timeline layout preview"

    private static func demoTranscriptPath(
        daysAgo: Int,
        summary: String
    ) throws -> String {
        let directory = URL.applicationSupportDirectory
            .appending(path: "DemoTranscripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "tangent-\(daysAgo)-days-ago.txt")
        let transcript = "Hi. I wanted to check in about today. \(summary) I want to remember what I tried and what I learned."
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
