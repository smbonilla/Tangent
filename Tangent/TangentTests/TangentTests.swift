import Foundation
import Testing
import SwiftData
import SQLite3
@testable import Tangent

struct TangentTests {
    @Test @MainActor
    func noteStoreCRUD() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let profileID = UUID()

        var profile = UserProfile(id: profileID, name: "Sam")
        try await store.saveUserProfile(profile)
        #expect(try await store.userProfile(id: profileID)?.name == "Sam")
        profile.name = "Alex"
        try await store.saveUserProfile(profile)
        #expect(try await store.userProfile(id: profileID)?.name == "Alex")

        var prompt = Prompt(text: "What stood out today?")
        try await store.savePrompt(prompt)
        prompt.text = "What mattered today?"
        try await store.savePrompt(prompt)
        #expect(try await store.prompt(id: prompt.id)?.text == prompt.text)

        var question = Question(
            profileID: profileID,
            promptText: "Question prompt for Alex",
            text: "What did you work on?"
        )
        try await store.saveQuestion(question)
        question.text = "What did you work on today?"
        try await store.saveQuestion(question)
        #expect(try await store.questions(profileID: profileID) == [question])

        var diary = DiaryEntry(
            profileID: profileID,
            day: Date(),
            questions: [DiaryQuestion(text: question.text)],
            promptText: "Diary prompt for Alex"
        )
        try await store.saveDiaryEntry(diary)
        diary.summaryShort = "The afternoon was steady."
        try await store.saveDiaryEntry(diary)
        let savedDiary = try #require(
            await store.diaryEntry(id: diary.id)
        )
        #expect(savedDiary.summaryShort == diary.summaryShort)
        #expect(savedDiary.questions == diary.questions)
        #expect(savedDiary.promptText == diary.promptText)

        var insight = Insight(
            day: Date(),
            generatedFrom: diary.day,
            generatedTo: diary.day,
            promptText: "Insight prompt for Alex",
            text: "No trend yet."
        )
        try await store.saveInsight(insight)
        insight.text = "The afternoon looks steady."
        try await store.saveInsight(insight)
        #expect(try await store.insight(id: insight.id)?.text == insight.text)

        try await store.deleteInsight(id: insight.id)
        try await store.deleteDiaryEntry(id: diary.id)
        try await store.deleteQuestion(id: question.id)
        try await store.deletePrompt(id: prompt.id)
        try await store.deleteUserProfile(id: profile.id)

        #expect(try await store.insights().isEmpty)
        #expect(try await store.diaryEntries(profileID: nil).isEmpty)
        #expect(try await store.questions(profileID: nil).isEmpty)
        #expect(try await store.prompts().isEmpty)
        #expect(try await store.userProfiles().isEmpty)
    }

    @Test
    func diaryTimelineIncludesMissingDaysAndEmptyToday() throws {
        let calendar = testCalendar
        let profileID = UUID()
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))
        )
        let twelfth = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))
        )
        let thirteenth = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))
        )
        let entries = [
            DiaryEntry(
                profileID: profileID,
                day: twelfth,
                promptText: "Prompt",
                summaryShort: "First entry"
            ),
            DiaryEntry(
                profileID: profileID,
                day: thirteenth,
                promptText: "Prompt",
                summaryShort: "Second entry"
            )
        ]

        let days = DiaryHomeViewModel.makeTimeline(
            entries: entries,
            today: today,
            calendar: calendar
        )

        #expect(days.count == 4)
        #expect(days[0].entry?.summaryShort == "First entry")
        #expect(days[1].entry?.summaryShort == "Second entry")
        #expect(days[2].entry == nil)
        #expect(days[3].entry == nil)
    }

    @Test
    func diaryTimelineShowsCompletedToday() throws {
        let calendar = testCalendar
        let profileID = UUID()
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))
        )
        let entry = DiaryEntry(
            profileID: profileID,
            day: today,
            promptText: "Prompt",
            summaryShort: "Today is complete"
        )

        let days = DiaryHomeViewModel.makeTimeline(
            entries: [entry],
            today: today,
            calendar: calendar
        )

        #expect(days.count == 1)
        #expect(days[0].entry?.id == entry.id)
    }

    @Test
    func emptyDiaryTimelineOnlyShowsToday() throws {
        let calendar = testCalendar
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))
        )

        let days = DiaryHomeViewModel.makeTimeline(
            entries: [],
            today: today,
            calendar: calendar
        )

        #expect(days == [DiaryTimelineDay(date: today, entry: nil)])
    }

    @Test
    func diaryXMLExportIncludesAllFieldsAndEscapesText() throws {
        let profileID = UUID()
        let questionID = UUID()
        let entryID = UUID()
        let entry = DiaryEntry(
            id: entryID,
            profileID: profileID,
            day: Date(timeIntervalSince1970: 100),
            questions: [DiaryQuestion(id: questionID, text: "Notes < 3 & improving")],
            promptText: "Ask \"carefully\"",
            summaryShort: "Better",
            transcriptPath: "/private/tangent/audio.m4a"
        )

        let data = DiaryXMLExporter.makeDocument(
            entries: [entry],
            profileID: profileID,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let xml = try #require(String(data: data, encoding: .utf8))

        #expect(xml.contains("profile-id=\"\(profileID.uuidString)\""))
        #expect(xml.contains("<entry id=\"\(entryID.uuidString)\">"))
        #expect(xml.contains("<question id=\"\(questionID.uuidString)\">Notes &lt; 3 &amp; improving</question>"))
        #expect(xml.contains("<prompt-text>Ask &quot;carefully&quot;</prompt-text>"))
        #expect(xml.contains("<summary-short>Better</summary-short>"))
        #expect(!xml.contains("summary-long"))
        #expect(xml.contains("<transcript-path>/private/tangent/audio.m4a</transcript-path>"))
    }

    @Test
    func dailyDetailsLoadsTranscriptFromStoredPath() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "tangent-transcript-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "  I felt rested after my walk.\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        #expect(
            DailyTangentDetailsViewModel.loadTranscript(at: url.path)
                == "I felt rested after my walk."
        )
        #expect(
            DailyTangentDetailsViewModel.loadTranscript(at: "") == nil
        )
        #expect(
            DailyTangentDetailsViewModel.loadTranscript(
                at: "/tmp/tangent-audio.m4a"
            ) == nil
        )
    }

    @Test
    func recordingWritesTranscriptTextFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tangent-transcripts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcript = "I slept well. My energy stayed steady all day."

        let path = try RecordHomeViewModel.writeTranscript(
            transcript,
            directory: directory
        )

        #expect(try String(contentsOfFile: path, encoding: .utf8) == transcript)
        #expect(path.hasSuffix(".txt"))
    }

    @Test @MainActor
    func insightsGenerationUsesAModelSpecificLookback() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let calendar = testCalendar
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))
        )
        let user = UserProfile(name: "Taylor", interests: ["Creative projects"], concerns: ["Finding time"])
        try await store.saveUserProfile(user)
        try await store.saveDiaryEntry(
            DiaryEntry(
                profileID: user.id,
                day: today,
                promptText: "Prompt",
                summaryShort: "A steady day"
            )
        )
        let model = InsightsViewModel(
            noteStore: store,
            languageModel: StubDiaryLanguageModel(),
            selectedModel: .medgemma4B,
            calendar: calendar,
            now: today
        )

        let tooEarly = try #require(
            calendar.date(byAdding: .day, value: -30, to: today)
        )
        model.setFromDate(tooEarly)
        #expect(
            calendar.dateComponents(
                [.day],
                from: model.fromDate,
                to: model.toDate
            ).day == SummaryModelID.medgemma4B.maximumInsightSpanDays
        )

        await model.generateInsight()
        #expect(model.generatedInsight?.generatedFrom == model.fromDate)
        #expect(model.generatedInsight?.generatedTo == model.toDate)
        // The range the user picked reaches the prompt, and the filled prompt
        // is what gets persisted.
        #expect(model.generatedInsight?.promptText.contains("18 September") == true)
        #expect(model.generatedInsight?.promptText.contains("Creative projects") == true)
        #expect(model.generatedInsight?.promptText.contains("Finding time") == true)
        #expect(model.generatedInsight?.promptText.contains("context for what the writer may") == true)
        #expect(try await store.insights().count == 1)
    }

    @Test @MainActor
    func insightLookbackFollowsTheSelectedModel() throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let calendar = testCalendar
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))
        )
        let model = InsightsViewModel(
            noteStore: store,
            languageModel: StubDiaryLanguageModel(),
            selectedModel: .qwen3_1_7B,
            calendar: calendar,
            now: today
        )
        #expect(
            calendar.dateComponents([.day], from: model.fromDate, to: model.toDate).day == 7
        )
        #expect(model.toDate == today)

        model.setSelectedModel(.medgemma4B)
        #expect(calendar.dateComponents([.day], from: model.fromDate, to: model.toDate).day == 7)
        model.setSelectedModel(.qwen3_1_7B)
        model.setFromDate(.distantPast)
        #expect(calendar.dateComponents([.day], from: model.fromDate, to: model.toDate).day == 42)

        let farBack = try #require(calendar.date(byAdding: .day, value: -40, to: today))
        model.setFromDate(farBack)
        model.setSelectedModel(.medgemma4B)
        #expect(
            calendar.dateComponents([.day], from: model.fromDate, to: model.toDate).day == 14
        )
        #expect(model.insightSpanDescription == "2 weeks")

        let earlierEnd = try #require(calendar.date(byAdding: .day, value: -7, to: today))
        model.setToDate(earlierEnd)
        model.setFromDate(.distantPast)
        #expect(model.toDate == earlierEnd)
        #expect(calendar.dateComponents([.day], from: model.fromDate, to: model.toDate).day == 14)

        model.setToDate(.distantFuture)
        #expect(model.toDate == today)
        #expect(calendar.dateComponents([.day], from: model.fromDate, to: model.toDate).day == 14)
    }

    @Test @MainActor
    func demoDataSeederCreatesEntriesOnce() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try ProfileSeeder.seedIfNeeded(in: context)
        try DemoDataSeeder.seedIfNeeded(in: context)
        let user = try #require(await store.userProfiles().first)
        #expect(try await store.diaryEntries(profileID: user.id).count == 11)
        let insights = try await store.insights()
        #expect(insights.count == 1)
        #expect(insights.first?.text.contains("creative project") == true)
        #expect(try await store.questions(profileID: user.id).count == 4)
        #expect(user.dailyReminder == nil)

        try DemoDataSeeder.seedIfNeeded(in: context)
        #expect(try await store.diaryEntries(profileID: user.id).count == 11)
        #expect(try await store.insights().count == 1)
    }

    @Test
    func promptTemplateFillsBothPlaceholders() {
        let profile = UserProfile(
            name: "Taylor",
            interests: ["Painting", "Guitar"],
            concerns: ["Finding time"]
        )

        let filled = PromptTemplate.dailyShortSummary.filled(
            transcript: "  I left my draft unfinished.  ",
            profile: profile
        )

        #expect(!filled.contains(PromptTemplate.transcriptPlaceholder))
        #expect(!filled.contains(PromptTemplate.profilePlaceholder))
        #expect(filled.contains("TRANSCRIPT: I left my draft unfinished."))
        #expect(filled.contains("Interests: Painting; Guitar"))
        #expect(!filled.contains("Age:"))
        #expect(!filled.contains("Weight:"))
        #expect(!filled.contains("@"))
    }

    @Test
    func insightsPromptUsesOnlyNonemptyShortSummariesInDateOrder() throws {
        let profileID = UUID()
        let entries = [
            DiaryEntry(profileID: profileID, day: Date(timeIntervalSince1970: 200),
                       promptText: "PRIVATE PROMPT", summaryShort: "  I finished a sketch.  ",
                       transcriptPath: "/private/transcript.txt"),
            DiaryEntry(profileID: profileID, day: Date(timeIntervalSince1970: 100),
                       promptText: "PRIVATE PROMPT", summaryShort: "I started a new chapter."),
            DiaryEntry(profileID: profileID, day: Date(timeIntervalSince1970: 300),
                       promptText: "PRIVATE PROMPT", summaryShort: " \n ",
                       transcriptPath: "/private/unsummarised.txt")
        ]
        let summaries = entries.compactMap(DiarySummary.init)
        #expect(summaries.count == 2)
        let filled = PromptTemplate.weeklyInsights.filled(
            period: "7 to 13 September",
            summaries: summaries,
            focus: DiaryFocus(interests: ["Painting"], concerns: ["Finding time"])
        )
        #expect(!filled.contains(PromptTemplate.periodPlaceholder))
        #expect(!filled.contains(PromptTemplate.dailySummariesPlaceholder))
        #expect(filled.contains("NOTES (7 to 13 September):"))
        #expect(filled.contains("Interests: Painting"))
        #expect(filled.contains("Concerns: Finding time"))
        #expect(filled.contains("context for what the writer may"))
        #expect(filled.contains("If none"))
        #expect(filled.contains("Look back over the dated short summaries"))
        #expect(!filled.contains("PRIVATE PROMPT"))
        #expect(!filled.contains("/private/"))
        let earlier = try #require(filled.range(of: "I started a new chapter."))
        let later = try #require(filled.range(of: "I finished a sketch."))
        #expect(earlier.lowerBound < later.lowerBound)

        let withoutFocus = PromptTemplate.weeklyInsights.filled(
            period: "7 to 13 September", summaries: summaries
        )
        #expect(withoutFocus.contains("No interests or concerns specified."))
        #expect(withoutFocus.contains("draw insights only from the summaries"))
    }

    @Test @MainActor
    func profileSeederCreatesTheProfileAndItsQuestions() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try ProfileSeeder.seedIfNeeded(in: context)
        let user = try #require(await store.userProfiles().first)
        #expect(user.name == "You")

        // NoteStore sorts questions by text, so compare the set rather than
        // the seeder's order.
        let questions = try await store.questions(profileID: user.id)
        #expect(questions.map(\.text).sorted() == ProfileSeeder.questionTexts.sorted())

        // Seeding again leaves one user and one set of questions.
        try ProfileSeeder.seedIfNeeded(in: context)
        #expect(try await store.userProfiles().count == 1)
        #expect(try await store.questions(profileID: user.id).count == 4)

        var edited = user
        edited.name = "My diary"
        edited.interests = ["Painting", "Language learning"]
        edited.concerns = ["Making time for friends"]
        try await store.saveUserProfile(edited)
        try ProfileSeeder.seedIfNeeded(in: context)
        #expect(try await store.userProfile(id: user.id) == edited)
    }

    @Test @MainActor
    func promptSeederStoresBothTemplatesOnce() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataNoteStore(modelContext: context)

        try PromptSeeder.seedPrompts(in: context)
        try PromptSeeder.seedPrompts(in: context)

        let texts = try await store.prompts().map(\.text)
        #expect(texts.count == 2)
        #expect(texts.contains(PromptTemplate.dailyShortSummary.text))
        #expect(texts.contains(PromptTemplate.weeklyInsights.text))
    }

    @Test
    func profileDescriptionOmitsUnspecifiedDetails() {
        let sparse = UserProfile(name: "Sam")

        let description = sparse.promptDescription

        #expect(description == "Name: Sam\nNo interests or concerns specified.")
        #expect(!description.contains("Age"))
        #expect(!description.contains("Weight"))
        #expect(UserProfile(name: "").promptDescription
            == "No interests or concerns specified.")
    }

    @Test
    func summaryTextStripsWhatTheModelWrapsAroundASentence() {
        let expected = "I slept badly and woke twice."

        #expect(SummaryText.clean(expected) == expected)
        #expect(SummaryText.clean("  \(expected)\n\n") == expected)
        #expect(SummaryText.clean("\"\(expected)\"") == expected)
        #expect(SummaryText.clean("Short summary: \(expected)") == expected)
        #expect(SummaryText.clean("short_summary: \"\(expected)\"") == expected)
        #expect(SummaryText.clean("```\n\(expected)\n```") == expected)
    }

    @Test
    func summaryTextLeavesAPartialSentenceAlone() {
        // Mid-stream: the opening quote goes so the screen never shows one, and
        // the unfinished words are left exactly as they arrived.
        #expect(SummaryText.clean("\"I slept badly and") == "I slept badly and")
        #expect(SummaryText.clean("I slept") == "I slept")
        #expect(SummaryText.clean("") == "")
        // A quotation the user actually made is not a wrapper.
        #expect(
            SummaryText.clean("I told them \"I am fine\" and left.")
                == "I told them \"I am fine\" and left."
        )
    }

    @Test @MainActor
    func promptSeederKeepsCustomPromptsWhenSeeding() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        context.insert(PromptRecord(prompt: Prompt(text: "My custom prompt")))
        try context.save()
        try PromptSeeder.seedPrompts(in: context)
        try PromptSeeder.seedPrompts(in: context)
        let texts = try context.fetch(FetchDescriptor<PromptRecord>()).map(\.text)
        #expect(texts.count == 3)
        #expect(texts.contains("My custom prompt"))
        #expect(texts.contains(PromptTemplate.dailyShortSummary.text))
        #expect(texts.contains(PromptTemplate.weeklyInsights.text))
    }

    @Test @MainActor
    func dailyDetailsGeneratesOneSummaryAndReusesIt() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let user = UserProfile(name: "Taylor")
        try await store.saveUserProfile(user)
        let transcript = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: transcript) }
        try "I had a steady day.".write(to: transcript, atomically: true, encoding: .utf8)
        let entry = DiaryEntry(profileID: user.id, day: Date(), promptText: "",
                               transcriptPath: transcript.path)
        try await store.saveDiaryEntry(entry)
        let languageModel = StubDiaryLanguageModel()
        let details = DailyTangentDetailsViewModel(noteStore: store, languageModel: languageModel,
                                                  diaryID: entry.id)
        await details.start()
        await details.start()
        #expect(await languageModel.shortSummaryCalls == 1)
        let saved = try #require(await store.diaryEntry(id: entry.id))
        #expect(saved.summaryShort == "I had a steady day.")
        #expect(saved.promptText == "short prompt")
        #expect(details.summaryDisplay == .written(saved.summaryShort))
    }

    @Test @MainActor
    func insightsSkipEntriesWithoutSummaries() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let store = SwiftDataNoteStore(modelContext: container.mainContext)
        let user = UserProfile(name: "Taylor")
        try await store.saveUserProfile(user)
        let entry = DiaryEntry(profileID: user.id, day: Date(), promptText: "private prompt",
                               summaryShort: " \n ", transcriptPath: "/private/transcript.txt")
        try await store.saveDiaryEntry(entry)
        let languageModel = StubDiaryLanguageModel()
        let model = InsightsViewModel(noteStore: store, languageModel: languageModel)
        await model.generateInsight()
        #expect(model.generationError == DiaryLanguageModelError.notEnoughEntries.localizedDescription)
        #expect(try await store.insights().isEmpty)
        #expect(await languageModel.receivedSummaries.isEmpty)

        var completed = entry
        completed.summaryShort = "I felt rested."
        try await store.saveDiaryEntry(completed)
        await model.generateInsight()
        #expect(await languageModel.receivedSummaries.map(\.text) == ["I felt rested."])
        let insight = try #require(model.generatedInsight)
        #expect(insight.promptText.contains("I felt rested."))
        #expect(!insight.promptText.contains("private prompt"))
        #expect(!insight.promptText.contains("/private/transcript.txt"))
    }

    @Test @MainActor
    func existingDiaryMigratesWithoutLosingShortSummary() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "diary.store")
        let entry = DiaryEntry(profileID: UUID(), day: Date(),
                               questions: [DiaryQuestion(text: "What stood out to you today?")],
                               promptText: "Original short prompt", summaryShort: "I finished a sketch.",
                               transcriptPath: "/private/original.txt")
        try autoreleasepool {
            let schema = Schema(TangentSchemaV0.models)
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: url)
            ])
            container.mainContext.insert(TangentSchemaV0.DiaryEntryRecord(entry: entry))
            try container.mainContext.save()
        }
        try autoreleasepool {
            let container = try TangentModelContainer.make(storeURL: url)
            let records = try container.mainContext.fetch(FetchDescriptor<DiaryEntryRecord>())
            #expect(records.count == 1)
            #expect(records.first?.domainModel == entry)
        }
        // Verify the old field is removed from the physical store, not just hidden in the UI.
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, "PRAGMA table_info(ZDIARYENTRYRECORD)", -1,
                                   &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.append(String(cString: sqlite3_column_text(statement, 1)))
        }
        #expect(columns.contains("ZSUMMARYSHORT"))
        #expect(!columns.contains("ZSUMMARYLONG"))
    }

    @Test @MainActor
    func settingsSaveGeneralInterestsAndConcerns() async throws {
        let container = try TangentModelContainer.make(inMemory: true)
        let context = container.mainContext
        try ProfileSeeder.seedIfNeeded(in: context)
        let store = SwiftDataNoteStore(modelContext: context)
        let settings = SettingsViewModel(noteStore: store, reminderScheduler: UnavailableReminderScheduler())
        await settings.load()
        settings.name = "  Alex  "
        settings.interests = "Painting\n Learning Spanish \n"
        settings.concerns = "Finishing my project\n\n"
        await settings.saveProfile()
        try ProfileSeeder.seedIfNeeded(in: context)
        let profile = try #require(await store.userProfiles().first)
        #expect(profile.name == "Alex")
        #expect(profile.interests == ["Painting", "Learning Spanish"])
        #expect(profile.concerns == ["Finishing my project"])
        let summaries = [DiaryEntry(profileID: profile.id, day: Date(), promptText: "",
                                    summaryShort: "I finished a sketch.")].compactMap(DiarySummary.init)
        let prompt = PromptTemplate.weeklyInsights.filled(period: "Today", summaries: summaries,
                                                          focus: profile.focus)
        #expect(prompt.contains("Painting; Learning Spanish"))
        #expect(prompt.contains("Finishing my project"))
        #expect(prompt.contains("I finished a sketch."))
        #expect(prompt.contains("context for what the writer may"))
    }

    @Test @MainActor
    func profileRenamePreservesExistingDataAndReferences() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "profile.store")
        let profile = UserProfile(name: "Alex", interests: ["Photography"],
                                  concerns: ["Finishing a project"], dailyReminder: Date(timeIntervalSince1970: 100))
        let entry = DiaryEntry(profileID: profile.id, day: Date(), promptText: "original prompt",
                               summaryShort: "I finished a photo series.", transcriptPath: "/private/entry.txt")
        let question = Question(profileID: profile.id, promptText: "custom", text: "What did you create?")
        try autoreleasepool {
            // Reproduce the unversioned database written by the previous app.
            let schema = Schema(TangentSchemaV1.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let profileRecord = TangentSchemaV1.UserProfileRecord(profile: profile)
            profileRecord.age = 30
            profileRecord.weight = 68
            profileRecord.gender = "Non-binary"
            profileRecord.email = "alex@example.com"
            container.mainContext.insert(profileRecord)
            container.mainContext.insert(TangentSchemaV1.DiaryEntryRecord(entry: entry))
            container.mainContext.insert(TangentSchemaV1.QuestionRecord(question: question))
            try container.mainContext.save()
        }
        try autoreleasepool {
            let container = try TangentModelContainer.make(storeURL: url)
            let context = container.mainContext
            #expect(try context.fetch(FetchDescriptor<UserProfileRecord>()).map(\.domainModel) == [profile])
            #expect(try context.fetch(FetchDescriptor<DiaryEntryRecord>()).map(\.domainModel) == [entry])
            #expect(try context.fetch(FetchDescriptor<QuestionRecord>()).map(\.domainModel) == [question])
            try ProfileSeeder.seedIfNeeded(in: context)
            #expect(try context.fetch(FetchDescriptor<UserProfileRecord>()).map(\.domainModel) == [profile])
        }
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, "PRAGMA table_info(ZUSERPROFILERECORD)", -1,
                                   &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.append(String(cString: sqlite3_column_text(statement, 1)))
        }
        #expect(columns.contains("ZNAME"))
        #expect(!columns.contains("ZAGE"))
        #expect(!columns.contains("ZWEIGHT"))
        #expect(!columns.contains("ZGENDER"))
        #expect(!columns.contains("ZEMAIL"))
    }

    @Test
    func supportedModelsHaveStableIdentitiesAndSmallQwenChoices() {
        #expect(SummaryModelID.default == .qwen3_0_6B)
        #expect(Set(SummaryModelID.allCases.map(\.repoID)).count == SummaryModelID.allCases.count)
        #expect(SummaryModelID.qwen3_0_6B.approximateDownloadBytes < 400_000_000)
        #expect(SummaryModelID.qwen2_5_0_5B.approximateDownloadBytes < SummaryModelID.qwen3_0_6B.approximateDownloadBytes)
        #expect(SummaryModelID.qwen3_0_6B.disablesThinking)
        #expect(SummaryModelID.qwen3_1_7B.disablesThinking)
        #expect(!SummaryModelID.gemma3_1B.disablesThinking)
        #expect(SummaryModelID(rawValue: "gemma3-1b-qat-4bit") == .gemma3_1B)
        #expect(SummaryModelID(rawValue: "medgemma-1.5-4b-it-4bit") == .medgemma4B)
        #expect(SummaryModelID.qwen2_5_0_5B.contextWindowTokens == 32_768)
        #expect(SummaryModelID.qwen3_0_6B.contextWindowTokens == 40_960)
        #expect(SummaryModelID.qwen3_1_7B.contextWindowTokens == 40_960)
        #expect(SummaryModelID.gemma3_1B.contextWindowTokens == 32_768)
        #expect(SummaryModelID.medgemma4B.contextWindowTokens == 131_072)
        #expect(SummaryModelID.qwen2_5_0_5B.maximumInsightSpanDays == 21)
        #expect(SummaryModelID.qwen3_0_6B.maximumInsightSpanDays == 28)
        #expect(SummaryModelID.gemma3_1B.maximumInsightSpanDays == 28)
        #expect(SummaryModelID.qwen3_1_7B.maximumInsightSpanDays == 42)
        #expect(SummaryModelID.medgemma4B.maximumInsightSpanDays == 14)
        #expect(SummaryModelID.medgemma4B.maximumInsightSpanDays < SummaryModelID.qwen3_1_7B.maximumInsightSpanDays)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

/// Stands in for the model so the view model's own behaviour can be tested
/// without a 2.5 GB download.
private actor StubDiaryLanguageModel: DiaryLanguageModel {
    private(set) var shortSummaryCalls = 0
    private(set) var receivedSummaries: [DiarySummary] = []

    func prepare() async {}

    func generateShortSummary(
        transcript: String,
        profile: UserProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        shortSummaryCalls += 1
        onPartial?("I had a")
        return GeneratedText(text: "I had a steady day.", promptText: "short prompt")
    }

    func generateInsights(
        from summaries: [DiarySummary],
        focus: DiaryFocus,
        period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        receivedSummaries = summaries
        onPartial?("You seem")
        return GeneratedText(
            text: "You seem steadier at weekends.",
            promptText: PromptTemplate.weeklyInsights.filled(period: period, summaries: summaries, focus: focus)
        )
    }
}
