import CryptoKit
import Foundation
import SwiftData

/// Creates a neutral profile once; existing preferences always belong to the user.
enum ProfileSeeder {
    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<UserProfileRecord>(sortBy: [SortDescriptor(\.name)])
        )
        let profile: UserProfileRecord
        if let first = existing.first {
            profile = first
        } else {
            profile = UserProfileRecord(profile: UserProfile(name: "You"))
            modelContext.insert(profile)
        }
        let questions = try modelContext.fetch(FetchDescriptor<QuestionRecord>())
            .filter { $0.profileID == profile.id }
        if questions.isEmpty || isRetiredQuestionnaire(questions) {
            questions.forEach { modelContext.delete($0) }
            for text in questionTexts {
                modelContext.insert(QuestionRecord(question: Question(
                    profileID: profile.id, promptText: "", text: text
                )))
            }
        }
        try modelContext.save()
        #if DEBUG
        try DemoDataSeeder.removeDummyPastDayIfNeeded(in: modelContext)
        #endif
    }

    static let questionTexts = [
        "What stood out to you today?",
        "What did you spend time on or learn?",
        "What went well, and what felt difficult?",
        "What would you like to explore or change next?",
    ]

    // Exact fingerprints of a retired built-in questionnaire. Matching sets
    // are replaced; custom questions are left alone.
    private static let retiredQuestionDigests: Set<String> = [
        "b808e9315881ebcf00117b276275b9ae86f606e4eadc94327d8a5662e144d73e",
        "c984db6b0e674daedac66f5758adedf89e440658b6677a1de4658175377579da",
        "d849c97e2cf447051c3de4adc76d5b26cbd3210c22796d621079300a1b56aeb3",
        "06ba84b62e1e4135826a23471cecaa3f0fead7c1d8d1d19edd55139f3e810f5a",
        "1b6b3cfdcfbcc38ba04843e160b7465e640bf408f57a078a1617add74e8ff49b",
        "c0aa64d2e9067e994f89ddf109e01fd3f4ab1cc96f5de075981ab6ea00f35efc",
        "41a3c4dfa4137a874551e9a910d37e5ff205029ddf438b230777e7ce2d861342",
        "3f13715cb6b9559de8d53fc313e584c75361546fb65257fda5554eda4a712ad5",
    ]

    private static func isRetiredQuestionnaire(_ questions: [QuestionRecord]) -> Bool {
        Set(questions.map { digest($0.text) }) == retiredQuestionDigests
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
