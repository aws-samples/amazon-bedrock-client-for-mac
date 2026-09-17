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
    case output([JSONValue])
    case finished(stopReason: String, usage: UsageInfo?, fallbackText: String)
}

/// Stateless Responses streaming on Bedrock Runtime and Mantle. The endpoint,
/// model profile and signing region are resolved together; input/output stays
/// in local history because every request explicitly sets store=false.
final class MantleResponsesService: Sendable {
    private let region: String
    private let apiKey: String
    private let credentialResolver: (any AWSCredentialIdentityResolver)?
    private let session: URLSession
    private let endpointOverride: URL?
    private let logger = Logger(label: "MantleResponsesService")

    init(region: String, apiKey: String, credentialResolver: (any AWSCredentialIdentityResolver)? = nil,
         session: URLSession = .shared, endpointOverride: URL? = nil) {
        self.region = region
        self.apiKey = apiKey
        self.credentialResolver = credentialResolver
        self.session = session
        self.endpointOverride = endpointOverride
    }

    /// Streams text deltas from the Responses API.
    /// Input includes typed file/image parts and function calls/results.
    func streamResponse(
        modelId: String,
        input: [[String: Any]],
        maxOutputTokens: Int,
        reasoningEffort: String,
        tools: [[String: Any]] = []
    ) -> AsyncThrowingStream<MantleResponseEvent, Error> {
        // Serialize the request body before entering the stream closure so the
        // non-Sendable [[String: Any]] payload is not captured across tasks
        let endpoint = Result { try BedrockResponsesEndpoint.resolve(modelID: modelId, region: region) }
        var body: [String: Any] = [
            "model": (try? endpoint.get().modelID) ?? modelId,
            "input": input,
            "stream": true,
            "store": false,
            "max_output_tokens": maxOutputTokens,
            "reasoning": ["effort": reasoningEffort]
        ]
        if !tools.isEmpty { body["tools"] = tools }
        if BedrockModelID.provider(modelId) == "openai" {
            body["include"] = ["reasoning.encrypted_content"]
        }
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let target = try endpoint.get()
                    let url = self.endpointOverride ?? target.url
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
                        self.signWithSigV4(request: &request, bodyData: bodyData, credentials: credentials, endpoint: target)
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
                        for event in try Self.parseEvents(payload) {
                            continuation.yield(event)
                            if case .finished = event { completed = true }
                        }
                        // Completion is authoritative even if the SSE connection
                        // stays open. Tool execution starts only after this event.
                        if completed { break }
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

    private static func parseEvents(_ payload: String) throws -> [MantleResponseEvent] {
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return [] }
        if type == "response.output_text.delta", let text = event["delta"] as? String {
            return [.text(text)]
        }
        if type == "response.failed" || type == "error" {
            throw NSError(domain: "MantleResponsesService", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: extractErrorMessage(from: payload) ??
                                     "The model could not complete this response."])
        }
        guard type == "response.completed" || type == "response.incomplete" else { return [] }
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
        let output = response["output"] as? [[String: Any]] ?? []
        let fallbackText = output
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
        var events: [MantleResponseEvent] = []
        if !output.isEmpty { events.append(.output(output.map(JSONValue.from))) }
        events.append(.finished(stopReason: stopReason, usage: usage, fallbackText: fallbackText))
        return events
    }

    // MARK: - SigV4 Signing

    /// Both Bedrock Responses endpoints use the bedrock signing service.
    /// The signed headers are host, x-amz-date, and x-amz-security-token (when present).
    private func signWithSigV4(request: inout URLRequest, bodyData: Data, credentials: AWSCredentialIdentity,
                              endpoint: BedrockResponsesEndpoint) {
        let service = endpoint.signingService
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

        let host = (request.url?.host ?? "") + (request.url?.port.map { ":\($0)" } ?? "")
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
        let credentialScope = "\(dateStamp)/\(endpoint.region)/\(service)/aws4_request"
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
        let kRegion = Self.hmac(key: kDate, data: Data(endpoint.region.utf8))
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
