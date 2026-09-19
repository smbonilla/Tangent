import Foundation
#if TANGENT_LEGACY_MLX
import Hub
#else
import HuggingFace
#endif

/// Where Tangent keeps downloaded model weights, and what it knows about them.
///
/// Deliberately not the Hugging Face default location: on a sandboxed app that
/// resolves inside `Library/Caches`, which iOS may purge under storage
/// pressure — losing a 2.5 GB download the user waited for. Application Support
/// survives, and is excluded from backup so the weights never inflate an iCloud
/// backup.
enum ModelStorage {
    static let directory: URL = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory

        var directory = base
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "huggingface", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)

        return directory
    }()

    #if TANGENT_LEGACY_MLX
    static func client() -> HubApi {
        HubApi(downloadBase: directory.appending(path: "legacy"), useOfflineMode: false)
    }

    static func modelDirectory(_ model: SummaryModelID) -> URL {
        client().localRepoLocation(Hub.Repo(id: model.repoID))
    }

    private static func completionMarker(_ model: SummaryModelID) -> URL {
        modelDirectory(model).appending(path: ".tangent-download-complete")
    }

    static func markDownloaded(_ model: SummaryModelID) throws {
        try Data().write(to: completionMarker(model), options: .atomic)
    }

    static func isDownloaded(_ model: SummaryModelID) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: modelDirectory(model), includingPropertiesForKeys: nil
        )) ?? []
        return FileManager.default.fileExists(atPath: completionMarker(model).path)
            && files.contains { $0.pathExtension == "safetensors" }
            && files.contains { $0.lastPathComponent == "config.json" }
    }

    static func bytesOnDisk(_ model: SummaryModelID) -> Int64 {
        size(of: modelDirectory(model))
    }

    static func remove(_ model: SummaryModelID) throws {
        let url = modelDirectory(model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    #else
    static var cache: HubCache {
        HubCache(cacheDirectory: directory)
    }

    static func client() -> HubClient {
        HubClient(cache: cache)
    }

    static func repoID(for model: SummaryModelID) -> Repo.ID? {
        let parts = model.repoID.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Repo.ID(namespace: String(parts[0]), name: String(parts[1]))
    }

    /// True only when a snapshot holds both weights and a config, so a download
    /// interrupted half way is not mistaken for a usable model.
    static func isDownloaded(_ model: SummaryModelID) -> Bool {
        guard let repo = repoID(for: model) else { return false }
        let snapshots = cache.snapshotsDirectory(repo: repo, kind: .model)
        let revisions = (try? FileManager.default.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: nil
        )) ?? []

        return revisions.contains { revision in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: revision,
                includingPropertiesForKeys: nil
            )) ?? []
            return files.contains { $0.pathExtension == "safetensors" }
                && files.contains { $0.lastPathComponent == "config.json" }
        }
    }

    /// Size of the blobs, which hold the real bytes. Snapshot entries are
    /// symlinks into them and would double-count.
    static func bytesOnDisk(_ model: SummaryModelID) -> Int64 {
        guard let repo = repoID(for: model) else { return 0 }
        return size(of: cache.blobsDirectory(repo: repo, kind: .model))
    }

    static func remove(_ model: SummaryModelID) throws {
        guard let repo = repoID(for: model) else { return }
        let manager = FileManager.default
        for url in [
            cache.repoDirectory(repo: repo, kind: .model),
            cache.metadataDirectory(repo: repo, kind: .model),
        ] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    #endif

    private static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// The model Tangent summarises with. Held in UserDefaults so the catalog on
/// the main actor and the generator on its own actor can both read it without
/// one having to wait for the other.
enum SelectedModelStore {
    private static let key = "tangent.summaryModel"

    static var selected: SummaryModelID {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let model = SummaryModelID(rawValue: raw)
        else {
            return .default
        }
        return model
    }

    static func select(_ model: SummaryModelID) {
        UserDefaults.standard.set(model.rawValue, forKey: key)
    }
}
