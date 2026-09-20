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

/// Recognition invokes this on its serial queue. Atomic replacements preserve
/// the last successful checkpoint if a later write fails or the app terminates.
final class TranscriptCheckpoint: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var lastText = ""

    init(url: URL) { self.url = url }

    func save(_ text: String) throws {
        try lock.withLock {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text != lastText else { return }
            try TranscriptFiles.write(text, to: url)
            lastText = text
        }
    }
}
