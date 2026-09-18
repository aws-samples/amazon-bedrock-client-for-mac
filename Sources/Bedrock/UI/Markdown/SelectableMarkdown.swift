import AppKit
import MarkdownKit
import SwiftUI

/// One TextKit selection spans paragraphs, list items, tables and code.
/// Layout stays native; rendered HTML continues through the bounded WebKit path.
struct SelectableMarkdown: NSViewRepresentable {
    let rows: [MarkdownLayoutRow]
    let fontSize: CGFloat
    let highlights: [String]
    var isStreaming = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> MarkdownSelectionTextView { MarkdownSelectionTextView() }
    func updateNSView(_ view: MarkdownSelectionTextView, context: Context) {
        view.install(rows: rows, fontSize: fontSize, highlights: highlights, dark: colorScheme == .dark,
                     isStreaming: isStreaming, reduceMotion: reduceMotion)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownSelectionTextView, context: Context) -> CGSize? {
        nsView.measuredSize(width: proposal.width ?? 760)
    }
}

/// Fade only newly received glyphs. Existing text, line metrics and token
/// delivery stay untouched, and at most four short paint effects are active.
// NSTextView creates and uses this non-Sendable layout manager only on the
// main thread, including its timer. NSLayoutManager's drawing override is not
// actor isolated; do not transfer the manager into a task from that callback.
final class MarkdownRevealLayoutManager: NSLayoutManager {
    private struct Reveal {
        let range: NSRange
        let started: TimeInterval
    }
    private var reveals: [Reveal] = []
    private var timer: Timer?
    private let duration: TimeInterval = 0.14
    var activeRevealCount: Int { reveals.count }

    func reveal(_ range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= (textStorage?.length ?? 0) else { return }
        if reveals.count == 4 {
            invalidateDisplay(forCharacterRange: reveals.removeFirst().range)
        }
        reveals.append(Reveal(range: range, started: ProcessInfo.processInfo.systemUptime))
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(advanceReveals),
                          userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func advanceReveals(_ timer: Timer) {
        let now = ProcessInfo.processInfo.systemUptime
        for reveal in reveals where NSMaxRange(reveal.range) <= (textStorage?.length ?? 0) {
            invalidateDisplay(forCharacterRange: reveal.range)
        }
        reveals.removeAll { now - $0.started >= duration }
        if reveals.isEmpty {
            timer.invalidate()
            self.timer = nil
        }
    }

    func finishReveals() {
        for reveal in reveals where NSMaxRange(reveal.range) <= (textStorage?.length ?? 0) {
            invalidateDisplay(forCharacterRange: reveal.range)
        }
        reveals.removeAll(keepingCapacity: true)
        timer?.invalidate()
        timer = nil
    }

    override func drawGlyphs(forGlyphRange glyphs: NSRange, at origin: NSPoint) {
        guard !reveals.isEmpty else { super.drawGlyphs(forGlyphRange: glyphs, at: origin); return }
        let now = ProcessInfo.processInfo.systemUptime
        var cursor = glyphs.location
        for reveal in reveals where NSMaxRange(reveal.range) <= (textStorage?.length ?? 0) {
            let range = NSIntersectionRange(glyphs, glyphRange(forCharacterRange: reveal.range, actualCharacterRange: nil))
            let start = max(cursor, range.location)
            guard NSMaxRange(range) > start else { continue }
            if start > cursor { super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: start - cursor), at: origin) }
            NSGraphicsContext.saveGraphicsState()
            let progress = min(1, max(0, (now - reveal.started) / duration))
            NSGraphicsContext.current?.cgContext.setAlpha(0.72 + 0.28 * (1 - pow(1 - progress, 2)))
            super.drawGlyphs(forGlyphRange: NSRange(location: start, length: NSMaxRange(range) - start), at: origin)
            NSGraphicsContext.restoreGraphicsState()
            cursor = NSMaxRange(range)
        }
        if cursor < NSMaxRange(glyphs) {
            super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: NSMaxRange(glyphs) - cursor), at: origin)
        }
    }
}

@MainActor
final class MarkdownSelectionTextView: NSTextView, NSTextViewDelegate {
    struct ListMarker {
        var characterIndex: Int
        var text: String
        var indent: CGFloat
        var font: NSFont
    }
    struct CodeBlock {
        var range: NSRange
        var source: String
        var indent: CGFloat
    }
    struct QuoteBlock {
        var range: NSRange
        var indent: CGFloat
    }
    private var signature: Int?
    private var renderedText: NSAttributedString?
    private(set) var codeBlocks: [CodeBlock] = []
    private(set) var listMarkers: [ListMarker] = []
    private(set) var quoteBlocks: [QuoteBlock] = []
    private var inlineCodeRanges: [NSRange] = []
    private var clipboardBlocks: [MarkdownClipboardBlock] = []
    private var copyButtons: [NSButton] = []

    init() {
        let storage = NSTextStorage()
        let layout = MarkdownRevealLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        textContainerInset = .zero
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = false
        delegate = self
        linkTextAttributes = [.foregroundColor: NSColor.labelColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        setAccessibilityLabel("Assistant response text")
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }
    override func menu(for event: NSEvent) -> NSMenu? { TextContextMenu.make(for: self) }

    func install(rows: [MarkdownLayoutRow], fontSize: CGFloat, highlights: [String], dark: Bool,
                 isStreaming: Bool = false, reduceMotion: Bool = false) {
        let reveal = layoutManager as? MarkdownRevealLayoutManager
        if !isStreaming || reduceMotion { reveal?.finishReveals() }
        var hasher = Hasher()
        rows.forEach { hasher.combine($0.revision) }
        hasher.combine(fontSize); hasher.combine(highlights); hasher.combine(dark); hasher.combine(isStreaming)
        let next = hasher.finalize()
        guard signature != next else { return }
        signature = next
        let selections = selectedRanges.compactMap { value -> (NSRange, String)? in
            let range = value.rangeValue
            guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return nil }
            return (range, (string as NSString).substring(with: range))
        }
        let result = MarkdownNativeAttributedDocument.render(rows, fontSize: fontSize, highlights: highlights, dark: dark, isStreaming: isStreaming)
        // Each rendered paragraph ends in a structural newline. Appended words
        // appear before that newline, not after the old attributed string.
        let previous = string.hasSuffix("\n") ? String(string.dropLast()) : string
        if let textStorage { Self.updateText(textStorage, previous: renderedText, with: result.text) }
        renderedText = result.text
        if isStreaming && !reduceMotion && !previous.isEmpty && result.text.string.hasPrefix(previous) {
            let start = (previous as NSString).length
            let end = result.text.length - (result.text.string.hasSuffix("\n") ? 1 : 0)
            reveal?.reveal(NSRange(location: start, length: max(0, end - start)))
        } else if !result.text.string.hasPrefix(previous) {
            reveal?.finishReveals()
        }
        codeBlocks = result.codeBlocks
        listMarkers = result.listMarkers
        quoteBlocks = result.quoteBlocks
        clipboardBlocks = result.clipboardBlocks
        inlineCodeRanges.removeAll(keepingCapacity: true)
        result.text.enumerateAttribute(MarkdownNativeAttributedDocument.inlineCodeKey,
                                       in: NSRange(location: 0, length: result.text.length)) { value, range, _ in
            if value != nil { inlineCodeRanges.append(range) }
        }
        let retained = selections.compactMap { range, original -> NSValue? in
            let text = string as NSString
            if NSMaxRange(range) <= text.length, text.substring(with: range) == original {
                return NSValue(range: range)
            }
            // Formatting can consume literal Markdown delimiters before the
            // selected words. Preserve the closest identical passage.
            var nearest: NSRange?
            var cursor = 0
            while cursor < text.length {
                let match = text.range(of: original, options: .literal,
                                       range: NSRange(location: cursor, length: text.length - cursor))
                guard match.location != NSNotFound else { break }
                if nearest == nil || abs(match.location - range.location) < abs(nearest!.location - range.location) {
                    nearest = match
                }
                cursor = NSMaxRange(match)
            }
            return nearest.map { NSValue(range: $0) }
        }
        if !retained.isEmpty { selectedRanges = retained }
        while copyButtons.count > codeBlocks.count { copyButtons.removeLast().removeFromSuperview() }
        while copyButtons.count < codeBlocks.count {
            let button = NSButton(title: "Copy code", target: self, action: #selector(copyCode(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .secondaryLabelColor
            button.setAccessibilityLabel("Copy code")
            addSubview(button)
            copyButtons.append(button)
        }
        for index in copyButtons.indices { copyButtons[index].tag = index }
        needsLayout = true
        needsDisplay = true
    }

    /// Leave the unchanged prefix in TextKit, including its attributes and
    /// selection. A final streaming flag must not replace identical text.
    private static func updateText(_ storage: NSTextStorage, previous: NSAttributedString?, with text: NSAttributedString) {
        // TextKit substitutes fallback fonts for emoji. Compare our previous
        // document, not those platform substitutions, to find the unchanged
        // prefix and avoid rewriting a completed emoji on every later token.
        let baseline = previous ?? storage
        guard !baseline.isEqual(to: text) else { return }
        let old = baseline.string as NSString
        let next = text.string as NSString
        var prefix = old.commonPrefix(with: text.string, options: .literal).utf16.count
        if prefix < next.length { prefix = min(prefix, next.rangeOfComposedCharacterSequence(at: prefix).location) }
        if prefix < old.length { prefix = min(prefix, old.rangeOfComposedCharacterSequence(at: prefix).location) }
        var cursor = 0
        while cursor < prefix {
            var oldRange = NSRange(), newRange = NSRange()
            let oldAttributes = baseline.attributes(at: cursor, longestEffectiveRange: &oldRange,
                                                   in: NSRange(location: 0, length: prefix))
            let newAttributes = text.attributes(at: cursor, longestEffectiveRange: &newRange,
                                                in: NSRange(location: 0, length: prefix))
            if !NSDictionary(dictionary: oldAttributes).isEqual(to: newAttributes) { prefix = cursor; break }
            cursor = min(NSMaxRange(oldRange), NSMaxRange(newRange))
        }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: prefix, length: storage.length - prefix),
                                  with: text.attributedSubstring(from: NSRange(location: prefix, length: text.length - prefix)))
        storage.endEditing()
    }

    func measuredSize(width: CGFloat) -> NSSize {
        let width = max(1, width.isFinite ? width : 760)
        guard let container = textContainer, let manager = layoutManager else { return NSSize(width: width, height: 1) }
        if container.containerSize.width != width {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        manager.ensureLayout(for: container)
        var bottom = manager.usedRect(for: container).maxY
        // Paragraph terminators are necessary for tables and continuous
        // selection. TextKit also reserves a final empty insertion line after
        // them, which a read-only response does not need to display.
        if manager.extraLineFragmentTextContainer === container,
           manager.extraLineFragmentRect.height > 0 {
            bottom = min(bottom, manager.extraLineFragmentRect.minY)
        }
        // Code backgrounds extend below their final glyph. Keep that padding
        // without retaining an entire empty text line below every response.
        for block in codeBlocks {
            bottom = max(bottom, blockRect(block).maxY)
        }
        return NSSize(width: width, height: ceil(max(1, bottom)) + 2)
    }

    override func layout() {
        super.layout()
        for (index, block) in codeBlocks.enumerated() where copyButtons.indices.contains(index) {
            let rect = blockRect(block)
            copyButtons[index].frame = NSRect(x: max(rect.minX + 40, rect.maxX - 88), y: rect.minY + 5, width: 80, height: 20)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for block in codeBlocks {
            let rect = blockRect(block)
            guard rect.intersects(dirtyRect) else { continue }
            NSColor(DesignTokens.surface).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            border.lineWidth = 0.5
            border.stroke()
        }
        if let manager = layoutManager, let container = textContainer {
            for quote in quoteBlocks {
                let glyphs = manager.glyphRange(forCharacterRange: quote.range, actualCharacterRange: nil)
                let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                guard rect.intersects(dirtyRect) else { continue }
                NSColor.separatorColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: quote.indent, y: rect.minY, width: 2, height: rect.height),
                             xRadius: 1, yRadius: 1).fill()
            }
            for range in inlineCodeRanges {
                let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                manager.enumerateEnclosingRects(forGlyphRange: glyphs,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                    guard rect.intersects(dirtyRect) else { return }
                    NSColor.labelColor.withAlphaComponent(0.055).setFill()
                    NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: 0.5), xRadius: 3, yRadius: 3).fill()
                }
            }
            for marker in listMarkers where marker.characterIndex < (string as NSString).length {
                let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: marker.characterIndex, length: 1), actualCharacterRange: nil)
                let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                guard rect.intersects(dirtyRect) else { continue }
                let attributes: [NSAttributedString.Key: Any] = [.font: marker.font, .foregroundColor: NSColor.labelColor]
                let size = (marker.text as NSString).size(withAttributes: attributes)
                (marker.text as NSString).draw(at: NSPoint(x: max(0, marker.indent - size.width - 10), y: rect.minY), withAttributes: attributes)
            }
        }
        super.draw(dirtyRect)
    }

    private func blockRect(_ block: CodeBlock) -> NSRect {
        guard let manager = layoutManager, let container = textContainer else { return .zero }
        let glyphs = manager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        return NSRect(x: block.indent, y: max(0, rect.minY - 6), width: max(0, bounds.width - block.indent),
                      height: rect.height + 14)
    }

    @objc private func copyCode(_ sender: NSButton) {
        guard codeBlocks.indices.contains(sender.tag) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codeBlocks[sender.tag].source, forType: .string)
    }

    /// AppKit's rich-text export uses legacy pasteboard types on some macOS
    /// versions. Always supply public UTF-8 text as well. Decorative list markers
    /// behave like HTML ::marker; Copy response still exports the source Markdown.
    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .html {
            guard let textStorage, let html = MarkdownClipboard.html(
                text: textStorage, blocks: clipboardBlocks, ranges: selectedRanges.map(\.rangeValue)) else { return false }
            return pasteboard.setString(html, forType: .html)
        }
        guard type == .string else { return super.writeSelection(to: pasteboard, type: type) }
        let source = string as NSString
        let selections = selectedRanges.compactMap { value -> String? in
            let range = value.rangeValue
            guard range.length > 0, range.location != NSNotFound, NSMaxRange(range) <= source.length else { return nil }
            return source.substring(with: range)
        }
        guard !selections.isEmpty else { return false }
        return pasteboard.setString(selections.joined(separator: "\n"), forType: .string)
    }

    override func copy(_ sender: Any?) {
        guard selectedRanges.contains(where: { $0.rangeValue.length > 0 }) else { return }
        let pasteboard = NSPasteboard.general
        let html = textStorage.flatMap {
            MarkdownClipboard.html(text: $0, blocks: clipboardBlocks, ranges: selectedRanges.map(\.rangeValue))
        }
        pasteboard.clearContents()
        // Rich destinations read semantic HTML; plain editors still receive the
        // exact selected text. AppKit RTF omits our decorative list semantics.
        pasteboard.declareTypes(html == nil ? [.string] : [.html, .string], owner: nil)
        if let html { pasteboard.setString(html, forType: .html) }
        _ = writeSelection(to: pasteboard, type: .string)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url, MarkdownLinkPolicy.allowsExternalLink(url) { NSWorkspace.shared.open(url) }
        return true
    }
}

@MainActor
enum MarkdownNativeAttributedDocument {
    static let inlineCodeKey = NSAttributedString.Key("BedrockInlineCode")
    struct Result {
        let text: NSAttributedString
        let codeBlocks: [MarkdownSelectionTextView.CodeBlock]
        let listMarkers: [MarkdownSelectionTextView.ListMarker]
        let quoteBlocks: [MarkdownSelectionTextView.QuoteBlock]
        let clipboardBlocks: [MarkdownClipboardBlock]
    }

    static func render(_ rows: [MarkdownLayoutRow], fontSize: CGFloat, highlights: [String], dark: Bool, isStreaming: Bool) -> Result {
        let output = NSMutableAttributedString(string: "")
        var codeBlocks: [MarkdownSelectionTextView.CodeBlock] = []
        var listMarkers: [MarkdownSelectionTextView.ListMarker] = []
        var quoteBlocks: [MarkdownSelectionTextView.QuoteBlock] = []
        var clipboardBlocks: [MarkdownClipboardBlock] = []
        for row in rows {
            let start = output.length
            var clipboardKind = MarkdownClipboardBlock.Kind.text(tag: "p")
            defer {
                if output.length > start {
                    clipboardBlocks.append(.init(
                        range: NSRange(location: start, length: output.length - start),
                        containers: row.clipboardContainers, kind: clipboardKind))
                    for indent in row.quoteIndents {
                        if let index = quoteBlocks.lastIndex(where: { $0.indent == indent }),
                           NSMaxRange(quoteBlocks[index].range) == start {
                            quoteBlocks[index].range.length = output.length - quoteBlocks[index].range.location
                        } else {
                            quoteBlocks.append(.init(range: NSRange(location: start, length: output.length - start), indent: indent))
                        }
                    }
                }
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            style.paragraphSpacingBefore = row.spacing
            style.headIndent = row.indent
            style.firstLineHeadIndent = row.indent
            style.tabStops = [NSTextTab(textAlignment: .left, location: row.indent)]
            var body: NSMutableAttributedString
            var size = fontSize
            switch row.block {
            case .paragraph(let text):
                body = inline(text, size: size)
            case .heading(let level, let text):
                clipboardKind = .text(tag: "h\(min(6, max(1, level)))")
                size += CGFloat(max(0, 5 - level)) * 2
                body = inline(text, size: size, weight: .semibold)
                style.paragraphSpacingBefore += 4
            case .fencedCode(let language, let lines):
                clipboardKind = .code(appendCode(lines.joined(), language: language ?? "Code", row: row, to: output,
                           codeBlocks: &codeBlocks, size: fontSize, dark: dark, isStreaming: isStreaming))
                continue
            case .indentedCode(let lines):
                clipboardKind = .code(appendCode(lines.joined(), language: "Code", row: row, to: output,
                           codeBlocks: &codeBlocks, size: fontSize, dark: dark, isStreaming: isStreaming))
                continue
            case .table(let header, let alignments, let cells):
                let table = NSTextTable()
                table.numberOfColumns = max(1, header.count)
                table.collapsesBorders = true
                table.setContentWidth(100, type: .percentageValueType)
                table.setWidth(row.spacing, type: .absoluteValueType, for: .margin, edge: .minY)
                var clipboardCells: [MarkdownClipboardBlock.Cell] = []
                for (r, values) in ([header] + cells).enumerated() {
                    for (c, value) in values.enumerated() {
                        let cellStart = output.length
                        let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                        block.setContentWidth(100 / CGFloat(table.numberOfColumns), type: .percentageValueType)
                        block.setWidth(8, type: .absoluteValueType, for: .padding)
                        block.setWidth(0.5, type: .absoluteValueType, for: .border)
                        block.setBorderColor(.separatorColor)
                        if r == 0 { block.backgroundColor = NSColor(DesignTokens.surface) }
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.textBlocks = [block]
                        paragraph.lineSpacing = 3
                        if c < alignments.count { paragraph.alignment = alignments[c] == .right ? .right : alignments[c] == .center ? .center : .left }
                        let cell = inline(value, size: max(12, fontSize - 1), weight: r == 0 ? .semibold : .regular)
                        cell.append(NSAttributedString(string: "\n"))
                        cell.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: cell.length))
                        output.append(cell)
                        clipboardCells.append(.init(range: NSRange(location: cellStart, length: cell.length),
                                                    row: r, isHeader: r == 0))
                    }
                }
                clipboardKind = .table(clipboardCells)
                continue
            case .thematicBreak:
                clipboardKind = .rule
                body = NSMutableAttributedString(string: "────────", attributes: [.foregroundColor: NSColor.separatorColor])
            default:
                body = NSMutableAttributedString(string: row.block.string)
            }
            if let marker = row.marker {
                listMarkers.append(.init(characterIndex: output.length, text: marker,
                                         indent: row.indent, font: .systemFont(ofSize: size)))
            }
            body.append(NSAttributedString(string: "\n"))
            let range = NSRange(location: 0, length: body.length)
            body.addAttribute(.paragraphStyle, value: style, range: range)
            body.addAttribute(.font, value: NSFont.systemFont(ofSize: size), range: NSRange(location: body.length - 1, length: 1))
            output.append(body)
        }
        let text = output.string as NSString
        for term in highlights where !term.isEmpty {
            var remaining = NSRange(location: 0, length: text.length)
            while remaining.length > 0 {
                let match = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: remaining)
                guard match.location != NSNotFound, match.length > 0 else { break }
                output.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: match)
                remaining = NSRange(location: NSMaxRange(match), length: text.length - NSMaxRange(match))
            }
        }
        return Result(text: output, codeBlocks: codeBlocks, listMarkers: listMarkers,
                      quoteBlocks: quoteBlocks, clipboardBlocks: clipboardBlocks)
    }

    private static func inline(_ text: MarkdownKit.Text, size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSMutableAttributedString {
        let output = NSMutableAttributedString(string: "")
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = italic ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) : base
        for fragment in text {
            let part: NSMutableAttributedString
            switch fragment {
            case .emph(let children): part = inline(children, size: size, weight: weight, italic: true)
            case .strong(let children): part = inline(children, size: size, weight: .semibold, italic: italic)
            case .link(let children, let destination, _):
                part = inline(children, size: size, weight: weight, italic: italic)
                if let url = destination.flatMap(URL.init(string:)), MarkdownLinkPolicy.allowsExternalLink(url) {
                    part.addAttributes([.link: url, .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: 0, length: part.length))
                }
            case .autolink(let type, let destination):
                part = NSMutableAttributedString(string: String(destination), attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                if let url = URL(string: type == .email ? "mailto:\(destination)" : String(destination)), MarkdownLinkPolicy.allowsExternalLink(url) {
                    part.addAttributes([.link: url, .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: 0, length: part.length))
                }
            case .code(let text):
                part = NSMutableAttributedString(string: String(text), attributes: [.font: NSFont.monospacedSystemFont(ofSize: max(11, size - 1), weight: .regular),
                                                                                   .foregroundColor: NSColor.labelColor, inlineCodeKey: true])
            case .softLineBreak: part = NSMutableAttributedString(string: " ", attributes: [.font: font])
            case .hardLineBreak: part = NSMutableAttributedString(string: "\n", attributes: [.font: font])
            default: part = NSMutableAttributedString(string: fragment.string, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            }
            let range = NSRange(location: 0, length: part.length)
            if weight.rawValue >= NSFont.Weight.semibold.rawValue {
                part.addAttribute(MarkdownClipboard.strongKey, value: true, range: range)
            }
            if italic { part.addAttribute(MarkdownClipboard.emphasisKey, value: true, range: range) }
            output.append(part)
        }
        return output
    }

    private static func appendCode(_ code: String, language: String, row: MarkdownLayoutRow, to output: NSMutableAttributedString,
                                   codeBlocks: inout [MarkdownSelectionTextView.CodeBlock], size: CGFloat, dark: Bool, isStreaming: Bool) -> NSRange {
        let start = output.length
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.firstLineHeadIndent = row.indent + 12
        headingStyle.headIndent = row.indent + 12
        headingStyle.paragraphSpacingBefore = row.spacing + 8
        headingStyle.paragraphSpacing = 10
        output.append(NSAttributedString(string: language + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: headingStyle
        ]))
        let codeStart = output.length
        let body = NSMutableAttributedString(attributedString: isStreaming ? NSAttributedString(string: code) :
            NSAttributedString(CodeHighlightCache.shared.text(code, language: language, dark: dark)))
        if !body.string.hasSuffix("\n") { body.append(NSAttributedString(string: "\n")) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = row.indent + 12
        paragraph.firstLineHeadIndent = row.indent + 12
        paragraph.tailIndent = -12
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 6
        body.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: max(11, size - 1), weight: .regular),
                            .paragraphStyle: paragraph], range: NSRange(location: 0, length: body.length))
        body.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: body.length)) { value, range, _ in
            if value == nil { body.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        output.append(body)
        codeBlocks.append(.init(range: NSRange(location: start, length: output.length - start), source: code, indent: row.indent))
        return NSRange(location: codeStart, length: output.length - codeStart)
    }
}
