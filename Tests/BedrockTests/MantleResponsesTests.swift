import Foundation
import SmithyIdentity
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MantleResponsesTests: XCTestCase {
    func testAstraFilesUseRuntimeResponsesAndRemainInFollowUpHistory() async throws {
        for format in [MessageContent.DocumentFormat.pdf, .txt] {
            let fixture = ResponsesFixture(events: [
                #"{"type":"response.output_text.delta","delta":"ASTRA_FILE_OK"}"#,
                #"{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"ASTRA_FILE_OK"}]}]}}"#
            ], apiKey: "")
            defer { fixture.close() }
            let bytes = Data("SYNTHETIC_ASTRA_FILE".utf8).base64EncodedString()
            let history: [BedrockMessage] = [
                .init(role: .user, content: [.document(.init(format: format, base64Data: bytes, name: "Report")),
                                            .text("Read this file.")]),
                .init(role: .assistant, content: [.text("I have read the file.")]),
                .init(role: .user, content: [.text("What was the marker?")])
            ]
            var text = ""
            for try await event in fixture.service.streamResponse(
                modelId: "us.openai.gpt-6-astra", input: try BedrockResponsesRequest.input(history),
                maxOutputTokens: 256, reasoningEffort: "low"
            ) {
                if case .text(let delta) = event { text += delta }
            }
            XCTAssertEqual(text, "ASTRA_FILE_OK")
            XCTAssertEqual(fixture.request?.url?.path, "/openai/v1/responses")
            XCTAssertEqual(fixture.request?.url?.host, "bedrock-runtime.us-west-2.amazonaws.com")
            let body = try XCTUnwrap(fixture.body)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "us.openai.gpt-6-astra")
            XCTAssertEqual(json["store"] as? Bool, false)
            let input = try XCTUnwrap(json["input"] as? [[String: Any]])
            XCTAssertEqual(input.count, 3)
            let part = try XCTUnwrap((input[0]["content"] as? [[String: Any]])?.first)
            XCTAssertEqual(part["type"] as? String, "input_file")
            XCTAssertEqual(part["filename"] as? String, "Report." + format.rawValue)
            XCTAssertTrue((part["file_data"] as? String)?.hasSuffix(bytes) == true)
        }
    }

    func testOutputLimitPreservesTextUsageAndContinueAction() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.output_text.delta","delta":"A partial "}"#,
            #"{"type":"response.output_text.delta","delta":"answer"}"#,
            #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":120,"output_tokens":64,"input_tokens_details":{"cached_tokens":80}}}}"#
        ])
        defer { fixture.close() }
        let events = try await collect(fixture.service)
        XCTAssertEqual(events.prefix(2), [.text("A partial "), .text("answer")])
        guard let last = events.last, case .finished(let reason, let usage, _) = last else {
            return XCTFail("Expected a recoverable completion event.")
        }
        XCTAssertEqual(reason, "max_tokens")
        XCTAssertEqual(usage?.inputTokens, 120)
        XCTAssertEqual(usage?.outputTokens, 64)
        XCTAssertEqual(usage?.cacheReadInputTokens, 80)
        var run = RunRecord(threadID: "fixture", modelID: "openai.gpt-5.5", title: "Output limit")
        run.status = .completed
        run.stopReason = reason
        XCTAssertTrue(run.canContinueResponse)
        XCTAssertNotNil(run.completionNotice)
    }

    func testContentFilterDoesNotOfferAutomaticContinuation() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}"#
        ])
        defer { fixture.close() }
        let events = try await collect(fixture.service)
        guard let last = events.last, case .finished(let reason, _, _) = last else { return XCTFail("Missing stop reason.") }
        var run = RunRecord(threadID: "fixture", modelID: "openai.gpt-5.5", title: "Filtered")
        run.status = .completed
        run.stopReason = reason
        XCTAssertEqual(reason, "content_filtered")
        XCTAssertFalse(run.canContinueResponse)
        XCTAssertNotNil(run.completionNotice)
    }

    func testCompletionFinishesAnOpenConnectionAndUsesTheMantlePath() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"The complete answer."}]}]}}"#
        ], keepsConnectionOpen: true)
        defer { fixture.close() }
        let events = try await collect(fixture.service)
        XCTAssertEqual(events.last, .finished(stopReason: "end_turn", usage: nil, fallbackText: "The complete answer."))
        guard case .output(let items) = events.first else { return XCTFail("The completion must retain its output items.") }
        XCTAssertEqual(items.count, 1)
        let request = try XCTUnwrap(fixture.request)
        XCTAssertEqual(request.url?.host, "bedrock-mantle.us-west-2.api.aws")
        XCTAssertEqual(request.url?.path, "/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer FIXTURE_ONLY")
        let body = try XCTUnwrap(fixture.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(json["model"] as? String, "openai.gpt-5.5")
    }

    func testUnexpectedEOFDoesNotReportACompleteResponse() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.output_text.delta","delta":"Keep this partial response."}"#
        ])
        defer { fixture.close() }
        var partial: [MantleResponseEvent] = []
        do {
            for try await event in fixture.stream { partial.append(event) }
            XCTFail("An EOF without a completion event must fail.")
        } catch {
            XCTAssertEqual((error as NSError).code, 502)
        }
        XCTAssertEqual(partial, [.text("Keep this partial response.")])
    }

    func testNestedModelFailureKeepsTheActionableMessage() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.failed","response":{"error":{"code":"model_error","message":"The model is temporarily unavailable."}}}"#
        ])
        defer { fixture.close() }
        do {
            _ = try await collect(fixture.service)
            XCTFail("The model failure must propagate.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The model is temporarily unavailable.")
        }
    }

    func testRuntimeDocumentsPreserveFileTypesImagesToolsAndSignedProfile() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"File read."}]}]}}"#
        ], apiKey: "")
        defer { fixture.close() }
        let pdf = Data("%PDF-1.7\nSYNTHETIC_DOCUMENT_MARKER\n%%EOF".utf8).base64EncodedString()
        let image = Data([137, 80, 78, 71, 13, 10, 26, 10]).base64EncodedString()
        let history: [BedrockMessage] = [
            .init(role: .user, content: [.document(.init(format: .pdf, base64Data: pdf, name: "Saved report")),
                                        .image(.init(format: .png, base64Data: image)), .text("Read the report.")]),
            .init(role: .assistant, content: [.tooluse(.init(toolUseId: "read-1", name: "local_read_file",
                                                            input: .object(["path": .string("/tmp/synthetic.txt")])))]),
            .init(role: .user, content: [.toolresult(.init(toolUseId: "read-1", result: "ACTUAL_TOOL_RESULT", status: "success"))]),
            .init(role: .user, content: [.text("Keep going with the attached file.")])
        ]
        let input = try BedrockResponsesRequest.input(history, systemPrompt: "Synthetic request.")
        let tools: [[String: Any]] = [
            ["type": "function", "name": "local_read_file", "parameters":
                ["type": "object", "properties": ["path": ["type": "string"]], "required": ["path"]]]
        ]
        for try await _ in fixture.service.streamResponse(
            modelId: "us.openai.gpt-5.6-luna", input: input, maxOutputTokens: 256, reasoningEffort: "low", tools: tools) {}
        let request = try XCTUnwrap(fixture.request)
        XCTAssertEqual(request.url?.absoluteString, "https://bedrock-runtime.us-west-2.amazonaws.com/openai/v1/responses")
        let authorization = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authorization.contains("/us-west-2/bedrock/aws4_request"))
        let body = try XCTUnwrap(fixture.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "us.openai.gpt-5.6-luna")
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["name"] as? String, "local_read_file")
        let sent = try XCTUnwrap(json["input"] as? [[String: Any]])
        let parts = try XCTUnwrap(sent[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts[0]["filename"] as? String, "Saved report.pdf")
        XCTAssertEqual(parts[0]["file_data"] as? String, "data:application/pdf;base64," + pdf)
        XCTAssertEqual(parts[1]["image_url"] as? String, "data:image/png;base64," + image)
        XCTAssertEqual(sent[2]["type"] as? String, "function_call")
        XCTAssertEqual(sent[3]["call_id"] as? String, "read-1")
        XCTAssertEqual(sent[3]["output"] as? String, "ACTUAL_TOOL_RESULT")
        guard case .document(let original) = history[0].content[0] else { return XCTFail("Missing stored attachment.") }
        XCTAssertEqual(original.name, "Saved report", "Adapting the wire name must not rewrite stored history.")
        XCTAssertEqual(original.base64Data, pdf)
    }

    func testCompletedResponsesCarryToolAndReasoningItemsWithoutEarlyExecution() async throws {
        let fixture = ResponsesFixture(events: [
            #"{"type":"response.output_item.done","item":{"type":"function_call","call_id":"read-1","name":"local_read_file","arguments":"{\"path\":\"/tmp/fixture.txt\"}"}}"#,
            #"{"type":"response.completed","response":{"output":[{"type":"reasoning","id":"reasoning-1","encrypted_content":"SYNTHETIC_OPAQUE_CONTENT","summary":[]},{"type":"function_call","call_id":"read-1","name":"local_read_file","arguments":"{\"path\":\"/tmp/fixture.txt\"}","status":"completed"}]}}"#
        ])
        defer { fixture.close() }
        let events = try await collect(fixture.service)
        XCTAssertEqual(events.count, 2, "A function item alone must not execute before response completion.")
        guard case .output(let output) = events.first else { return XCTFail("Missing completed output.") }
        let calls = try BedrockResponsesRequest.toolCalls(in: output)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "local_read_file")
        XCTAssertEqual(calls.first?.inputJSON, #"{"path":"/tmp/fixture.txt"}"#)
        XCTAssertEqual(output[0].asDictionary?["encrypted_content"] as? String, "SYNTHETIC_OPAQUE_CONTENT")
        XCTAssertEqual(events.last, .finished(stopReason: "end_turn", usage: nil, fallbackText: ""))
    }

    func testInvalidDuplicateAndPartialFunctionCallsAreNeverExecutable() throws {
        let complete = JSONValue.from(["type": "function_call", "call_id": "id", "name": "local_read_file", "arguments": "{}"])
        XCTAssertThrowsError(try BedrockResponsesRequest.toolCalls(in: [complete, complete]))
        XCTAssertThrowsError(try BedrockResponsesRequest.toolCalls(in: [
            .from(["type": "function_call", "call_id": "id", "name": "local_read_file", "arguments": #"{"path":"#])
        ]))
        XCTAssertThrowsError(try BedrockResponsesRequest.toolCalls(in: [
            .from(["type": "function_call", "call_id": "id", "name": "local_read_file", "arguments": "{}", "status": "incomplete"])
        ]))
        XCTAssertEqual(BedrockResponsesRequest.documentFilename("report.PDF", format: "pdf"), "report.PDF")
        XCTAssertEqual(BedrockResponsesRequest.documentFilename("한국어 메모", format: "txt"), "한국어 메모.txt")
        XCTAssertEqual(BedrockResponsesRequest.documentFilename("", format: "csv"), "Document.csv")
    }

    private func collect(_ service: MantleResponsesService) async throws -> [MantleResponseEvent] {
        try await withThrowingTaskGroup(of: [MantleResponseEvent].self) { group in
            group.addTask {
                var events: [MantleResponseEvent] = []
                for try await event in service.streamResponse(
                    modelId: "openai.gpt-5.5", input: [["role": "user", "content": "Fixture request"]],
                    maxOutputTokens: 64, reasoningEffort: "low"
                ) { events.append(event) }
                return events
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }
}

/// A session-scoped transport: every request is intercepted, including an
/// unrecognized fixture ID, so these cases can never reach AWS.
private final class ResponsesFixture {
    let id = UUID().uuidString
    let session: URLSession
    let service: MantleResponsesService
    var request: URLRequest? { ResponsesFixtureProtocol.lock.withLock { ResponsesFixtureProtocol.requests[id] } }
    var body: Data? { ResponsesFixtureProtocol.lock.withLock { ResponsesFixtureProtocol.bodies[id] } }
    var stream: AsyncThrowingStream<MantleResponseEvent, Error> {
        service.streamResponse(modelId: "openai.gpt-5.5", input: [["role": "user", "content": "Fixture request"]],
                               maxOutputTokens: 64, reasoningEffort: "low")
    }

    init(events: [String], keepsConnectionOpen: Bool = false, apiKey: String = "FIXTURE_ONLY") {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponsesFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Response-Fixture": id]
        session = URLSession(configuration: configuration)
        let credentials = StaticAWSCredentialIdentityResolver(AWSCredentialIdentity(
            accessKey: "FIXTURE_ONLY", secret: "NOT_A_REAL_SECRET"))
        service = MantleResponsesService(region: "us-west-2", apiKey: apiKey, credentialResolver: credentials, session: session)
        let data = Data(events.map { "data:\($0)\n\n" }.joined().utf8)
        ResponsesFixtureProtocol.lock.withLock {
            ResponsesFixtureProtocol.replies[id] = (data, keepsConnectionOpen)
        }
    }

    func close() {
        session.invalidateAndCancel()
        ResponsesFixtureProtocol.lock.withLock {
            ResponsesFixtureProtocol.replies.removeValue(forKey: id)
            ResponsesFixtureProtocol.requests.removeValue(forKey: id)
            ResponsesFixtureProtocol.bodies.removeValue(forKey: id)
        }
    }
}

private final class ResponsesFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var replies: [String: (Data, Bool)] = [:]
    nonisolated(unsafe) static var requests: [String: URLRequest] = [:]
    nonisolated(unsafe) static var bodies: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Response-Fixture") ?? ""
        let reply = Self.lock.withLock { Self.replies[id] }
        guard let reply, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while bytes.count < 64_000 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            body = bytes
        }
        Self.lock.withLock {
            Self.requests[id] = request
            Self.bodies[id] = body
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.0)
        if !reply.1 { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}
