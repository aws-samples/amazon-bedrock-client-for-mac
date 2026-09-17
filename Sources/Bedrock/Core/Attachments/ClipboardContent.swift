import Foundation

struct ClipboardHTMLContent: Sendable, Equatable {
    var text: String
    var imageSources: [String]
}

/// A bounded, non-rendering clipboard reader. HTML is data: never instantiate a
/// web view, load a stylesheet, run JavaScript, or resolve a file URL to get text.
enum ClipboardHTMLParser {
    static let maximumHTMLBytes = 8_000_000
    static let maximumTextBytes = 4_500_000
    static let maximumImages = 20
    private static let ignored: Set<String> = ["script", "style", "head", "iframe", "object", "template", "noscript"]
    private static let blocks: Set<String> = ["br", "p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "blockquote", "section", "article", "hr"]

    static func parse(_ html: String, includeText: Bool = true) throws -> ClipboardHTMLContent {
        guard html.utf8.count <= maximumHTMLBytes else { throw LocalOperationError.tooLarge(maximumHTMLBytes) }
        let bytes = Array(html.utf8)
        var text: [UInt8] = []
        text.reserveCapacity(includeText ? min(bytes.count, maximumTextBytes) : 0)
        var images: [String] = []
        var seen = Set<String>()
        var ignoredTag: String?
        var offset = 0
        var textStart = 0
        func appendText(_ range: Range<Int>) throws {
            guard includeText, ignoredTag == nil, !range.isEmpty else { return }
            guard text.count + range.count <= maximumTextBytes else { throw LocalOperationError.tooLarge(maximumTextBytes) }
            text.append(contentsOf: bytes[range])
        }
        while offset < bytes.count {
            if offset.isMultiple(of: 4096) { try Task.checkCancellation() }
            guard bytes[offset] == 60 else { offset += 1; continue } // <
            try appendText(textStart..<offset)
            if bytes[offset...].starts(with: [60, 33, 45, 45]) {
                offset += 4
                while offset + 2 < bytes.count && !bytes[offset...].starts(with: [45, 45, 62]) { offset += 1 }
                offset = min(bytes.count, offset + 3)
                textStart = offset
                continue
            }
            var end = offset + 1
            var quote: UInt8?
            while end < bytes.count {
                let byte = bytes[end]
                if let active = quote {
                    if byte == active { quote = nil }
                } else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 { break } // >
                end += 1
            }
            guard end < bytes.count else {
                // Malformed trailing markup is still pasteable text.
                try appendText(offset..<bytes.count)
                offset = bytes.count
                textStart = offset
                break
            }
            let tag = parseTag(bytes[(offset + 1)..<end])
            if let active = ignoredTag {
                if tag.closing && tag.name == active { ignoredTag = nil }
            } else if ignored.contains(tag.name) && !tag.closing {
                ignoredTag = tag.name
            } else {
                if includeText && blocks.contains(tag.name) && !text.isEmpty && text.last != 10 { text.append(10) }
                if tag.name == "td" && !tag.closing && !text.isEmpty && text.last != 10 { text.append(9) }
                if tag.name == "img", !tag.closing, images.count < maximumImages,
                   let raw = tag.source, !raw.isEmpty {
                    let source = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isImageSourceAllowed(source), seen.insert(source).inserted { images.append(source) }
                }
            }
            offset = end + 1
            textStart = offset
        }
        try appendText(textStart..<bytes.count)
        return ClipboardHTMLContent(text: decodeEntities(String(decoding: text, as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines),
                                    imageSources: images)
    }

    static func isImageSourceAllowed(_ value: String) -> Bool {
        if value.lowercased().hasPrefix("data:image/") {
            guard let comma = value.firstIndex(of: ",") else { return false }
            let header = value[..<comma].lowercased()
            return ["data:image/png;base64", "data:image/jpeg;base64", "data:image/gif;base64",
                    "data:image/webp;base64", "data:image/heic;base64", "data:image/tiff;base64",
                    "data:image/svg+xml;base64"].contains(header)
        }
        return (try? LocalPath.validatedWebURL(value, allowedDomains: "")) != nil
    }

    private static func parseTag(_ slice: ArraySlice<UInt8>) -> (name: String, closing: Bool, source: String?) {
        let bytes = Array(slice)
        var index = 0
        func whitespace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
        while index < bytes.count && whitespace(bytes[index]) { index += 1 }
        let closing = index < bytes.count && bytes[index] == 47
        if closing { index += 1 }
        let start = index
        while index < bytes.count && ((65...90).contains(bytes[index]) || (97...122).contains(bytes[index]) || (48...57).contains(bytes[index])) { index += 1 }
        let name = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
        guard name == "img", !closing else { return (name, closing, nil) }
        var source: String?
        while index < bytes.count {
            while index < bytes.count && (whitespace(bytes[index]) || bytes[index] == 47) { index += 1 }
            let keyStart = index
            while index < bytes.count && !whitespace(bytes[index]) && bytes[index] != 61 && bytes[index] != 47 { index += 1 }
            let key = String(decoding: bytes[keyStart..<index], as: UTF8.self).lowercased()
            while index < bytes.count && whitespace(bytes[index]) { index += 1 }
            guard index < bytes.count && bytes[index] == 61 else {
                if keyStart == index { index += 1 }
                continue
            }
            index += 1
            while index < bytes.count && whitespace(bytes[index]) { index += 1 }
            guard index < bytes.count else { break }
            let quote: UInt8? = bytes[index] == 34 || bytes[index] == 39 ? bytes[index] : nil
            if quote != nil { index += 1 }
            let valueStart = index
            while index < bytes.count {
                if let quote, bytes[index] == quote { break }
                if quote == nil && whitespace(bytes[index]) { break }
                index += 1
            }
            if key == "src" && source == nil { source = String(decoding: bytes[valueStart..<index], as: UTF8.self) }
            if quote != nil && index < bytes.count { index += 1 }
        }
        return (name, closing, source)
    }

    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                        "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "reg": "®",
                        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•"]
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "&" else {
                result.append(value[index]); value.formIndex(after: &index); continue
            }
            let tail = value.index(after: index)
            let limit = value.index(tail, offsetBy: 16, limitedBy: value.endIndex) ?? value.endIndex
            guard let end = value[tail..<limit].firstIndex(of: ";") else {
                result.append("&"); value.formIndex(after: &index); continue
            }
            let name = String(value[tail..<end])
            var replacement = entities[name]
            if name.hasPrefix("#") {
                let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
                if let number = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                   number != 0, let scalar = UnicodeScalar(number) { replacement = String(scalar) }
            }
            if let replacement {
                result += replacement
                index = value.index(after: end)
            } else {
                result.append("&"); value.formIndex(after: &index)
            }
        }
        return result
    }
}
