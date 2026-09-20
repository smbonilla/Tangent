import SwiftUI

/// Shared, explicit model setup for onboarding and Settings.
struct AIModelSetupView: View {
    @ObservedObject var model: SettingsViewModel
    var usesFormRows = false

    var body: some View {
        if usesFormRows {
            setupControls
        } else {
            VStack(alignment: .leading, spacing: 16) { setupControls }
        }
    }

    private var setupControls: some View {
        Group {
            Toggle("AI summaries", isOn: Binding(
                get: { model.aiRequested },
                set: model.setAIRequested
            ))
            .tint(Color.tangentPurple)
            .accessibilityIdentifier("ai-enabled")
            .disabled(!model.aiSetupLoaded)

            if model.aiRequested {
                AIRequirementsNote()
                if !model.selectedModelIsReady {
                    Text("AI summaries will stay off until a model is downloaded")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ai-setup-required")
                }
                ForEach(SummaryModelID.allCases) { summaryModel in
                    modelRow(summaryModel)
                    if !usesFormRows && summaryModel != SummaryModelID.allCases.last { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ summaryModel: SummaryModelID) -> some View {
        let state = model.modelStates[summaryModel] ?? .notDownloaded
        let isSelected = model.selectedModel == summaryModel

        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.chooseModel(summaryModel)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(summaryModel.displayName)
                        .font(.system(.body, weight: isSelected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.tangentPurple)
                            .accessibilityLabel("Selected")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("model-\(summaryModel.rawValue)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            modelStatus(summaryModel, state: state)
        }
        .padding(.vertical, 4)
    }

    /// Everything about the weights — where they are and what to do about it —
    /// stays inside the model's own card. No sheet, no dialog.
    @ViewBuilder
    private func modelStatus(
        _ summaryModel: SummaryModelID,
        state: ModelDownloadState
    ) -> some View {
        switch state {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.stateDescription(for: summaryModel))
                        .font(.footnote)
                        .foregroundStyle(Color.tangentInk.opacity(0.75))
                }
                // The bar only appears once the total is known; before that the
                // spinner carries the "something is happening" job on its own.
                if progress.totalBytes > 0 || progress.completedFraction != nil {
                    ProgressView(value: progress.fraction)
                        .tint(Color.tangentPurple)
                }
                modelButton("Cancel", role: nil) {
                    Task { await model.cancelDownload(summaryModel) }
                }
            }

        case .ready:
            VStack(alignment: .leading, spacing: 7) {
                statusLine(summaryModel)
                modelButton("Remove", role: .destructive) {
                    Task { await model.deleteModel(summaryModel) }
                }
            }

        case .notDownloaded, .failed:
            VStack(alignment: .leading, spacing: 7) {
                if case .failed = state {
                    statusLine(summaryModel)
                }
                modelButton(downloadLabel(for: summaryModel), role: nil) {
                    Task { await model.download(summaryModel) }
                }
            }
        }
    }

    private func statusLine(_ summaryModel: SummaryModelID) -> some View {
        Text(model.stateDescription(for: summaryModel))
            .font(.footnote)
            .foregroundStyle(Color.tangentInk.opacity(0.6))
    }

    /// The size sits on the button, so the user reads what the tap will cost
    /// before making it.
    private func downloadLabel(for summaryModel: SummaryModelID) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: summaryModel.approximateDownloadBytes,
            countStyle: .file
        )
        return "Download · \(size)"
    }

    private func modelButton(
        _ title: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, role: role, action: action)
            .font(.system(.subheadline, weight: .medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(role == .destructive ? .red : Color.tangentPurple)
    }
}
