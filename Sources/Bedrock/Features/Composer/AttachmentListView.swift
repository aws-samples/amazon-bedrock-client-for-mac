import SwiftUI
import Combine
import UniformTypeIdentifiers

struct PasteLoadingView: View {
    var body: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Preparing attachments…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 34)
        .padding(.bottom, 8)
        .transition(.opacity)
    }
}

struct ImageAttachment: Identifiable {
    var id = UUID()
    let image: NSImage
    var fileExtension: String
    var filename: String
}

struct AttachmentListView: View {
    @Binding var attachments: [ImageAttachment]
    @Binding var documentAttachments: [DocumentAttachment]
    @ObservedObject var sharedMediaDataSource: AttachmentStore
    @Binding var selectedImageIndex: Int?
    @Binding var showImagePreview: Bool
    var onRemoveAttachment: (UUID) -> Void
    var onRemoveDocumentAttachment: (UUID) -> Void
    var onRemoveAllAttachments: () -> Void

    @State private var documentToPreview: DocumentAttachment? = nil  // Use for sheet(item:)
    @State private var isSavingImages = false
    @State private var imageExportTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                let totalAttachments = attachments.count + documentAttachments.count

                Text("Attachments (\(totalAttachments))")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                if isSavingImages {
                    ProgressView().controlSize(.small)
                    Text("Saving images…").font(.system(size: 12)).foregroundStyle(.secondary)
                }

                if totalAttachments > 1 {
                    Button(action: onRemoveAllAttachments) {
                        Text("Clear all")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Remove all attachments from this draft")
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 8)

            // Combined attachment list (images + documents)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Images
                    ForEach(attachments) { attachment in
                        MediaAttachmentView(
                            attachmentType: .image(attachment.image),
                            filename: attachment.filename,
                            fileExtension: attachment.fileExtension,
                            onDelete: {
                                onRemoveAttachment(attachment.id)
                            },
                            onClick: {
                                if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                    selectedImageIndex = index
                                    showImagePreview = true
                                }
                            }
                        )
                    }

                    // Documents
                    ForEach(documentAttachments) { document in
                        if let preview = document.textPreview {
                            PastedTextAttachmentView(
                                preview: preview,
                                onDelete: {
                                    onRemoveDocumentAttachment(document.id)
                                },
                                onClick: {
                                    // Use sheet(item:) pattern - set the document directly
                                    documentToPreview = document
                                }
                            )
                        } else {
                            MediaAttachmentView(
                                attachmentType: .document(document.fileExtension),
                                filename: document.filename,
                                fileExtension: document.fileExtension,
                                onDelete: {
                                    onRemoveDocumentAttachment(document.id)
                                },
                                onClick: {
                                    // Use sheet(item:) pattern - set the document directly
                                    documentToPreview = document
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 8)
            }
            .frame(height: 90)
            .contextMenu {
                Button(action: onRemoveAllAttachments) {
                    Label("Delete All Attachments", systemImage: "trash")
                }

                if !attachments.isEmpty {
                    Button(action: {
                        saveAllImages()
                    }) {
                        Label("Save All Images", systemImage: "folder")
                    }
                    .disabled(isSavingImages)
                }
            }
        }
        .onDisappear { imageExportTask?.cancel() }
        .sheet(item: $documentToPreview) { doc in
            if let text = doc.textPreview {
                PastedTextEditor(filename: doc.filename, initialText: text) { value in
                    sharedMediaDataSource.updatePastedText(id: doc.id, text: value)
                    if let index = documentAttachments.firstIndex(where: { $0.id == doc.id }) {
                        documentAttachments[index] = DocumentAttachment(id: doc.id, data: Data(value.utf8), fileExtension: "txt", filename: doc.filename, textPreview: value)
                    }
                }
            } else {
                DocumentPreviewModal(
                    documentData: doc.data,
                    filename: doc.filename,
                    fileExtension: doc.fileExtension,
                    isPresented: Binding(
                        get: { documentToPreview != nil },
                        set: { if !$0 { documentToPreview = nil } }
                    )
                )
            }
        }
    }

    private func saveAllImages() {
        guard !isSavingImages else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder to save all images"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Snapshot before leaving the main actor; editing the draft
                // while saving must not change which images are exported.
                let items = sharedMediaDataSource.images.enumerated().map { index, image in
                    let bytes = sharedMediaDataSource.imageEncodedData.indices.contains(index)
                        ? sharedMediaDataSource.imageEncodedData[index] : nil
                    let filename = sharedMediaDataSource.filenames.indices.contains(index)
                        ? sharedMediaDataSource.filenames[index] : "Image"
                    return ImageExportItem(filename: filename,
                        source: bytes.map(ImagePreviewSource.encoded) ?? .legacy(ImagePreviewBitmap(image)))
                }
                isSavingImages = true
                imageExportTask = Task {
                    defer { isSavingImages = false; imageExportTask = nil }
                    do {
                        let result = try await AttachmentExporter.shared.save(items, to: url)
                        if !result.failures.isEmpty {
                            AppStore.shared.errorMessage = "Saved \(result.files.count) of \(items.count) images.\n"
                                + result.failures.joined(separator: "\n")
                        }
                    } catch is CancellationError {
                    } catch {
                        AppStore.shared.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

struct MediaAttachmentView: View {
    enum AttachmentType {
        case image(NSImage)
        case document(String) // Document extension
    }

    var attachmentType: AttachmentType
    var filename: String
    var fileExtension: String
    var onDelete: () -> Void
    var onClick: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail or icon
            Group {
                switch attachmentType {
                case .image(let image):
                    Button(action: { onClick?() }) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(6)
                            .clipped()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(filename)
                    .accessibilityLabel("Open attachment: \(filename)")

                case .document(let ext):
                    Button(action: { onClick?() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(documentColor(for: ext).opacity(0.15))
                                .frame(width: 60, height: 60)

                            Image(systemName: documentIcon(for: ext))
                                .font(.system(size: 24))
                                .foregroundColor(documentColor(for: ext))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(filename)
                    .accessibilityLabel("Open attachment: \(filename)")
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DesignTokens.border, lineWidth: 1)
            )
            .overlay(
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ?
                                  Color(white: 0.2).opacity(0.8) :
                                  Color.white.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)

                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove \(filename)")
                .accessibilityLabel("Remove attachment: \(filename)"),
                alignment: .topTrailing
            )

            Text(filename.count > 10 ? String(filename.prefix(7)) + "..." : filename)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 60)
                .help(filename)
        }
        .frame(width: 70, height: 80)
    }

    // Get icon based on file extension
    private func documentIcon(for extension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "html": return "globe"
        default: return "doc.fill"
        }
    }

    // Get color based on file extension
    private func documentColor(for extension: String) -> Color {
        switch fileExtension.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "txt", "md": return .gray
        case "html": return .orange
        default: return .gray
        }
    }
}

// MARK: - Pasted Text Attachment View (Claude Desktop style)
struct PastedTextAttachmentView: View {
    let preview: String
    var onDelete: () -> Void
    var onClick: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var displayPreview: String {
        // First truncate to avoid processing large text
        let truncated = String(preview.prefix(100))
        // Clean up newlines without regex
        let cleaned = truncated
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 60 {
            return String(cleaned.prefix(57)) + "..."
        }
        return cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Text preview area
            Button(action: { onClick?() }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayPreview)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(width: 80, height: 50, alignment: .topLeading)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Inspect and edit pasted text")
            .accessibilityLabel("Edit pasted text")
            .overlay(
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ?
                                  Color(white: 0.2).opacity(0.8) :
                                  Color.white.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)

                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .contentShape(Rectangle().size(width: 28, height: 28))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove pasted text")
                .accessibilityLabel("Remove pasted text")
                .opacity(isHovered ? 1 : 0.55),
                alignment: .topTrailing
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }

            // "PASTED" label
            Text("PASTED")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                )
        }
        .frame(width: 92, height: 80)
    }
}
