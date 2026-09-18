import Foundation

/// Protect complete equations before Markdown consumes TeX escapes or underscores.
/// Code, link destinations, currency and unfinished streaming delimiters stay literal.
enum MarkdownMath {
    static let maximumExpressionBytes = 4_096
    static let maximumExpressions = 128

    static func prepare(_ source: String) -> String {
        guard source.contains("$") || source.contains("\\(") || source.contains("\\[") else { return source }
        let bytes = Array(source.utf8)
        var index = 0, copied = 0, count = 0
        var scanBudget = max(16_384, min(bytes.count * 3, 1_048_576))
        var result = ""
        var fence: (character: UInt8, length: Int)?
        var cachedLineEnd = -1

        func run(_ start: Int, _ character: UInt8) -> Int {
            var end = start
            while end < bytes.count, bytes[end] == character { end += 1 }
            return end - start
        }
        func lineEnd(_ start: Int) -> Int {
            if start <= cachedLineEnd { return cachedLineEnd }
            var end = start
            while end < bytes.count, bytes[end] != 10 { end += 1 }
            cachedLineEnd = end
            return end
        }
        func whitespace(_ character: UInt8) -> Bool { character == 32 || character == 9 || character == 10 || character == 13 }
        func string(_ start: Int, _ end: Int) -> String { String(decoding: bytes[start..<end], as: UTF8.self) }

        while index < bytes.count, count < maximumExpressions, scanBudget > 0 {
            if index == 0 || bytes[index - 1] == 10 {
                let end = lineEnd(index)
                var content = index
                while content < end, bytes[content] == 32 { content += 1 }
                while content < end, bytes[content] == 62 {
                    content += 1
                    while content < end, bytes[content] == 32 { content += 1 }
                }
                if let open = fence {
                    if content < end, bytes[content] == open.character {
                        let length = run(content, open.character)
                        if length >= open.length, bytes[(content + length)..<end].allSatisfy(whitespace) { fence = nil }
                    }
                    index = min(end + 1, bytes.count); continue
                }
                if (run(index, 32) >= 4) || (content < end && bytes[content] == 9) {
                    index = min(end + 1, bytes.count); continue
                }
                if content + 2 < end, [UInt8(45), 42, 43].contains(bytes[content]), bytes[content + 1] == 32 {
                    content += 2
                    while content < end, bytes[content] == 32 { content += 1 }
                }
                if content < end, bytes[content] == 96 || bytes[content] == 126 {
                    let length = run(content, bytes[content])
                    if length >= 3 {
                        fence = (bytes[content], length)
                        index = min(end + 1, bytes.count); continue
                    }
                }
            }
            if bytes[index] == 96 {
                let length = run(index, 96)
                var next = index + length
                var found = false
                while next < bytes.count, scanBudget > 0 {
                    scanBudget -= 1
                    if bytes[next] == 96 {
                        let closing = run(next, 96)
                        if closing == length { next += closing; found = true; break }
                        next += closing
                    } else { next += 1 }
                }
                index = found ? next : index + length
                continue
            }
            if bytes[index] == 60, index + 1 < bytes.count,
               (65...90).contains(bytes[index + 1]) || (97...122).contains(bytes[index + 1]) ||
               bytes[index + 1] == 47 || bytes[index + 1] == 33 {
                // Do not reinterpret TeX-like text in raw HTML code or attributes.
                let end = lineEnd(index)
                var close = index + 1
                var quote: UInt8?
                while close < end, scanBudget > 0 {
                    scanBudget -= 1
                    let character = bytes[close]
                    if let current = quote {
                        if character == current { quote = nil }
                    } else if character == 34 || character == 39 { quote = character }
                    else if character == 62 { break }
                    close += 1
                }
                if close < end, bytes[close] == 62 {
                    let tag = string(index, min(close + 1, index + 9)).lowercased()
                    if let raw = ["code", "pre", "script", "style"].first(where: {
                        tag == "<\($0)>" || tag.hasPrefix("<\($0) ")
                    }) {
                        let closing = Array("</\(raw)>".utf8)
                        var next = close + 1
                        while next + closing.count <= bytes.count, scanBudget > 0 {
                            scanBudget -= 1
                            if closing.indices.allSatisfy({ offset in
                                let byte = bytes[next + offset]
                                return ((65...90).contains(byte) ? byte + 32 : byte) == closing[offset]
                            }) { break }
                            next += 1
                        }
                        if next + closing.count <= bytes.count, scanBudget > 0 {
                            index = next + closing.count; continue
                        }
                    }
                    index = close + 1; continue
                }
            }
            if bytes[index] == 93, index + 1 < bytes.count, bytes[index + 1] == 40 {
                var next = index + 2, depth = 1
                while next < bytes.count, depth > 0, scanBudget > 0 {
                    scanBudget -= 1
                    if bytes[next] == 92 { next = min(next + 2, bytes.count); continue }
                    if bytes[next] == 40 { depth += 1 }
                    if bytes[next] == 41 { depth -= 1 }
                    next += 1
                }
                if depth == 0 { index = next; continue }
            }

            let opening: Int
            let closing: [UInt8]
            let display: Bool
            if bytes[index] == 92, index + 1 < bytes.count, bytes[index + 1] == 40 || bytes[index + 1] == 91 {
                opening = 2; display = bytes[index + 1] == 91
                closing = [92, display ? 93 : 41]
            } else if bytes[index] == 36 {
                display = index + 1 < bytes.count && bytes[index + 1] == 36
                opening = display ? 2 : 1
                closing = display ? [36, 36] : [36]
                if index + opening >= bytes.count || (!display && whitespace(bytes[index + opening])) {
                    index += opening; continue
                }
            } else {
                index += bytes[index] == 92 ? min(2, bytes.count - index) : 1
                continue
            }
            let start = index + opening
            let limit = min(bytes.count, start + maximumExpressionBytes + closing.count)
            var end = start
            var match: Int?
            while end + closing.count <= limit, scanBudget > 0 {
                scanBudget -= 1
                if !display && bytes[end] == 10 { break }
                if bytes[end] == closing[0], closing.count == 1 || bytes[end + 1] == closing[1] {
                    if closing == [36] {
                        let followsDigit = end + 1 < bytes.count && (48...57).contains(bytes[end + 1])
                        if end == start || whitespace(bytes[end - 1]) || followsDigit { end += 1; continue }
                    }
                    match = end; break
                }
                end += bytes[end] == 92 ? 2 : 1
            }
            if let end = match, end > start, end - start <= maximumExpressionBytes {
                let latex = string(start, end).trimmingCharacters(in: .whitespacesAndNewlines)
                if !latex.isEmpty {
                    result += string(copied, index)
                    result += placeholder(latex, display: display)
                    index = end + closing.count
                    copied = index
                    count += 1
                    continue
                }
            }
            index += opening
        }
        guard copied > 0 else { return source }
        result += string(copied, bytes.count)
        return result
    }

    private static func placeholder(_ latex: String, display: Bool) -> String {
        let encoded = Data(latex.utf8).base64EncodedString()
        // Entities protect the fallback from Markdown's later inline transforms.
        let fallback = latex.unicodeScalars.map { "&#\($0.value);" }.joined()
        return "<span class=\"bedrock-math\(display ? " math-display" : "")\" data-bedrock-math=\"\(encoded)\" data-math-display=\"\(display)\">\(fallback)</span>"
    }
}
