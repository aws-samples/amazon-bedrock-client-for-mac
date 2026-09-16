import Foundation
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MantleResponsesTests: XCTestCase {
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
        XCTAssertEqual(events, [.finished(stopReason: "end_turn", usage: nil, fallbackText: "The complete answer.")])
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

    init(events: [String], keepsConnectionOpen: Bool = false) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponsesFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Response-Fixture": id]
        session = URLSession(configuration: configuration)
        service = MantleResponsesService(region: "us-west-2", apiKey: "FIXTURE_ONLY", session: session)
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
