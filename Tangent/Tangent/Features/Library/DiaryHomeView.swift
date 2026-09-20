import SwiftUI

struct DiaryHomeView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var model: DiaryHomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAddRecordOptions = false

    private let calendar: Calendar
    private let openEntry: (UUID) -> Void
    private let openRecord: () -> Void
    private let openEmptyDay: (Date) -> Void
    private let openSettings: () -> Void

    init(
        noteStore: any NoteStore,
        modelCatalog: (any ModelCatalog)? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        openEntry: @escaping (UUID) -> Void,
        openRecord: @escaping () -> Void,
        openEmptyDay: @escaping (Date) -> Void,
        openSettings: @escaping () -> Void
    ) {
        _model = StateObject(
            wrappedValue: DiaryHomeViewModel(
                noteStore: noteStore,
                modelCatalog: modelCatalog,
                calendar: calendar
            )
        )
        self.calendar = calendar
        self.openEntry = openEntry
        self.openRecord = openRecord
        self.openEmptyDay = openEmptyDay
        self.openSettings = openSettings
    }

    var body: some View {
        Group {
            if isFirstEntry {
                firstEntryAction
            } else {
                diaryTimeline
            }
        }
        .background(Color.tangentWash)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(action: openSettings)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbarBackgroundVisibility(.hidden, for: .tabBar)
        .task(id: preferences.aiEnabled) {
            await model.load()
        }
        .onAppear {
            Task { await model.load() }
        }
    }

    private var diaryTimeline: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    ForEach(model.days) { day in
                        dayRow(day)
                            .id(day.id)
                    }

                    addRecordButton

                    if let loadError = model.loadError {
                        Text(loadError)
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(Color.tangentInk.opacity(0.6))
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            .refreshable {
                await model.load()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var firstEntryAction: some View {
        VStack(spacing: 22) {
            todayRecordCard(on: calendar.startOfDay(for: Date()))
            addRecordButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var addRecordButton: some View {
        Group {
            if model.days.contains(where: { calendar.isDateInToday($0.date) && !$0.entries.isEmpty }) {
                Button { showsAddRecordOptions = true } label: { addRecordIcon }
                    .accessibilityLabel("Add a tangent")
                    .popover(isPresented: $showsAddRecordOptions) {
                        VStack(spacing: 0) {
                            Button("Record for today") {
                                showsAddRecordOptions = false
                                openRecord()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            Divider()
                            pastDatePicker
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay {
                                    Color(uiColor: .systemBackground).allowsHitTesting(false)
                                    Text("Record for a past day")
                                        .foregroundStyle(Color.tangentPurple)
                                        .lineLimit(1)
                                        .allowsHitTesting(false)
                                }
                        }
                        .frame(width: 240)
                        .padding(8)
                        .presentationCompactAdaptation(.popover)
                    }
            } else {
                pastDatePicker
                    .frame(width: 48, height: 48)
                    .clipped()
                    .overlay {
                        Color.tangentWash.allowsHitTesting(false)
                        addRecordIcon.allowsHitTesting(false)
                    }
            }
        }
        .accessibilityIdentifier("add-record")
        .disabled(model.isLoading)
    }

    private var pastDatePicker: some View {
        DatePicker(
            "Record for a past day",
            selection: Binding(
                // Today is the neutral selection. Every past date is a change.
                get: { Date() },
                set: { day in
                    guard !calendar.isDateInToday(day) else { return }
                    showsAddRecordOptions = false
                    openEmptyDay(calendar.startOfDay(for: day))
                }
            ),
            in: ...Date(),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .accessibilityIdentifier("past-record-picker")
    }

    private var addRecordIcon: some View {
        Image(systemName: "plus.circle")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(Color.gray)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }

    private var recordPrompt: some View {
        Text("Record today’s Tangent")
            .font(.system(.body, design: .serif, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var isFirstEntry: Bool {
        model.days.count == 1 && model.days.first?.entries.isEmpty == true
    }

    @ViewBuilder
    private func dayRow(_ day: DiaryTimelineDay) -> some View {
        if !day.entries.isEmpty {
            VStack(spacing: 22) {
                ForEach(day.entries) { entry in
                    filledDayCard(entry, on: day.date)
                        .accessibilityIdentifier("diary-entry-\(entry.id.uuidString)")
                }
            }
        } else if calendar.isDateInToday(day.date) {
            todayRecordCard(on: day.date)
        } else {
            dayCard(on: day.date, chrome: .empty, action: { openEmptyDay(day.date) }) {
                Text("Fill in Tangent")
                    .font(.system(.body, design: .serif, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("\(fullDate(day.date)). Fill in Tangent")
            .accessibilityHint("Opens the Record Tangent screen for this day")
        }
    }

    private func filledDayCard(_ entry: DiaryEntry, on date: Date) -> some View {
        // An entry whose summary has not been written yet — the model failed,
        // or none was available — still has a transcript worth opening, so the
        // row says so rather than sitting blank.
        let hasSummary = !entry.summaryShort.isEmpty
        let placeholder = model.needsModel
            ? "Download your preferred model in Settings to generate a summary."
            : "Summary not written yet"
        let summary = preferences.aiEnabled
            ? (hasSummary ? entry.summaryShort : placeholder)
            : (model.transcriptPreviews[entry.id] ?? "Transcript not available")

        return dayCard(on: date, chrome: .filled, action: { openEntry(entry.id) }) {
            Text(summary)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Color.tangentInk.opacity(!preferences.aiEnabled || hasSummary ? 1 : 0.5))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("\(fullDate(date)). \(summary)")
        .accessibilityHint("Opens daily Tangent details")
    }

    private func todayRecordCard(on date: Date) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let wave = sin(time * (2 * .pi / 2.2))
            let scale = 1 + 0.044 * wave

            dayCard(on: date, chrome: .today, action: openRecord) {
                recordPrompt
            }
            .scaleEffect(scale)
        }
        .accessibilityLabel("\(fullDate(date)). Record today’s Tangent")
        .accessibilityHint("Opens the Record Tangent screen")
    }

    @ViewBuilder
    private func dayCard<Content: View>(
        on date: Date,
        chrome: DayCardChrome,
        action: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action ?? {}) {
            HStack(spacing: 12) {
                dateLabel(for: date, chrome: chrome)
                    .frame(width: 38)

                Divider()
                    .overlay(chrome.dividerColor)
                    .frame(height: 46)

                content()
                    .foregroundStyle(chrome.contentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(chrome.background)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(chrome.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
        .frame(maxWidth: 288)
        .frame(maxWidth: .infinity)
    }

    private func dateLabel(for date: Date, chrome: DayCardChrome) -> some View {
        VStack(spacing: 1) {
            Text(date, format: .dateTime.day())
                .font(.system(.body, design: .serif, weight: .medium))
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.system(.caption2, design: .serif, weight: .medium))
        }
        .foregroundStyle(chrome.dateColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullDate(date))
    }

    private func fullDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }
}

private enum DayCardChrome {
    case filled
    case empty
    case today

    var background: Color {
        switch self {
        case .filled:
            return Color.tangentPaper.opacity(0.82)
        case .empty:
            return Color.tangentPaper.opacity(0.48)
        case .today:
            return Color.tangentPurple
        }
    }

    var stroke: Color {
        switch self {
        case .filled:
            return Color.tangentInk.opacity(0.06)
        case .empty:
            return Color.tangentInk.opacity(0.04)
        case .today:
            return Color.white.opacity(0.18)
        }
    }

    var dateColor: Color {
        switch self {
        case .filled:
            return Color.tangentInk.opacity(0.7)
        case .empty:
            return Color.tangentInk.opacity(0.38)
        case .today:
            return .white
        }
    }

    var dividerColor: Color {
        switch self {
        case .filled:
            return Color.tangentInk.opacity(0.16)
        case .empty:
            return Color.tangentInk.opacity(0.08)
        case .today:
            return Color.white.opacity(0.4)
        }
    }

    var contentColor: Color {
        switch self {
        case .filled:
            return Color.tangentInk
        case .empty:
            return Color.tangentInk.opacity(0.38)
        case .today:
            return .white
        }
    }
}
