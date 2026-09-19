import Foundation
import CryptoKit
import SwiftData

/// Keeps the app's prompts in the PROMPT table.
///
/// Generation reads its template from `PromptTemplate`, which stays the source
/// of truth; this only makes sure the schema reflects the prompts the app is
/// actually using.
enum PromptSeeder {
    @MainActor
    static func seedPrompts(in modelContext: ModelContext) throws {
        let templates = [
            PromptTemplate.dailyShortSummary,
            PromptTemplate.weeklyInsights,
        ]
        let existing = try modelContext.fetch(FetchDescriptor<PromptRecord>())
        var didChange = false
        for record in existing where retiredTemplateDigests.contains(Self.digest(record.text)) {
            modelContext.delete(record)
            didChange = true
        }

        for template in templates
        where !existing.contains(where: { $0.text == template.text }) {
            modelContext.insert(PromptRecord(prompt: Prompt(text: template.text)))
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }

    // Exact fingerprints of retired built-in templates, in order:
    // former short summary, former insights, obsolete long summary,
    // previous general insights template.
    private static let retiredTemplateDigests: Set<String> = [
        "f6e99864da1e898426abe994be7d99101c8b92243d6cd7740dee96879805f289",
        "580efd88e2bfd7a7f34a7a1a9bf7a471b3b72e234a073b00dd5884f16f04b5a2",
        "fe4fc036db776fc67cfdab5b988b2810b3996986c45327e13ec5074ebe5d86e4",
        "61a27b02d0787deef7b09e645ccc7efa367a538b9004442ddfc483af1d20e283",
        "672cce03c8fdcf07d63bdd3c96391efe77b4e221325114d6e37961436a3c9705",
    ]

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
