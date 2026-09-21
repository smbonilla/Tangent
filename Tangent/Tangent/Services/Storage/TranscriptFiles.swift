import Foundation

/// Store document-relative references so app updates/restores cannot strand files
/// behind an old sandbox UUID. Also resolve references written by older versions.
enum TranscriptFiles {
    static func url(for path: String, documents: URL = .documentsDirectory) -> URL {
        guard path.hasPrefix("/") else { return documents.appending(path: path) }
        let original = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) { return original }
        if let range = path.range(of: "/Documents/", options: .backwards) {
            return documents.appending(path: String(path[range.upperBound...]))
        }
        return original
    }

    static func reference(for url: URL, documents: URL = .documentsDirectory) -> String {
        let prefix = documents.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }

    static func checkpointURL(for audio: URL) -> URL {
        URL.documentsDirectory.appending(path: "Transcripts", directoryHint: .isDirectory)
            .appending(path: audio.deletingPathExtension().lastPathComponent + ".txt")
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Final segments extend the checkpoint instead of rewriting the whole diary
/// on every result. A retry truncates any failed append to its last saved length.
/// Full revisions (including file recovery) still use atomic replacement.
final class TranscriptCheckpoint: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var lastText = ""
    private var savedBytes: UInt64 = 0

    init(url: URL) { self.url = url }

    func save(_ text: String) throws {
        try lock.withLock {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text != lastText else { return }
            if !lastText.isEmpty, text.hasPrefix(lastText), FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.truncate(atOffset: savedBytes)
                try handle.seek(toOffset: savedBytes)
                let suffix = Data(text.dropFirst(lastText.count).utf8)
                try handle.write(contentsOf: suffix)
                try handle.synchronize()
                savedBytes += UInt64(suffix.count)
            } else {
                try TranscriptFiles.write(text, to: url)
                savedBytes = UInt64(text.utf8.count)
            }
            lastText = text
        }
    }
}
