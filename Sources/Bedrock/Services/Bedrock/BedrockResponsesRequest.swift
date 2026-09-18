import Foundation

/// Responses carries real file/image parts and function items. Flattening a
/// conversation to strings loses its attachments and tool protocol.
enum BedrockResponsesRequest {
    static func input(_ history: [BedrockMessage], systemPrompt: String = "") throws -> [[String: Any]] {
        var input: [[String: Any]] = []
        if !systemPrompt.isEmpty { input.append(["role": "developer", "content": systemPrompt]) }
        for message in history {
            var parts: [[String: Any]] = []
            func flush() {
                guard !parts.isEmpty else { return }
                if message.role == .assistant {
                    let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
                    if !text.isEmpty { input.append(["role": "assistant", "content": text]) }
                } else {
                    input.append(["role": "user", "content": parts])
                }
                parts.removeAll(keepingCapacity: true)
            }
            for content in message.content {
                switch content {
                case .text(let text):
                    if !text.isEmpty { parts.append(["type": "input_text", "text": text]) }
                case .image(let image):
                    parts.append(imagePart(image.base64Data, format: image.format.rawValue))
                case .document(let document):
                    let format = document.format.rawValue
                    let name = documentFilename(document.name, format: format)
                    guard let bytes = Data(base64Encoded: document.base64Data), !bytes.isEmpty else {
                        throw LocalOperationError.invalid("The attached file \(name) could not be read.")
                    }
                    parts.append(["type": "input_file", "filename": name,
                                  "file_data": "data:\(documentMIMEType(format));base64,\(document.base64Data)"])
                case .thinking:
                    break // Converse reasoning signatures are not Responses items.
                case .tooluse(let call):
                    flush()
                    let arguments = try JSONEncoder().encode(call.input)
                    input.append(["type": "function_call", "call_id": call.toolUseId, "name": call.name,
                                  "arguments": String(decoding: arguments, as: UTF8.self)])
                case .toolresult(let result):
                    flush()
                    input.append(["type": "function_call_output", "call_id": result.toolUseId, "output": result.result])
                    if let images = result.images, !images.isEmpty {
                        var attachments: [[String: Any]] = [
                            ["type": "input_text", "text": "Images returned by tool call \(result.toolUseId):"]
                        ]
                        attachments += images.map { imagePart($0.base64, format: $0.format) }
                        input.append(["role": "user", "content": attachments])
                    }
                }
            }
            flush()
        }
        return input
    }

    static func toolCalls(in output: [JSONValue]) throws -> [StreamedToolCall] {
        var accumulator = ToolStreamAccumulator()
        for (index, item) in output.enumerated() {
            guard let object = item.asDictionary, object["type"] as? String == "function_call" else { continue }
            guard let id = object["call_id"] as? String, let name = object["name"] as? String,
                  let arguments = object["arguments"] as? String,
                  object["status"] as? String != "in_progress", object["status"] as? String != "incomplete" else {
                throw LocalOperationError.invalid("The response ended before the tool input was complete.")
            }
            try accumulator.begin(index: index, id: id, name: name)
            try accumulator.append(index: index, json: arguments)
            try accumulator.complete(index: index)
        }
        return try accumulator.finish()
    }

    static func documentFilename(_ name: String, format: String) -> String {
        let filename = (name as NSString).lastPathComponent
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = filename.isEmpty ? "Document" : filename
        return clean.lowercased().hasSuffix("." + format) ? clean : clean + "." + format
    }

    private static func documentMIMEType(_ format: String) -> String {
        [
            "pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown",
            "csv": "text/csv", "html": "text/html", "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ][format] ?? "application/octet-stream"
    }

    private static func imagePart(_ base64: String, format: String) -> [String: Any] {
        ["type": "input_image", "image_url": "data:image/\(format == "jpg" ? "jpeg" : format);base64,\(base64)",
         "detail": "auto"]
    }
}
