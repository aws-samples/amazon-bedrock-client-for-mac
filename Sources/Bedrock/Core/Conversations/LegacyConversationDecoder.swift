import Foundation

enum LegacyConversationDecoder {
    static func decode(_ data: Data) throws -> [MessageData] {
        // Codable files use the 2001 reference date. Do not reinterpret them as
        // Unix timestamps when migrating an otherwise valid older conversation.
        if let messages = try? JSONDecoder().decode([MessageData].self, from: data) { return messages }
        guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LocalOperationError.invalid("The legacy conversation is not a message array.")
        }
        let aliases = [
            "isError": "is_error", "thinkingSummary": "thinking_summary",
            "imageBase64Strings": "image_base64_strings", "documentBase64Strings": "document_base64_strings",
            "documentFormats": "document_formats", "documentNames": "document_names",
            "pastedTexts": "pasted_texts", "toolUse": "tool_use", "toolResult": "tool_result",
            "toolUses": "tool_uses", "videoUrl": "video_url", "videoS3Uri": "video_s3_uri", "modelID": "model_id"
        ]
        return try records.map { original in
            var record = original
            for (old, current) in aliases where record[current] == nil { record[current] = record[old] }
            record["is_error"] = record["is_error"] ?? false
            guard let id = record["id"] as? String, UUID(uuidString: id) != nil,
                  record["text"] is String, record["user"] is String else {
                throw LocalOperationError.invalid("A legacy message is missing its ID, text, or role. The original file was preserved.")
            }
            if let number = original["sentTime"] as? Double {
                record["sent_time"] = Date(timeIntervalSince1970: number).timeIntervalSinceReferenceDate
            } else if let string = (original["sent_time"] ?? original["sentTime"]) as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
                guard let date else { throw LocalOperationError.invalid("A legacy message has an unreadable timestamp.") }
                record["sent_time"] = date.timeIntervalSinceReferenceDate
            } else if let number = original["sent_time"] as? Double, number > 1_200_000_000 {
                record["sent_time"] = Date(timeIntervalSince1970: number).timeIntervalSinceReferenceDate
            } else if record["sent_time"] == nil {
                // Very old files omitted timestamps. Preserve their order and use
                // a fixed unknown date, rather than making old messages look new.
                record["sent_time"] = Date(timeIntervalSince1970: 0).timeIntervalSinceReferenceDate
            }
            return try JSONDecoder().decode(MessageData.self, from: JSONSerialization.data(withJSONObject: record))
        }
    }
}
