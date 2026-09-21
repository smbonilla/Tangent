import Foundation

/// The language models Tangent can run on device.
///
/// This is deliberately framework free: the MLX configuration and factory for
/// each model live in `Services/Intelligence` so that features, settings and
/// persistence can talk about a model without importing MLX.
enum SummaryModelID: String, CaseIterable, Identifiable, Sendable {
    case qwen3_1_7B = "qwen3-1.7b-4bit"
    case qwen3_0_6B = "qwen3-0.6b-4bit"
    case gemma3n_E2B = "gemma3n-e2b-it-lm-4bit"
    case gemma3_1B = "gemma3-1b-qat-4bit"
    case medgemma4B = "medgemma-1.5-4b-it-4bit"

    var id: String { rawValue }

    /// The model's own name, used verbatim in the UI.
    var displayName: String {
        switch self {
        case .qwen3_0_6B: "Qwen3 0.6B"
        case .gemma3n_E2B: "Gemma 3n E2B"
        case .qwen3_1_7B: "Qwen3 1.7B"
        case .gemma3_1B: "Gemma 3 1B"
        case .medgemma4B: "MedGemma 1.5 4B"
        }
    }

    /// Hugging Face repository holding the 4-bit weights.
    var repoID: String {
        switch self {
        case .qwen3_0_6B: "mlx-community/Qwen3-0.6B-4bit"
        case .gemma3n_E2B: "mlx-community/gemma-3n-E2B-it-lm-4bit"
        case .qwen3_1_7B: "mlx-community/Qwen3-1.7B-4bit"
        case .gemma3_1B: "mlx-community/gemma-3-1b-it-qat-4bit"
        case .medgemma4B: "mlx-community/medgemma-1.5-4b-it-4bit"
        }
    }

    /// Rough download size, shown before the user commits to it.
    var approximateDownloadBytes: Int64 {
        switch self {
        case .qwen3_0_6B: 350_000_000
        case .gemma3n_E2B: 2_550_000_000
        case .qwen3_1_7B: 1_000_000_000
        case .gemma3_1B: 800_000_000
        case .medgemma4B: 2_500_000_000
        }
    }

    var description: String {
        switch self {
        case .qwen3_0_6B: "Compact general-purpose model. A starting point for quick diary reflections."
        case .gemma3n_E2B: "Text-only Gemma 3n model for summaries and reflection. Requires more storage and memory."
        case .qwen3_1_7B: "Larger general-purpose option. Uses more memory than Qwen3 0.6B."
        case .gemma3_1B: "An alternative general-purpose model for summaries and reflection."
        case .medgemma4B: "Specialist MedGemma model. Requires substantial storage and memory."
        }
    }

    var disablesThinking: Bool {
        self == .qwen3_0_6B || self == .qwen3_1_7B
    }

    /// Official context window from the MLX model config, in tokens.
    var contextWindowTokens: Int {
        switch self {
        case .qwen3_0_6B, .qwen3_1_7B: 40_960
        case .gemma3n_E2B, .gemma3_1B: 32_768
        case .medgemma4B: 131_072
        }
    }

    /// How far Insights may look back from the selected end date.
    ///
    /// Official windows are 32K–128K tokens, but on-device generation is capped
    /// at 4,096 input tokens. These spans keep a list of one-sentence summaries
    /// comfortably inside that budget. The largest models stay at two weeks
    /// because their weights leave the least room for KV cache.
    var maximumInsightSpanDays: Int {
        switch self {
        case .gemma3n_E2B: 14
        case .qwen3_0_6B, .gemma3_1B: 28
        case .qwen3_1_7B: 42
        case .medgemma4B: 14
        }
    }

    var insightSpanDescription: String {
        switch maximumInsightSpanDays {
        case 14: "2 weeks"
        case 21: "3 weeks"
        case 28: "4 weeks"
        case 42: "6 weeks"
        default: "\(maximumInsightSpanDays) days"
        }
    }

    static let `default`: SummaryModelID = .qwen3_1_7B
}
