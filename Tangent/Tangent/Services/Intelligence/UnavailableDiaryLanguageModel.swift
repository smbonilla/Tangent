import Foundation

/// Used where MLX cannot run — the Simulator, and previews. Fails cleanly so
/// the rest of the app behaves exactly as it would on a device without the
/// model, rather than crashing inside Metal.
final class UnavailableDiaryLanguageModel: DiaryLanguageModel {
    private let error: DiaryLanguageModelError

    init(error: DiaryLanguageModelError = .unsupportedDevice) { self.error = error }

    func prepare() async {}

    func generateShortSummary(
        transcript: String,
        profile: UserProfile,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        throw error
    }

    func generateInsights(
        from summaries: [DiarySummary],
        focus: DiaryFocus,
        period: String,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> GeneratedText {
        throw error
    }
}
