import Foundation
import UIKit
#if TANGENT_LEGACY_MLX
import Hub
#else
import HuggingFace
import MLXHuggingFace
#endif
import MLXLMCommon
import Tokenizers

/// Downloads and removes model weights, and remembers which model Tangent
/// summarises with.
///
/// Downloads use MLX's `resolve`, which fetches exactly the files the model
/// factory will later ask for and stops there — nothing is loaded into memory,
/// so Settings never holds 2.5 GB of weights.
@MainActor
final class MLXModelCatalog: ModelCatalog {
    private let resources: ModelResourceGuard

    init(resources: ModelResourceGuard = ModelResourceGuard()) { self.resources = resources }

    private var downloads: [SummaryModelID: Task<Void, Error>] = [:] {
        didSet { updateIdleTimer() }
    }
    private var previousIdleTimerDisabled: Bool?
    private var downloadIDs: [SummaryModelID: UUID] = [:]
    private var progresses: [SummaryModelID: DownloadProgress] = [:]

    private func updateIdleTimer() {
        if downloads.isEmpty {
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
                self.previousIdleTimerDisabled = nil
            }
        } else if previousIdleTimerDisabled == nil {
            // Keep the screen awake until the last active download finishes or is cancelled.
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    var selectedModel: SummaryModelID {
        SelectedModelStore.selected
    }

    func select(_ model: SummaryModelID) {
        SelectedModelStore.select(model)
    }

    func state(of model: SummaryModelID) async -> ModelDownloadState {
        if downloads[model] != nil {
            return .downloading(
                progresses[model] ?? DownloadProgress(completedBytes: 0, totalBytes: 0)
            )
        }
        guard ModelStorage.isDownloaded(model) else {
            return .notDownloaded
        }
        return .ready(bytesOnDisk: ModelStorage.bytesOnDisk(model))
    }

    func download(
        _ model: SummaryModelID,
        onProgress: @escaping @MainActor (DownloadProgress) -> Void
    ) async throws {
        if let existing = downloads[model] {
            return try await existing.value
        }

        if ModelStorage.isDownloaded(model) { return }
        let reserved = downloads.keys.reduce(Int64(0)) { $0 + ModelResourceGuard.downloadBudget(for: $1) }
        try resources.checkDownload(model, reservedBytes: reserved)
        let downloadID = UUID()
        downloadIDs[model] = downloadID
        progresses[model] = DownloadProgress(completedBytes: 0, totalBytes: 0)
        let task = Task<Void, Error> { [weak self] in
            #if TANGENT_LEGACY_MLX
            _ = try await ModelStorage.client().snapshot(
                from: model.repoID,
                matching: ["*.safetensors", "*.json", "*.model", "*.jinja", "*.txt"],
                progressHandler: { progress in
                    let update = DownloadProgress(
                        completedBytes: 0,
                        totalBytes: 0,
                        completedFraction: progress.fractionCompleted
                    )
                    Task { @MainActor in
                        guard let self, self.downloadIDs[model] == downloadID else { return }
                        self.progresses[model] = update
                        onProgress(update)
                    }
                }
            )
            try Task.checkCancellation()
            try ModelStorage.markDownloaded(model)
            #else
            _ = try await resolve(
                configuration: model.configuration,
                from: #hubDownloader(ModelStorage.client()),
                useLatest: false,
                progressHandler: { progress in
                    // Read the counts off Progress here: it is not Sendable and
                    // must not cross to the main actor. The hub weights each
                    // file by its size, so these are bytes.
                    let update = DownloadProgress(
                        completedBytes: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    )
                    Task { @MainActor in
                        guard let self, self.downloadIDs[model] == downloadID else { return }
                        self.progresses[model] = update
                        onProgress(update)
                    }
                }
            )
            #endif
        }
        downloads[model] = task

        defer {
            if downloadIDs[model] == downloadID {
                downloads[model] = nil
                progresses[model] = nil
                downloadIDs[model] = nil
            }
        }
        do {
            try await resources.monitoring(storage: true) {
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            }
        } catch {
            task.cancel()
            throw error
        }
    }

    func cancelDownload(_ model: SummaryModelID) {
        downloadIDs[model] = nil
        downloads[model]?.cancel()
        downloads[model] = nil
        progresses[model] = nil
    }

    /// Deleting the selected model does not change the selection. The next
    /// summary then fails with "not downloaded", which is the truth.
    func delete(_ model: SummaryModelID) async throws {
        cancelDownload(model)
        try ModelStorage.remove(model)
    }
}
