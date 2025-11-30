//
//  ModelInferenceConfig.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 5/26/25.
//

import Foundation

struct ModelInferenceConfig: Codable {
    var maxTokens: Int
    var temperature: Float
    var topP: Float
    var thinkingBudget: Int
    var reasoningEffort: String
    var overrideDefault: Bool
    var enableStreaming: Bool
    
    init(maxTokens: Int = 4096, temperature: Float = 0.7, topP: Float = 0.9, thinkingBudget: Int = 2048, reasoningEffort: String = "medium", overrideDefault: Bool = false, enableStreaming: Bool = true) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.thinkingBudget = thinkingBudget
        self.reasoningEffort = reasoningEffort
        self.overrideDefault = overrideDefault
        self.enableStreaming = enableStreaming
    }
}

struct ModelInferenceRange {
    let maxTokensRange: ClosedRange<Int>
    let temperatureRange: ClosedRange<Float>
    let topPRange: ClosedRange<Float>
    let thinkingBudgetRange: ClosedRange<Int>
    let defaultMaxTokens: Int
    let defaultTemperature: Float
    let defaultTopP: Float
    let defaultThinkingBudget: Int
    let defaultReasoningEffort: String
    
    static func getRangeForModel(_ modelId: String) -> ModelInferenceRange {
        let modelType = getModelTypeFromId(modelId)
        
        switch modelType {
        case .claudeSonnet45:
            // Claude Sonnet 4.5 doesn't support top_p with temperature
            return ModelInferenceRange(
                maxTokensRange: 1...64000,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,  // Range exists but can't be used with temperature
                thinkingBudgetRange: 1024...8192,
                defaultMaxTokens: 8192,
                defaultTemperature: 0.9,
                defaultTopP: 0.7,  // Not used by default since temperature is preferred
                defaultThinkingBudget: 2048,
                defaultReasoningEffort: "medium"
            )
        case .claudeHaiku45:
            // Claude Haiku 4.5 doesn't support top_p with temperature
            return ModelInferenceRange(
                maxTokensRange: 1...64000,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,  // Range exists but can't be used with temperature
                thinkingBudgetRange: 1024...8192,
                defaultMaxTokens: 32000,
                defaultTemperature: 0.9,
                defaultTopP: 0.7,  // Not used by default since temperature is preferred
                defaultThinkingBudget: 2048,
                defaultReasoningEffort: "medium"
            )
        case .claudeOpus45:
            // Claude Opus 4.5 doesn't support top_p with temperature (same as Sonnet 4.5 and Haiku 4.5)
            return ModelInferenceRange(
                maxTokensRange: 1...64000,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,  // Range exists but can't be used with temperature
                thinkingBudgetRange: 1024...8192,
                defaultMaxTokens: 8192,
                defaultTemperature: 0.9,
                defaultTopP: 0.7,  // Not used by default since temperature is preferred
                defaultThinkingBudget: 2048,
                defaultReasoningEffort: "medium"
            )
        case .claudeSonnet4, .claudeOpus4, .claudeOpus41:
            return ModelInferenceRange(
                maxTokensRange: 1...64000,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...8192,
                defaultMaxTokens: 8192,
                defaultTemperature: 0.9,
                defaultTopP: 0.7,
                defaultThinkingBudget: 2048,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .claude37:
            return ModelInferenceRange(
                maxTokensRange: 1...64000,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...16384,
                defaultMaxTokens: 8192,
                defaultTemperature: 0.9,
                defaultTopP: 0.7,
                defaultThinkingBudget: 4096,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .claude3, .claude35, .claude35Haiku:
            return ModelInferenceRange(
                maxTokensRange: 1...8192,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않지만 기본값 제공
                defaultMaxTokens: 4096,
                defaultTemperature: 0.9,
                defaultTopP: 0.7,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .novaPremier:
            return ModelInferenceRange(
                maxTokensRange: 1...10240,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 10240,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .novaPro, .novaLite:
            return ModelInferenceRange(
                maxTokensRange: 1...10240,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 10240,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .novaMicro:
            return ModelInferenceRange(
                maxTokensRange: 1...10240,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 10240,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .llama31, .llama32Large, .llama33:
            return ModelInferenceRange(
                maxTokensRange: 1...32768,
                temperatureRange: 0.0...2.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 8192,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .llama32Small, .llama3, .llama2:
            return ModelInferenceRange(
                maxTokensRange: 1...8192,
                temperatureRange: 0.0...2.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 2048,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .mistralLarge, .mistralLarge2407:
            return ModelInferenceRange(
                maxTokensRange: 1...32768,
                temperatureRange: 0.0...1.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 8192,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .deepseekr1:
            return ModelInferenceRange(
                maxTokensRange: 1...8192,
                temperatureRange: 1.0...1.0, // DeepSeek R1은 temperature가 1.0 고정
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // always-on reasoning이므로 사용자가 조정할 수 없음
                defaultMaxTokens: 8192,
                defaultTemperature: 1.0,
                defaultTopP: 0.9,
                defaultThinkingBudget: 2048,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
            
        case .openaiGptOss120b, .openaiGptOss20b:
            return ModelInferenceRange(
                maxTokensRange: 1...8192,
                temperatureRange: 0.0...2.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...4096, // 조정 가능한 reasoning budget
                defaultMaxTokens: 8192,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 2048,
                defaultReasoningEffort: "medium"  // GPT-OSS 모델에만 실제로 적용됨
            )
            
        default:
            return ModelInferenceRange(
                maxTokensRange: 1...4096,
                temperatureRange: 0.0...2.0,
                topPRange: 0.01...1.0,
                thinkingBudgetRange: 1024...2048, // thinking 지원하지 않음
                defaultMaxTokens: 4096,
                defaultTemperature: 0.7,
                defaultTopP: 0.9,
                defaultThinkingBudget: 1024,
                defaultReasoningEffort: "medium"  // GPT-OSS가 아니므로 실제로는 사용되지 않음
            )
        }
    }
    
    private static func getModelTypeFromId(_ modelId: String) -> ModelType {
        // Backend의 getModelType 로직을 여기에 복사하거나 참조
        let modelIdWithoutVersion = modelId.split(separator: ":").first ?? ""
        let parts = String(modelIdWithoutVersion).split(separator: ".")
        
        guard parts.count >= 2 else { return .unknown }
        
        let providerIndex = parts.count >= 3 ? 1 : 0
        let provider = String(parts[providerIndex]).lowercased()
        let modelNameElements = parts.suffix(from: providerIndex + 1)
        let modelNameAndVersion = modelNameElements.joined(separator: ".")
        
        switch provider {
        case "anthropic":
            if modelNameAndVersion.contains("claude-sonnet-4-5") {
                return .claudeSonnet45
            } else if modelNameAndVersion.contains("claude-haiku-4-5") {
                return .claudeHaiku45
            } else if modelNameAndVersion.contains("claude-opus-4-5") {
                return .claudeOpus45
            } else if modelNameAndVersion.contains("claude-opus-4-1") {
                return .claudeOpus41
            } else if modelNameAndVersion.contains("claude-sonnet-4") {
                return .claudeSonnet4
            } else if modelNameAndVersion.contains("claude-opus-4") {
                return .claudeOpus4
            } else if modelNameAndVersion.contains("claude-3-7") {
                return .claude37
            } else if modelNameAndVersion.contains("claude-3-5-haiku") {
                return .claude35Haiku
            } else if modelNameAndVersion.contains("claude-3-5") {
                return .claude35
            } else if modelNameAndVersion.contains("claude-3") {
                return .claude3
            } else {
                return .claude
            }
            
        case "amazon":
            if modelNameAndVersion.contains("nova-premier") {
                return .novaPremier
            } else if modelNameAndVersion.contains("nova-pro") {
                return .novaPro
            } else if modelNameAndVersion.contains("nova-lite") {
                return .novaLite
            } else if modelNameAndVersion.contains("nova-micro") {
                return .novaMicro
            }
            
        case "meta":
            if modelNameAndVersion.contains("llama3-3") {
                return .llama33
            } else if modelNameAndVersion.contains("llama3-2") {
                if modelNameAndVersion.contains("11b") || modelNameAndVersion.contains("90b") {
                    return .llama32Large
                } else {
                    return .llama32Small
                }
            } else if modelNameAndVersion.contains("llama3-1") {
                return .llama31
            } else if modelNameAndVersion.contains("llama3") {
                return .llama3
            } else if modelNameAndVersion.contains("llama2") {
                return .llama2
            }
            
        case "mistral":
            if modelNameAndVersion.contains("mistral-large-2407") {
                return .mistralLarge2407
            } else if modelNameAndVersion.contains("mistral-large") {
                return .mistralLarge
            }
            
        case "deepseek":
            if modelNameAndVersion.contains("r1") {
                return .deepseekr1
            }
            
        case "openai":
            if modelNameAndVersion.contains("gpt-oss-120b") {
                return .openaiGptOss120b
            } else if modelNameAndVersion.contains("gpt-oss-20b") {
                return .openaiGptOss20b
            }
            
        default:
            break
        }
        
        return .unknown
    }
}
