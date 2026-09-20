import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @StateObject private var model: InsightsViewModel
    private let modelCatalog: (any ModelCatalog)?
    private let openSettings: (() -> Void)?

    init(
        noteStore: any NoteStore,
        languageModel: any DiaryLanguageModel,
        modelCatalog: (any ModelCatalog)? = nil,
        openSettings: (() -> Void)? = nil
    ) {
        self.modelCatalog = modelCatalog
        self.openSettings = openSettings
        _model = StateObject(
            wrappedValue: InsightsViewModel(
                noteStore: noteStore,
                languageModel: languageModel,
                selectedModel: modelCatalog?.selectedModel ?? .default
            )
        )
    }

    var body: some View {
        insightsContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.tangentInk)
        .background(Color.tangentWash)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let openSettings {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(action: openSettings)
                }
            }
        }
        .onAppear {
            model.setSelectedModel(modelCatalog?.selectedModel ?? .default)
        }
    }

    private var insightsContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    generator

                    if preferences.aiEnabled && model.isGenerating {
                        // The words themselves say it is working, so there is
                        // nothing to spin until the first one arrives.
                        if model.isWaiting {
                            Text("Waiting for model…").foregroundStyle(.secondary)
                        } else if model.streamingInsight.isEmpty {
                            waitingIndicator
                        } else {
                            streamingBlock(model.streamingInsight)
                        }
                    } else if let insight = model.generatedInsight {
                        insightBlock(insight)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(
                    maxWidth: .infinity,
                    minHeight: proxy.size.height,
                    alignment: .center
                )
            }
        }
    }

    private var waitingIndicator: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let step = Int(
                context.date.timeIntervalSinceReferenceDate / 0.4
            ) % 3 + 1
            Text(String(repeating: ".", count: step))
                .font(.system(.title, design: .monospaced, weight: .semibold))
                .foregroundStyle(Color.tangentPurple)
                .frame(width: 52, height: 44, alignment: .leading)
                .accessibilityLabel("Generating insight")
        }
    }

    private var generator: some View {
        VStack(spacing: 18) {
            Text("Generate insight")
                .font(.system(.title2, weight: .semibold))

            DatePicker(
                "From",
                selection: Binding(
                    get: { model.fromDate },
                    set: model.setFromDate
                ),
                in: model.earliestFromDate...model.toDate,
                displayedComponents: .date
            )

            DatePicker(
                "To",
                selection: Binding(
                    get: { model.toDate },
                    set: model.setToDate
                ),
                in: ...model.latestToDate,
                displayedComponents: .date
            )

            Button {
                Task {
                    model.setSelectedModel(modelCatalog?.selectedModel ?? .default)
                    await model.generateInsight()
                }
            } label: {
                Group {
                    if preferences.aiEnabled && model.isWaiting {
                        Text("Waiting…")
                    } else if preferences.aiEnabled && model.isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Generate")
                    }
                }
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.tangentPurple)
            .disabled(!preferences.aiEnabled || model.isGenerating)
            .accessibilityIdentifier("generate-insight")

            if !preferences.aiEnabled {
                Button {
                    openSettings?()
                } label: {
                    Text("Download model in Settings for this functionality.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Settings")
            } else if let generationError = model.generationError {
                Text(generationError)
                    .font(.system(.footnote))
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(Color.tangentPaper.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tangentInk.opacity(0.06), lineWidth: 1)
        }
    }

    private func streamingBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.body))
            .foregroundStyle(Color.tangentInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.tangentPaper.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.tangentInk.opacity(0.06), lineWidth: 1)
            }
            .frame(maxWidth: 420)
            .animation(.easeOut(duration: 0.15), value: text)
    }

    private func insightBlock(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(insight.text)
                .font(.system(.body))
                .foregroundStyle(Color.tangentInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(rangeText(for: insight))
                .font(.system(.caption))
                .foregroundStyle(Color.tangentInk.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.tangentPaper.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tangentInk.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func rangeText(for insight: Insight) -> String {
        let from = insight.generatedFrom.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
        let to = insight.generatedTo.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
        return from == to ? from : "\(from) – \(to)"
    }
}

#Preview {
    let container = try! TangentModelContainer.make(inMemory: true)
    NavigationStack {
        InsightsView(
            noteStore: SwiftDataNoteStore(modelContext: container.mainContext),
            languageModel: UnavailableDiaryLanguageModel(),
            modelCatalog: MLXModelCatalog()
        )
    }
    .environmentObject(AppPreferences(defaults: UserDefaults(suiteName: "TangentPreview")!))
}
