//
//  MantleResponsesService.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/9/26.
//

import Foundation
import Logging

/// Client for the OpenAI-compatible Responses API on the Amazon Bedrock Mantle endpoint.
/// OpenAI frontier models (GPT-5.5 / GPT-5.4) are served exclusively through
/// bedrock-mantle — they are not available on bedrock-runtime InvokeModel/Converse.
/// Authentication uses a Bedrock API key (Bearer token), matching the documented
/// OPENAI_BASE_URL / OPENAI_API_KEY integration path.
final class MantleResponsesService: Sendable {
    private let region: String
    private let apiKey: String
    private let logger = Logger(label: "MantleResponsesService")

    init(region: String, apiKey: String) {
        self.region = region
        self.apiKey = apiKey
    }

    private var responsesURL: URL? {
        URL(string: "https://bedrock-mantle.\(region).api.aws/openai/v1/responses")
    }

    /// Streams text deltas from the Responses API.
    /// `input` is the Responses API input array: [{"role": "user"|"assistant"|"developer", "content": "..."}]
    func streamResponse(
        modelId: String,
        input: [[String: Any]],
        maxOutputTokens: Int,
        reasoningEffort: String,
        usageHandler: (@Sendable (UsageInfo) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        // Serialize the request body before entering the stream closure so the
        // non-Sendable [[String: Any]] payload is not captured across tasks
        let body: [String: Any] = [
            "model": modelId,
            "input": input,
            "stream": true,
            "max_output_tokens": maxOutputTokens,
            "reasoning": ["effort": reasoningEffort]
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !self.apiKey.isEmpty else {
                        throw NSError(
                            domain: "MantleResponsesService", code: 401,
                            userInfo: [NSLocalizedDescriptionKey: "Bedrock API key is not configured. Set it in Settings → General → Bedrock API Key to use OpenAI models on Bedrock."]
                        )
                    }
                    guard let url = self.responsesURL else {
                        throw NSError(
                            domain: "MantleResponsesService", code: 400,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid bedrock-mantle endpoint for region \(self.region)"]
                        )
                    }
                    guard let bodyData else {
                        throw NSError(
                            domain: "MantleResponsesService", code: 400,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to encode Responses API request body"]
                        )
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 600
                    request.httpBody = bodyData

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 4096 { break }
                        }
                        let message = Self.extractErrorMessage(from: errorBody) ?? errorBody
                        throw NSError(
                            domain: "MantleResponsesService", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Responses API error (HTTP \(httpResponse.statusCode)): \(message)"]
                        )
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"] as? String {
                                continuation.yield(delta)
                            }
                        case "response.completed":
                            if let resp = event["response"] as? [String: Any],
                               let usage = resp["usage"] as? [String: Any] {
                                let usageInfo = UsageInfo(
                                    inputTokens: usage["input_tokens"] as? Int,
                                    outputTokens: usage["output_tokens"] as? Int,
                                    cacheCreationInputTokens: nil,
                                    cacheReadInputTokens: nil
                                )
                                usageHandler?(usageInfo)
                            }
                        case "response.failed", "error":
                            let message = Self.extractErrorMessage(from: payload) ?? "Response failed"
                            throw NSError(
                                domain: "MantleResponsesService", code: 500,
                                userInfo: [NSLocalizedDescriptionKey: message]
                            )
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    self.logger.error("Mantle Responses stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func extractErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return json["message"] as? String
    }
}
