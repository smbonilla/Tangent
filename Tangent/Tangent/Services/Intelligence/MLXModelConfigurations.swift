import Foundation
import MLXLLM
import MLXLMCommon
import MLXVLM

/// Maps Tangent's model identities onto MLX. Kept out of `Domain` so nothing
/// above `Services` has to import MLX.
extension SummaryModelID {
    var configuration: ModelConfiguration {
        switch self {
        case .qwen3_0_6B, .qwen3_1_7B:
            ModelConfiguration(id: repoID, extraEOSTokens: ["<|im_end|>"])
        case .gemma3n_E2B:
            LLMRegistry.gemma3n_E2B_it_lm_4bit
        case .gemma3_1B:
            LLMRegistry.gemma3_1B_qat_4bit
        case .medgemma4B:
            ModelConfiguration(id: repoID, extraEOSTokens: ["<end_of_turn>"])
        }
    }

    /// MedGemma was converted with mlx-vlm under the Gemma 3 multimodal
    /// architecture, so it loads through the VLM factory even though Tangent
    /// only ever sends it text. Attaching no images is fine.
    var factory: any ModelFactory {
        switch self {
        case .gemma3_1B, .qwen3_0_6B, .gemma3n_E2B, .qwen3_1_7B:
            LLMModelFactory.shared
        case .medgemma4B:
            VLMModelFactory.shared
        }
    }
}
