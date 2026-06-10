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

/// Client for the OpenAI-compatible Responses API on the Amazon Bedrock Mantle endpoint.
/// OpenAI frontier models (GPT-5.5 / GPT-5.4) are served exclusively through
/// bedrock-mantle — they are not available on bedrock-runtime InvokeModel/Converse.
///
/// Authentication follows the same precedence as the Codex/Bedrock integration:
/// a Bedrock API key (Bearer token) is used when configured, otherwise requests
/// are SigV4-signed with the app's AWS credential chain (service: bedrock-mantle).
final class MantleResponsesService: Sendable {
    private let region: String
    private let apiKey: String
    private let credentialResolver: (any AWSCredentialIdentityResolver)?
    private let logger = Logger(label: "MantleResponsesService")

    init(region: String, apiKey: String, credentialResolver: (any AWSCredentialIdentityResolver)? = nil) {
        self.region = region
        self.apiKey = apiKey
        self.credentialResolver = credentialResolver
    }

    private var host: String {
        "bedrock-mantle.\(region).api.aws"
    }

    private var responsesURL: URL? {
        URL(string: "https://\(host)/openai/v1/responses")
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
                            userInfo: [NSLocalizedDescriptionKey: "No AWS credentials available. Configure an AWS profile or set a Bedrock API key in Settings → Developer → Advanced."]
                        )
                    }

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
        return json["message"] as? String
    }
}
