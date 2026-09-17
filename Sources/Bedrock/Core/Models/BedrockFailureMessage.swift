import Foundation

enum BedrockFailureMessage {
    /// Older conversations stored the entire SDK debug description. Recover its
    /// service message for display without rewriting the user's history.
    static func readable(_ source: String) -> String {
        var message = source
        if let expression = try? NSRegularExpression(pattern: #"message: Optional\("((?:\\.|[^"\\])*)"\)"#),
           let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let range = Range(match.range(at: 1), in: source) {
            // Swift/SDK descriptions can escape apostrophes, which JSON does
            // not recognize. Normalize only that escape before decoding the
            // quoted service message; never strip ordinary path backslashes.
            let encoded = "\"" + readableApostrophes(String(source[range])) + "\""
            message = (try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))) ?? String(source[range])
        } else if source.contains("httpResponse:") || source.contains("(properties:") {
            return "Bedrock could not complete this request. Check the selected model and AWS connection, then try again."
        }
        message = message.replacingOccurrences(of: "Error invoking the model: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        message = readableApostrophes(message)
        if message.contains("on-demand throughput") && message.contains("inference profile") {
            return "This model requires an inference profile. Refresh the model catalog in Settings → AWS connection, then choose the model again."
        }
        return message.isEmpty ? "Bedrock did not return a response. Please try again." : message
    }

    private static func readableApostrophes(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\+'"#, with: "'", options: .regularExpression)
    }
}
