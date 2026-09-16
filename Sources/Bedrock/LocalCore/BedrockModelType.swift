import Foundation

enum ModelType: Sendable {
    // Anthropic models
    case claude, claude3, claude35, claude35Haiku, claude37, claudeSonnet4, claudeSonnet45, claudeSonnet5, claudeHaiku45, claudeOpus4, claudeOpus41, claudeOpus45, claudeOpus46, claudeOpus47, claudeOpus48, claudeOpus5, claudeFable5
    // Meta models
    case llama2, llama3, llama31, llama32Small, llama32Large, llama33, llama4Maverick, llama4Scout
    // Mistral models
    case mistral, mistral7b, mistralLarge, mistralLarge2407, mistralLarge3, mistralSmall, mixtral, pixtralLarge
    case voxtralSmall, voxtralMini, ministral3b, ministral8b, ministral14b, magistralSmall
    // Amazon models
    case titan, titanImage, titanEmbed, novaPremier, novaPro, novaLite, novaMicro, novaCanvas, rerank
    // Amazon Nova 2 models
    case nova2Lite, nova2Sonic
    // AI21 models
    case j2, jambaInstruct, jambaLarge, jambaMini
    // Cohere models
    case cohereCommand, cohereCommandLight, cohereCommandR, cohereCommandRPlus, cohereEmbed, cohereEmbedV4, cohereRerank
    // Stability models
    case stableDiffusion, stableImage
    // OpenAI models
    case openaiGptOss120b, openaiGptOss20b, openaiGptOssSafeguard
    // OpenAI frontier models (bedrock-mantle Responses API only)
    case openaiGpt55, openaiGpt54
    // OpenAI GPT-5.6 capability tiers (bedrock-mantle Responses API only)
    case openaiGpt56Sol, openaiGpt56Terra, openaiGpt56Luna
    case openaiGpt6Astra
    // DeepSeek models
    case deepseekr1, deepseekv3
    // Qwen models
    case qwen3Large, qwen3Dense, qwen3CoderLarge, qwen3CoderSmall, qwen3VL, qwen3Next
    // Writer models
    case palmyraX4, palmyraX5
    // TwelveLabs models
    case pegasus
    // Moonshot models
    case kimiK2Thinking
    // NVIDIA models
    case nvidiaNemotronNano9b, nvidiaNemotronNano12bVL
    // MiniMax models
    case minimaxM2
    // Google models
    case gemma3_4b, gemma3_12b, gemma3_27b
    // Other models
    case luma, unknown
}
