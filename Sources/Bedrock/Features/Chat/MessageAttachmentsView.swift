import AppKit
import SwiftUI

struct MessageAttachmentsView: View {
    let imageBase64Strings: [String]?
    let imageSize: CGFloat
    let onTapImage: (String) -> Void
    var onSelectDocument: (Data, String, String) -> Void
    let documentBase64Strings: [String]?
    let documentFormats: [String]?
    let documentNames: [String]?
    let pastedTexts: [PastedTextInfo]?
    let alignment: HorizontalAlignment

    var body: some View {
        FlowLayout(alignment: alignment) {
            ForEach(pastedTexts ?? []) { text in
                MessageDocumentButton(name: text.filename, format: "txt", content: .text(text.content),
                                      onOpen: onSelectDocument)
            }
            if let contents = documentBase64Strings, let formats = documentFormats, let names = documentNames {
                ForEach(0..<min(contents.count, min(formats.count, names.count)), id: \.self) { index in
                    MessageDocumentButton(name: names[index], format: formats[index], content: .encoded(contents[index]),
                                          onOpen: onSelectDocument)
                }
            }
            // Index identity preserves two identical attached images.
            ForEach(Array((imageBase64Strings ?? []).enumerated()), id: \.offset) { _, image in
                MessageImageView(imageData: image, size: imageSize) { onTapImage(image) }
            }
        }
    }
}

private enum MessageDocumentContent: Sendable {
    case text(String), encoded(String)

    func decode() throws -> Data {
        let maximumBytes = 64 * 1_024 * 1_024
        try Task.checkCancellation()
        switch self {
        case .text(let text):
            guard text.utf8.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
            return Data(text.utf8)
        case .encoded(let value):
            guard value.utf8.count <= maximumBytes * 4 / 3 + 4 else { throw LocalOperationError.tooLarge(maximumBytes) }
            guard let data = Data(base64Encoded: value), data.count <= maximumBytes else {
                throw LocalOperationError.invalid("The saved document is damaged or too large to preview.")
            }
            return data
        }
    }
}

private struct MessageDocumentButton: View {
    private enum Action: Hashable { case open, copy }
    let name: String
    let format: String
    let content: MessageDocumentContent
    let onOpen: (Data, String, String) -> Void
    @State private var action: Action?

    private var canCopy: Bool {
        if case .text = content { return true }
        return ["txt", "md", "csv", "html", "json", "yaml", "yml", "xml", "swift", "py", "js", "ts", "log"]
            .contains(format.lowercased())
    }

    private var symbol: String {
        switch format.lowercased() {
        case "csv", "xls", "xlsx": "tablecells"
        case "pdf": "doc.richtext"
        case "html": "chevron.left.forwardslash.chevron.right"
        default: "doc.text"
        }
    }

    var body: some View {
        Button { action = .open } label: {
            HStack(spacing: 9) {
                Group {
                    if action != nil { ProgressView().controlSize(.small) }
                    else { Image(systemName: symbol).font(.system(size: 18)) }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(format.uppercased()).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 130, maxWidth: 210, alignment: .leading)
            .padding(10)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.09), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(action != nil)
        .help("Open \(name)")
        .accessibilityLabel("Open attachment \(name)")
        .contextMenu {
            Button("Open", systemImage: "doc.text") { action = .open }
            if canCopy {
                Button("Copy Content", systemImage: "doc.on.doc") { action = .copy }
            }
        }
        .task(id: action) {
            guard let requestedAction = action else { return }
            let source = content
            let worker = Task.detached(priority: .userInitiated) {
                let data = try source.decode()
                let text = requestedAction == .copy ? String(data: data, encoding: .utf8) : nil
                if requestedAction == .copy, text == nil {
                    throw LocalOperationError.invalid("This document cannot be copied as plain text.")
                }
                return (data, text)
            }
            do {
                let (data, text) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                if let text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } else {
                    onOpen(data, format, name)
                }
            } catch is CancellationError {
            } catch { AppStore.shared.errorMessage = error.localizedDescription }
            action = nil
        }
    }
}
