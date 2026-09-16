//
//  MantleResponsesService.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/9/26.
//

import CryptoKit
import Foundation
import Logging
import SmithyIdentity

enum MantleResponseEvent: Sendable, Equatable {
    case text(String)
    case finished(stopReason: String, usage: UsageInfo?, fallbackText: String)
}

/// Client for models using the Responses API on the Amazon Bedrock Mantle endpoint.
///
/// Authentication follows the same precedence as the Codex/Bedrock integration:
/// a Bedrock API key (Bearer token) is used when configured, otherwise requests
/// are SigV4-signed with the app's AWS credential chain (service: bedrock-mantle).
final class MantleResponsesService: Sendable {
    private let region: String
    private let apiKey: String
    private let credentialResolver: (any AWSCredentialIdentityResolver)?
    private let session: URLSession
    private let logger = Logger(label: "MantleResponsesService")

    init(region: String, apiKey: String, credentialResolver: (any AWSCredentialIdentityResolver)? = nil,
         session: URLSession = .shared) {
        self.region = region
        self.apiKey = apiKey
        self.credentialResolver = credentialResolver
        self.session = session
    }

    private var host: String {
        "bedrock-mantle.\(region).api.aws"
    }

    private var responsesURL: URL? {
        URL(string: "https://\(host)/v1/responses")
    }

    /// Streams text deltas from the Responses API.
    /// `input` is the Responses API input array: [{"role": "user"|"assistant"|"developer", "content": "..."}]
    func streamResponse(
        modelId: String,
        input: [[String: Any]],
        maxOutputTokens: Int,
        reasoningEffort: String
    ) -> AsyncThrowingStream<MantleResponseEvent, Error> {
        // Serialize the request body before entering the stream closure so the
        // non-Sendable [[String: Any]] payload is not captured across tasks
        let body: [String: Any] = [
            "model": modelId,
            "input": input,
            "stream": true,
            "store": false,
            "max_output_tokens": maxOutputTokens,
            "reasoning": ["effort": reasoningEffort]
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
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
                    request.timeoutInterval = 600
                    request.httpBody = bodyData

                    // Auth: Bearer token when configured, otherwise SigV4 via the AWS credential chain
                    if !self.apiKey.isEmpty {
                        request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                    } else if let resolver = self.credentialResolver {
                        let credentials = try await resolver.getIdentity(identityProperties: nil)
                        self.signWithSigV4(request: &request, bodyData: bodyData, credentials: credentials)
                    } else {
                        throw NSError(
                            domain: "MantleResponsesService", code: 401,
                            userInfo: [NSLocalizedDescriptionKey: "No AWS credentials available. Configure an AWS profile or set a Bedrock API key in Settings → AWS connection."]
                        )
                    }

                    let (bytes, response) = try await self.session.bytes(for: request)

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

                    var completed = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let event = try Self.parseEvent(payload) else { continue }
                        continuation.yield(event)
                        if case .finished = event {
                            completed = true
                            // A terminal event completes the request even when the
                            // server leaves its SSE connection open.
                            break
                        }
                    }
                    guard completed else {
                        throw NSError(domain: "MantleResponsesService", code: 502,
                                      userInfo: [NSLocalizedDescriptionKey: "The response ended before it was complete. Please try again."])
                    }
                    continuation.finish()
                } catch {
                    let failure = error as NSError
                    self.logger.error("Mantle Responses stream error (\(failure.domain), \(failure.code))")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func parseEvent(_ payload: String) throws -> MantleResponseEvent? {
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }
        if type == "response.output_text.delta", let text = event["delta"] as? String {
            return .text(text)
        }
        if type == "response.failed" || type == "error" {
            throw NSError(domain: "MantleResponsesService", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: extractErrorMessage(from: payload) ??
                                     "The model could not complete this response."])
        }
        guard type == "response.completed" || type == "response.incomplete" else { return nil }
        guard let response = event["response"] as? [String: Any] else {
            throw NSError(domain: "MantleResponsesService", code: 502,
                          userInfo: [NSLocalizedDescriptionKey: "The model returned an invalid completion event."])
        }
        let stopReason: String
        if type == "response.completed" {
            stopReason = "end_turn"
        } else {
            let reason = (response["incomplete_details"] as? [String: Any])?["reason"] as? String
            switch reason {
            case "max_output_tokens": stopReason = "max_tokens"
            case "content_filter": stopReason = "content_filtered"
            default:
                throw NSError(domain: "MantleResponsesService", code: 502,
                              userInfo: [NSLocalizedDescriptionKey: "The response stopped before it was complete. Please try again."])
            }
        }
        let usage = (response["usage"] as? [String: Any]).map { value in
            let details = value["input_tokens_details"] as? [String: Any]
            return UsageInfo(inputTokens: value["input_tokens"] as? Int,
                             outputTokens: value["output_tokens"] as? Int,
                             cacheCreationInputTokens: details?["cache_write_tokens"] as? Int,
                             cacheReadInputTokens: details?["cached_tokens"] as? Int)
        }
        let fallbackText = (response["output"] as? [[String: Any]] ?? [])
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
        return .finished(stopReason: stopReason, usage: usage, fallbackText: fallbackText)
    }

    // MARK: - SigV4 Signing

    /// Signs the request with AWS Signature Version 4 for the bedrock-mantle service.
    /// The signed headers are host, x-amz-date, and x-amz-security-token (when present).
    private func signWithSigV4(request: inout URLRequest, bodyData: Data, credentials: AWSCredentialIdentity) {
        let service = "bedrock-mantle"
        let now = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let amzDate = dateFormatter.string(from: now)
        let dateStamp = String(amzDate.prefix(8))

        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        if let sessionToken = credentials.sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        // Canonical request
        let path = request.url?.path ?? "/"
        let payloadHash = SHA256.hash(data: bodyData).map { String(format: "%02x", $0) }.joined()

        var canonicalHeaders = "host:\(host)\nx-amz-date:\(amzDate)\n"
        var signedHeaders = "host;x-amz-date"
        if let sessionToken = credentials.sessionToken {
            canonicalHeaders += "x-amz-security-token:\(sessionToken)\n"
            signedHeaders += ";x-amz-security-token"
        }

        let canonicalRequest = [
            "POST",
            path,
            "",  // no query string
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        // String to sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        // Signing key
        let kDate = Self.hmac(key: Data("AWS4\(credentials.secret)".utf8), data: Data(dateStamp.utf8))
        let kRegion = Self.hmac(key: kDate, data: Data(region.utf8))
        let kService = Self.hmac(key: kRegion, data: Data(service.utf8))
        let kSigning = Self.hmac(key: kService, data: Data("aws4_request".utf8))
        let signature = Self.hmac(key: kSigning, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    private static func hmac(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func extractErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let response = json["response"] as? [String: Any],
           let error = response["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return json["message"] as? String
    }
}
