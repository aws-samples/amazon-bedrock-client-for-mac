import AppKit
import Combine
import JavaScriptCore
import MarkdownKit
import SwiftUI

enum MarkdownSanitizerScript {
    static let source = #"""
    window.bedrockSanitize = fragment => {
        const remove = new Set(['script','style','iframe','object','embed','link','meta','base','form','input','textarea','select','video','audio','source','math','foreignobject','animate','set']);
        const allowed = new Set(['p','div','span','br','hr','h1','h2','h3','h4','h5','h6','ul','ol','li','blockquote','pre','code','strong','b','em','i','del','s','a','img','table','thead','tbody','tfoot','tr','th','td','sup','sub','details','summary','button','svg','path']);
        const attributes = new Set(['class','id','title','aria-label','aria-hidden','role','colspan','rowspan','align','width','height','viewbox','fill','d','stroke','stroke-width','data-code-id','alt']);
        const safeLink = value => {
            try {
                const url = new URL(value);
                return !url.username && !url.password && ['https:','http:','mailto:'].includes(url.protocol);
            } catch { return false; }
        };
        for (const element of Array.from(fragment.querySelectorAll('*'))) {
            const tag = element.tagName.toLowerCase();
            if (remove.has(tag)) { element.remove(); continue; }
            if (!allowed.has(tag)) { element.replaceWith(...element.childNodes); continue; }
            if (tag === 'img') {
                const src = element.getAttribute('src') || '';
                if (!/^data:image\/(?:png|jpeg|gif|webp);base64,/i.test(src)) {
                    const label = document.createElement(safeLink(src) ? 'a' : 'span');
                    label.textContent = element.getAttribute('alt') || 'View image';
                    if (safeLink(src)) label.setAttribute('href', src);
                    element.replaceWith(label);
                    continue;
                }
            }
            for (const attribute of Array.from(element.attributes)) {
                const name = attribute.name.toLowerCase();
                const keep = attributes.has(name) ||
                    (tag === 'a' && name === 'href' && safeLink(attribute.value)) ||
                    (tag === 'img' && name === 'src') ||
                    ((tag === 'ol' && name === 'start' || tag === 'li' && name === 'value') &&
                     /^-?\d+$/.test(attribute.value));
                if (!keep) element.removeAttribute(attribute.name);
            }
        }
        return fragment;
    };
    """#
}

enum MarkdownDOMUpdateScript {
    static let source = MarkdownSanitizerScript.source + #"""
    let bedrockSourceBlocks = null;
    const bedrockStreamAnimations = new Set();
    const bedrockPatchNode = (current, incoming) => {
        if (current.nodeType !== incoming.nodeType || current.nodeName !== incoming.nodeName) {
            current.replaceWith(incoming);
            return incoming;
        }
        if (current.nodeType === Node.TEXT_NODE) {
            if (incoming.data.startsWith(current.data)) current.appendData(incoming.data.slice(current.length));
            else current.replaceData(0, current.length, incoming.data);
            return current;
        }
        if (current.nodeType !== Node.ELEMENT_NODE) {
            if (!current.isEqualNode(incoming)) current.replaceWith(incoming);
            return current;
        }
        for (const attribute of Array.from(current.attributes)) {
            if (!incoming.hasAttribute(attribute.name)) current.removeAttribute(attribute.name);
        }
        for (const attribute of Array.from(incoming.attributes)) {
            if (current.getAttribute(attribute.name) !== attribute.value) current.setAttribute(attribute.name, attribute.value);
        }
        const oldChildren = Array.from(current.childNodes);
        const newChildren = Array.from(incoming.childNodes);
        newChildren.forEach((child, index) => {
            if (!oldChildren[index]) current.appendChild(child);
            else if (!oldChildren[index].isEqualNode(child)) bedrockPatchNode(oldChildren[index], child);
        });
        oldChildren.slice(newChildren.length).forEach(child => child.remove());
        return current;
    };
    window.bedrockUpdateContent = (html, fontSize, streaming = false, reduceMotion = false) => {
        const content = document.getElementById('bedrock-content');
        const template = document.createElement('template');
        template.innerHTML = html;
        bedrockSanitize(template.content);
        const incoming = Array.from(template.content.children);
        const sources = incoming.map(node => node.outerHTML);
        const current = Array.from(content.children);
        const appended = [];
        incoming.forEach((node, index) => {
            if (bedrockSourceBlocks && bedrockSourceBlocks[index] === sources[index]) return;
            if (current[index]) bedrockPatchNode(current[index], node);
            else { content.appendChild(node); appended.push(node); }
        });
        current.slice(incoming.length).forEach(node => node.remove());
        const firstContent = bedrockSourceBlocks === null;
        bedrockSourceBlocks = sources;
        document.documentElement.style.setProperty('--message-font-size', `${fontSize}px`);
        if (typeof hljs !== 'undefined') Array.from(content.children).forEach((node, index) => {
            // Leave an open code block alone. Replacing its highlighted spans
            // on every token destroys selection and needlessly repaints it.
            if (streaming && index === incoming.length - 1) return;
            node.querySelectorAll('pre code:not([data-highlighted])').forEach(code => {
                const language = Array.from(code.classList).find(value => value.startsWith('language-'));
                if (language && hljs.getLanguage(language.slice(9))) hljs.highlightElement(code);
            });
        });
        const reduced = reduceMotion || matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (!streaming || reduced) {
            bedrockStreamAnimations.forEach(animation => animation.cancel());
            bedrockStreamAnimations.clear();
        } else if (!firstContent) {
            // Content is present immediately. Only newly appended small blocks
            // get a brief compositor fade; height, position, existing text and
            // token delivery never animate. Bound simultaneous layer creation.
            for (const node of appended.slice(-4)) {
                if (node.getBoundingClientRect().height > 512) continue;
                while (bedrockStreamAnimations.size >= 4) {
                    const oldest = bedrockStreamAnimations.values().next().value;
                    oldest.cancel(); bedrockStreamAnimations.delete(oldest);
                }
                const animation = node.animate([{opacity: 0.72}, {opacity: 1}], {duration: 140, easing: 'ease-out'});
                bedrockStreamAnimations.add(animation);
                animation.onfinish = animation.oncancel = () => bedrockStreamAnimations.delete(animation);
            }
        }
        window.bedrockReportContentSize?.();
        // A tall WebView can be outside WebKit's visible viewport even while its
        // enclosing chat is visible. Do not depend on an animation frame there:
        // return the new extent with the update so SwiftUI can resize it now.
        return content.getBoundingClientRect().height;
    };
    """#
}

enum MarkdownSearchScript {
    static let source = #"""
    window.bedrockClearSearch = () => {
        document.querySelectorAll('.search-highlight,.search-highlight-current').forEach(mark => {
            const parent = mark.parentNode;
            mark.replaceWith(document.createTextNode(mark.textContent));
            parent.normalize();
        });
    };
    window.bedrockFind = (query, targetIndex) => {
        bedrockClearSearch();
        if (!query) return null;
        const content = document.getElementById('bedrock-content');
        const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
            acceptNode: node => node.parentElement.closest('script,style,button') ?
                NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
        });
        let text = '', node;
        const nodes = [];
        while ((node = walker.nextNode())) {
            nodes.push({ node, start: text.length, end: text.length + node.textContent.length });
            text += node.textContent;
        }
        // Fold for matching while retaining original UTF-16 offsets, including
        // emoji, decomposed accents and Hangul. Never interpolate the query.
        const fold = value => value.normalize('NFD').toLowerCase().replace(/\p{M}/gu, '');
        let searchable = '';
        const starts = [], ends = [];
        for (let offset = 0; offset < text.length;) {
            const character = String.fromCodePoint(text.codePointAt(offset));
            const folded = fold(character);
            for (let i = 0; i < folded.length; i++) {
                starts.push(offset);
                ends.push(offset + character.length);
            }
            searchable += folded;
            offset += character.length;
        }
        const term = fold(query), matches = [];
        if (!term) return null;
        for (let offset = 0; offset < searchable.length;) {
            const index = searchable.indexOf(term, offset);
            if (index < 0) break;
            matches.push({ start: starts[index], end: ends[index + term.length - 1] });
            offset = index + term.length;
        }
        if (!matches.length) return null;
        const selected = Math.min(Math.max(targetIndex, 0), matches.length - 1);
        let selectedMark = null;
        let nextMatch = 0;
        nodes.forEach(({node, start, end}) => {
            while (nextMatch < matches.length && matches[nextMatch].end <= start) nextMatch++;
            const intersections = [];
            for (let index = nextMatch; index < matches.length && matches[index].start < end; index++) {
                intersections.push({...matches[index], index});
            }
            if (!intersections.length) return;
            const fragment = document.createDocumentFragment(), original = node.textContent;
            let offset = 0;
            intersections.forEach(match => {
                const from = Math.max(0, match.start - start), to = Math.min(original.length, match.end - start);
                fragment.append(document.createTextNode(original.slice(offset, from)));
                const mark = document.createElement('span');
                mark.className = match.index === selected ? 'search-highlight-current' : 'search-highlight';
                mark.textContent = original.slice(from, to);
                fragment.append(mark);
                if (match.index === selected && !selectedMark) selectedMark = mark;
                offset = to;
            });
            fragment.append(document.createTextNode(original.slice(offset)));
            node.replaceWith(fragment);
        });
        const rect = selectedMark.getBoundingClientRect();
        return { top: rect.top + scrollY, height: rect.height, count: matches.length };
    };
    """#
}

/// Flatten containers before layout. Nested HStack/VStack lists repeatedly ask
/// their descendants for ideal sizes and alignments as a long response grows.
struct MarkdownLayoutRow: Identifiable, Equatable, @unchecked Sendable {
    let id: Int
    let block: Block
    let indent: CGFloat
    let marker: String?
    let quoteDepth: Int
    let quoteIndents: [CGFloat]
    let clipboardContainers: [MarkdownClipboardContainer]
    let spacing: CGFloat
    let revision: Int

    static func flatten(_ document: Block) -> [Self] {
        var rows: [Self] = []
        var nextContainerID = 0
        func containerID() -> Int {
            defer { nextContainerID += 1 }
            return nextContainerID
        }
        func visit(_ block: Block, indent: CGFloat = 0, marker: String? = nil, quoteDepth: Int = 0,
                   quoteIndents: [CGFloat] = [], spacing: CGFloat = 12,
                   clipboardContainers: [MarkdownClipboardContainer] = []) {
            switch block {
            case .document(let children), .listItem(_, _, let children):
                for (index, child) in children.enumerated() {
                    visit(child, indent: indent, marker: index == 0 ? marker : nil, quoteDepth: quoteDepth,
                          quoteIndents: quoteIndents, spacing: spacing, clipboardContainers: clipboardContainers)
                }
            case .list(let start, let tight, let items):
                let list = MarkdownClipboardContainer.list(id: containerID(), start: start)
                for (index, item) in items.enumerated() {
                    let ordinal = start.map { $0 + index }
                    visit(item, indent: indent + 24, marker: start.map { "\($0 + index)." } ?? "•",
                          quoteDepth: quoteDepth, quoteIndents: quoteIndents, spacing: tight ? 6 : 12,
                          clipboardContainers: clipboardContainers + [list, .item(id: containerID(), ordinal: ordinal)])
                }
            case .blockquote(let children):
                let quote = MarkdownClipboardContainer.quote(containerID())
                for child in children {
                    visit(child, indent: indent + 16, quoteDepth: quoteDepth + 1,
                          quoteIndents: quoteIndents + [indent], spacing: 8,
                          clipboardContainers: clipboardContainers + [quote])
                }
            case .referenceDef:
                break
            default:
                var hasher = Hasher()
                hasher.combine(block.description)
                hasher.combine(indent); hasher.combine(marker); hasher.combine(quoteIndents); hasher.combine(spacing)
                hasher.combine(clipboardContainers)
                rows.append(Self(id: rows.count, block: block, indent: indent, marker: marker, quoteDepth: quoteDepth,
                                 quoteIndents: quoteIndents, clipboardContainers: clipboardContainers,
                                 spacing: rows.isEmpty ? 0 : spacing, revision: hasher.finalize()))
            }
        }
        visit(document)
        return rows
    }
}

@MainActor
final class MarkdownBlockState: ObservableObject, Identifiable {
    struct Content: Equatable {
        let row: MarkdownLayoutRow
        let isStreaming: Bool
    }

    let id: Int
    @Published private(set) var content: Content

    init(row: MarkdownLayoutRow, isStreaming: Bool) {
        id = row.id
        content = Content(row: row, isStreaming: isStreaming)
    }

    func update(row: MarkdownLayoutRow, isStreaming: Bool) {
        let next = Content(row: row, isStreaming: isStreaming)
        if content != next { content = next }
    }
}

/// A token changes the open block, not every completed block in the response.
/// Publish the collection only when blocks are inserted or removed; reference
/// changes (such as a Markdown link definition) still update the affected rows.
@MainActor
final class MarkdownDocumentState: ObservableObject {
    @Published private(set) var blocks: [MarkdownBlockState]
    @Published private(set) var revision: UInt64 = 0

    init(rows: [MarkdownLayoutRow], isStreaming: Bool = false) {
        blocks = rows.map { MarkdownBlockState(row: $0, isStreaming: isStreaming && $0.id == rows.last?.id) }
    }

    func update(rows: [MarkdownLayoutRow], isStreaming: Bool) {
        for index in 0..<min(blocks.count, rows.count) {
            blocks[index].update(row: rows[index], isStreaming: isStreaming && index == rows.count - 1)
        }
        if rows.count > blocks.count {
            let added = rows.dropFirst(blocks.count).map {
                MarkdownBlockState(row: $0, isStreaming: isStreaming && $0.id == rows.last?.id)
            }
            blocks.append(contentsOf: added)
        } else if rows.count < blocks.count {
            blocks.removeLast(blocks.count - rows.count)
        }
        revision &+= 1
    }
}

struct MarkdownRenderer: View {
    @ObservedObject var document: MarkdownDocumentState
    let fontSize: CGFloat
    let highlights: [String]

    init(document: MarkdownDocumentState, fontSize: CGFloat, highlights: [String]) {
        self.document = document
        self.fontSize = fontSize
        self.highlights = highlights
    }

    init(rows: [MarkdownLayoutRow], fontSize: CGFloat, highlights: [String], isStreaming: Bool = false) {
        self.init(document: MarkdownDocumentState(rows: rows, isStreaming: isStreaming),
                  fontSize: fontSize, highlights: highlights)
    }

    var body: some View {
        SelectableMarkdown(rows: document.blocks.map(\.content.row), fontSize: fontSize, highlights: highlights,
                                    isStreaming: document.blocks.contains { $0.content.isStreaming })
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(DesignTokens.accent)
        .accessibilityElement(children: .contain)
    }
}

/// Keep the bundled highlighter's language support without a WebKit process or
/// asynchronous page layout. Source is passed as data, never evaluated as code.
@MainActor
final class CodeHighlightCache {
    static let shared = CodeHighlightCache()
    private let context: JSContext?
    private let cache = NSCache<NSString, NSAttributedString>()
    private let tags = try? NSRegularExpression(pattern: #"<span class="([^"]+)">|</span>"#)

    private init() {
        cache.totalCostLimit = 4 * 1_024 * 1_024
        cache.countLimit = 160
        if let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            context = JSContext()
            context?.evaluateScript(script)
        } else { context = nil }
    }

    func text(_ source: String, language: String, dark: Bool) -> AttributedString {
        let key = "\(dark)|\(language)|\(source)" as NSString
        if let cached = cache.object(forKey: key) { return AttributedString(cached) }
        // Unlabelled/very large blocks remain immediately readable. Avoid an
        // expensive language auto-detection pass on the main thread.
        let name = language.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
        guard source.utf8.count <= 30_000, !name.isEmpty,
              let highlighter = context?.objectForKeyedSubscript("hljs"),
              highlighter.invokeMethod("getLanguage", withArguments: [name])?.isUndefined == false,
              let html = highlighter.invokeMethod("highlight", withArguments: [source, ["language": name, "ignoreIllegals": true]])?
                .objectForKeyedSubscript("value")?.toString(), let tags else { return AttributedString(source) }
        let output = NSMutableAttributedString(string: "")
        let raw = html as NSString
        var cursor = 0
        var colors: [NSColor] = [dark ? .white : .black]
        func append(_ end: Int) {
            guard end > cursor else { return }
            let text = Self.decode(raw.substring(with: NSRange(location: cursor, length: end - cursor)))
            output.append(NSAttributedString(string: text, attributes: [.foregroundColor: colors.last!]))
        }
        for match in tags.matches(in: html, range: NSRange(location: 0, length: raw.length)) {
            append(match.range.location)
            if match.range(at: 1).location != NSNotFound {
                let token = raw.substring(with: match.range(at: 1))
                colors.append(Self.color(token, dark: dark))
            } else if colors.count > 1 { colors.removeLast() }
            cursor = NSMaxRange(match.range)
        }
        append(raw.length)
        // Never substitute a highlighter result that lost or altered source.
        guard output.string == source else { return AttributedString(source) }
        cache.setObject(output.copy() as! NSAttributedString, forKey: key, cost: source.utf8.count * 4)
        return AttributedString(output)
    }

    private static func color(_ token: String, dark: Bool) -> NSColor {
        if token.contains("comment") { return .secondaryLabelColor }
        if token.contains("string") { return dark ? NSColor(red: 0.65, green: 0.83, blue: 1, alpha: 1) : NSColor(red: 0.05, green: 0.3, blue: 0.52, alpha: 1) }
        if token.contains("keyword") || token.contains("literal") { return dark ? NSColor(red: 1, green: 0.48, blue: 0.52, alpha: 1) : NSColor(red: 0.73, green: 0.15, blue: 0.21, alpha: 1) }
        if token.contains("number") || token.contains("attr") { return dark ? NSColor(red: 0.5, green: 0.75, blue: 1, alpha: 1) : NSColor(red: 0.03, green: 0.35, blue: 0.64, alpha: 1) }
        if token.contains("title") || token.contains("built_in") { return dark ? NSColor(red: 0.83, green: 0.67, blue: 1, alpha: 1) : NSColor(red: 0.43, green: 0.22, blue: 0.67, alpha: 1) }
        return .labelColor
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}
