import AppKit

/// Semantic containers are retained alongside TextKit's flattened layout.
/// List markers stay outside the selection while copied HTML remains a list.
enum MarkdownClipboardContainer: Hashable, Sendable {
    case quote(Int)
    case list(id: Int, start: Int?)
    case item(id: Int, ordinal: Int?)

    var closingTag: String {
        switch self {
        case .quote: "</blockquote>"
        case .list(_, let start): start == nil ? "</ul>" : "</ol>"
        case .item: "</li>"
        }
    }

    func openingTag(next: Self?) -> String {
        switch self {
        case .quote: return "<blockquote>"
        case .list(_, let start):
            guard let start else { return "<ul>" }
            let first: Int
            if let next, case .item(_, let ordinal) = next { first = ordinal ?? start }
            else { first = start }
            return first == 1 ? "<ol>" : "<ol start=\"\(first)\">"
        case .item(_, let ordinal):
            return ordinal.map { "<li value=\"\($0)\">" } ?? "<li>"
        }
    }
}

struct MarkdownClipboardBlock {
    struct Cell {
        let range: NSRange
        let row: Int
        let isHeader: Bool
    }

    enum Kind {
        case text(tag: String)
        case code(NSRange)
        case table([Cell])
        case rule
    }

    let range: NSRange
    let containers: [MarkdownClipboardContainer]
    let kind: Kind
}

@MainActor
enum MarkdownClipboard {
    static let strongKey = NSAttributedString.Key("BedrockStrong")
    static let emphasisKey = NSAttributedString.Key("BedrockEmphasis")

    /// Export only selected characters. No HTML import, WebView, theme colors,
    /// or additional Markdown parsing is needed when the user presses Copy.
    static func html(text: NSAttributedString, blocks: [MarkdownClipboardBlock], ranges: [NSRange]) -> String? {
        let valid = ranges.filter {
            $0.location != NSNotFound && $0.length > 0 &&
            $0.location <= text.length && $0.length <= text.length - $0.location
        }
        guard !valid.isEmpty else { return nil }
        var fragments: [String] = []
        for selection in valid {
            var open: [MarkdownClipboardContainer] = []
            for block in blocks {
                let selected = NSIntersectionRange(block.range, selection)
                guard selected.length > 0 else { continue }
                let content = blockHTML(block, selected: selected, text: text)
                guard !content.isEmpty else { continue }
                var common = 0
                while common < min(open.count, block.containers.count),
                      open[common] == block.containers[common] { common += 1 }
                for container in open.dropFirst(common).reversed() { fragments.append(container.closingTag) }
                for index in common..<block.containers.count {
                    let next = index + 1 < block.containers.count ? block.containers[index + 1] : nil
                    fragments.append(block.containers[index].openingTag(next: next))
                }
                open = block.containers
                fragments.append(content)
            }
            for container in open.reversed() { fragments.append(container.closingTag) }
        }
        guard !fragments.isEmpty else { return nil }
        return document(fragments.joined())
    }

    static func document(_ fragment: String) -> String {
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body><!--StartFragment-->" +
            fragment + "<!--EndFragment--></body></html>"
    }

    private static func blockHTML(_ block: MarkdownClipboardBlock, selected: NSRange,
                                  text: NSAttributedString) -> String {
        switch block.kind {
        case .text(let tag):
            let body = inlineHTML(text, range: trimmingTerminator(selected, text: text))
            return body.isEmpty ? "" : "<\(tag)>\(body)</\(tag)>"
        case .code(let range):
            let part = NSIntersectionRange(range, selected)
            guard part.length > 0 else { return "" }
            return "<pre><code>\(escape((text.string as NSString).substring(with: part)))</code></pre>"
        case .table(let cells):
            var html = "", currentRow: Int?
            for cell in cells {
                let part = NSIntersectionRange(cell.range, selected)
                guard part.length > 0 else { continue }
                if currentRow != cell.row {
                    if currentRow != nil { html += "</tr>" }
                    html += "<tr>"
                    currentRow = cell.row
                }
                let tag = cell.isHeader ? "th" : "td"
                html += "<\(tag)>\(inlineHTML(text, range: trimmingTerminator(part, text: text)))</\(tag)>"
            }
            return currentRow == nil ? "" : "<table>\(html)</tr></table>"
        case .rule:
            return "<hr>"
        }
    }

    private static func trimmingTerminator(_ range: NSRange, text: NSAttributedString) -> NSRange {
        guard range.length > 0, (text.string as NSString).character(at: NSMaxRange(range) - 1) == 10 else { return range }
        return NSRange(location: range.location, length: range.length - 1)
    }

    private static func inlineHTML(_ text: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var parts: [String] = []
        text.enumerateAttributes(in: range) { attributes, run, _ in
            var content = escape((text.string as NSString).substring(with: run)).replacingOccurrences(of: "\n", with: "<br>")
            if attributes[MarkdownNativeAttributedDocument.inlineCodeKey] != nil { content = "<code>\(content)</code>" }
            if attributes[emphasisKey] != nil { content = "<em>\(content)</em>" }
            if attributes[strongKey] != nil { content = "<strong>\(content)</strong>" }
            if let url = attributes[.link] as? URL, MarkdownLinkPolicy.allowsExternalLink(url) {
                content = "<a href=\"\(escape(url.absoluteString))\">\(content)</a>"
            }
            parts.append(content)
        }
        return parts.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum MarkdownClipboardScript {
    static let source = #"""
    window.bedrockSelectionPayload = () => {
        const selection = window.getSelection();
        const content = document.getElementById('bedrock-content');
        if (!selection || selection.isCollapsed || !content) return null;
        const output = document.createElement('div');
        const allowed = new Set(['p','br','hr','h1','h2','h3','h4','h5','h6','ul','ol','li',
            'blockquote','pre','code','strong','b','em','i','del','s','a','table','thead',
            'tbody','tfoot','tr','th','td','sup','sub']);
        const mathTags = new Set(['math','semantics','annotation','mrow','mi','mn','mo','mtext',
            'msup','msub','msubsup','mfrac','msqrt','mroot','mtable','mtr','mtd','munder',
            'mover','munderover','mspace','menclose','mstyle','mphantom','mpadded']);
        const mathAttributes = new Set(['display','mathvariant','scriptlevel','displaystyle','rowspacing',
            'columnspacing','rowalign','columnalign','linethickness','minsize','maxsize','stretchy',
            'fence','separator','accent','accentunder','movablelimits','notation','width','height',
            'depth','lspace','rspace']);
        const remove = new Set(['script','style','button','svg','img','iframe','object','embed',
            'link','meta','base','form','input','textarea','select','video','audio']);
        const plain = [];
        for (let index = 0; index < selection.rangeCount; index++) {
            const original = selection.getRangeAt(index);
            if (!original.intersectsNode(content)) continue;
            const range = original.cloneRange();
            const bounds = document.createRange(); bounds.selectNodeContents(content);
            if (range.compareBoundaryPoints(Range.START_TO_START, bounds) < 0) {
                range.setStart(bounds.startContainer, bounds.startOffset);
            }
            if (range.compareBoundaryPoints(Range.END_TO_END, bounds) > 0) {
                range.setEnd(bounds.endContainer, bounds.endOffset);
            }
            let selectedText = range.toString();
            for (const equation of content.querySelectorAll('span[data-bedrock-math]')) {
                if (!range.intersectsNode(equation)) continue;
                try {
                    const bytes = Uint8Array.from(atob(equation.dataset.bedrockMath), value => value.charCodeAt(0));
                    if (bytes.length > 4096) continue;
                    const source = new TextDecoder().decode(bytes);
                    const display = equation.dataset.mathDisplay === 'true';
                    // MathML includes a hidden TeX annotation. Copy a complete
                    // selected formula once, with editable TeX in plain text.
                    selectedText = selectedText.replace(equation.textContent,
                        display ? `$$${source}$$` : `\\(${source}\\)`);
                } catch {}
            }
            plain.push(selectedText);
            let fragment = range.cloneContents();
            let parent = range.commonAncestorContainer;
            if (parent.nodeType === Node.TEXT_NODE) parent = parent.parentElement;
            // cloneContents omits common ancestors, including a partly selected
            // strong/emphasis node or the enclosing list.
            while (parent && parent !== content) {
                const wrapper = parent.cloneNode(false);
                if (parent.tagName === 'OL') {
                    const items = Array.from(parent.children).filter(node => node.tagName === 'LI');
                    const first = items.findIndex(item => range.intersectsNode(item));
                    if (first >= 0) {
                        let ordinal = Number(parent.getAttribute('start') || 1);
                        for (let i = 0; i <= first; i++) {
                            if (items[i].hasAttribute('value')) ordinal = Number(items[i].getAttribute('value'));
                            if (i !== first) ordinal++;
                        }
                        wrapper.setAttribute('start', String(ordinal));
                    }
                }
                wrapper.append(fragment);
                fragment = wrapper;
                parent = parent.parentElement;
            }
            output.append(fragment);
        }
        for (const element of Array.from(output.querySelectorAll('*'))) {
            const tag = element.tagName.toLowerCase();
            if (remove.has(tag)) { element.remove(); continue; }
            if (!allowed.has(tag) && !mathTags.has(tag)) { element.replaceWith(...element.childNodes); continue; }
            for (const attribute of Array.from(element.attributes)) {
                const name = attribute.name.toLowerCase();
                let keep = ['colspan','rowspan'].includes(name) && ['td','th'].includes(tag) &&
                    /^\d+$/.test(attribute.value);
                keep ||= (name === 'start' && tag === 'ol' || name === 'value' && tag === 'li') &&
                    /^-?\d+$/.test(attribute.value);
                if (tag === 'a' && name === 'href') {
                    try {
                        const url = new URL(attribute.value);
                        keep = !url.username && !url.password && ['https:','http:','mailto:'].includes(url.protocol);
                    } catch { keep = false; }
                }
                if (mathTags.has(tag)) {
                    keep ||= name === 'xmlns' && tag === 'math' &&
                        attribute.value === 'http://www.w3.org/1998/Math/MathML';
                    keep ||= name === 'encoding' && tag === 'annotation' && attribute.value === 'application/x-tex';
                    keep ||= mathAttributes.has(name) && attribute.value.length <= 128 &&
                        /^[\w\s.+%,-]+$/.test(attribute.value);
                }
                if (!keep) element.removeAttribute(attribute.name);
            }
        }
        if (!output.textContent && !output.querySelector('hr')) return null;
        return { text: plain.join('\n'), html: output.innerHTML };
    };
    document.addEventListener('copy', event => {
        const payload = window.bedrockSelectionPayload();
        if (!payload || !event.clipboardData) return;
        event.clipboardData.setData('text/plain', payload.text);
        event.clipboardData.setData('text/html', payload.html);
        event.preventDefault();
    });
    """#
}
