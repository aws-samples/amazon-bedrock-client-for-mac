import Foundation

struct StreamedToolCall: Equatable, Sendable {
    let index: Int
    let id: String
    let name: String
    var inputJSON = ""
    var completed = false
}

struct ToolStreamAccumulator: Sendable {
    private var calls: [Int: StreamedToolCall] = [:]
    mutating func begin(index: Int, id: String, name: String) throws {
        guard calls[index] == nil, !calls.values.contains(where: { $0.id == id }), !id.isEmpty, !name.isEmpty else {
            throw LocalWorkbenchError.invalid("The model returned a duplicate or incomplete tool call.")
        }
        calls[index] = .init(index: index, id: id, name: name)
    }
    mutating func append(index: Int, json: String) throws {
        guard var call = calls[index], !call.completed else {
            throw LocalWorkbenchError.invalid("The model returned tool input without a matching start.")
        }
        guard call.inputJSON.utf8.count + json.utf8.count <= 1_048_576 else { throw LocalWorkbenchError.tooLarge(1_048_576) }
        call.inputJSON += json
        calls[index] = call
    }
    mutating func complete(index: Int) throws {
        guard var call = calls[index] else { return } // Text and reasoning have block-stop events too.
        if call.inputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { call.inputJSON = "{}" }
        guard let data = call.inputJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw LocalWorkbenchError.invalid("The model returned invalid JSON input for \(call.name).")
        }
        call.completed = true
        calls[index] = call
    }
    func finish() throws -> [StreamedToolCall] {
        guard calls.values.allSatisfy(\.completed) else {
            throw LocalWorkbenchError.invalid("The response ended before all tool inputs arrived. Retry the response.")
        }
        return calls.values.sorted { $0.index < $1.index }
    }
}
