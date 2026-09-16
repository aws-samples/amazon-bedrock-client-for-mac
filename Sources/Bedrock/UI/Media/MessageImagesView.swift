import AppKit
import SwiftUI

struct MessageImageView: View {
    let imageData: String
    let size: CGFloat
    let onTap: () -> Void
    var isGeneratedImage: Bool = false

    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var loadedImage: PreparedImagePreview?
    @State private var isLoading = true

    private var displaySize: CGFloat {
        isGeneratedImage ? max(size, 400) : size
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if let image = loadedImage {
                    Image(decorative: image.preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: displaySize, maxHeight: displaySize)
                        .clipShape(RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10)
                                .stroke(
                                    colorScheme == .dark ?
                                    Color.white.opacity(0.15) :
                                        Color.primary.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(isGeneratedImage ? 0.15 : 0.05),
                            radius: isGeneratedImage ? 8 : 2,
                            x: 0,
                            y: isGeneratedImage ? 4 : 1
                        )
                } else if isLoading {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .frame(width: displaySize * 0.8, height: displaySize * 0.6)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                } else {
                    // Error state
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .frame(width: size, height: size / 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(isGeneratedImage ? "Open generated image" : "Open image attachment")
        .task(id: imageData) { await loadImageAsync() }
        .contextMenu {
            Button(action: copyImageToClipboard) {
                Label("Copy Image", systemImage: "doc.on.doc")
            }

            Button(action: saveImageToFile) {
                Label("Save Image...", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func loadImageAsync() async {
        isLoading = true
        let directory = URL(fileURLWithPath: PreferencesStore.shared.defaultDirectory).appendingPathComponent("generated_images")
        do {
            let image = try await ImagePreviewLoader.shared.load(.stored(imageData, directory: directory),
                                                               maximumPixelSize: isGeneratedImage ? 1_024 : 480)
            try Task.checkCancellation()
            loadedImage = image
            isLoading = false
        } catch is CancellationError {
        } catch { isLoading = false }
    }

    private func copyImageToClipboard() {
        guard let image = loadedImage else { return }
        Task {
            do {
                let data = try await ImagePreviewLoader.shared.export(image, as: .png)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
            } catch { AppStore.shared.errorMessage = error.localizedDescription }
        }
    }

    private func saveImageToFile() {
        guard let image = loadedImage else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "generated-image.png"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                Task {
                    do { try await ImagePreviewLoader.shared.save(image, to: url) }
                    catch { AppStore.shared.errorMessage = error.localizedDescription }
                }
            }
        }
    }
}

// MARK: - GeneratedImagesView (for AI-generated images)
struct GeneratedImagesView: View {
    let imageBase64Strings: [String]
    let onTapImage: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Display images in a responsive grid
            ForEach(Array(imageBase64Strings.enumerated()), id: \.offset) { _, imageData in
                MessageImageView(
                    imageData: imageData,
                    size: 512,
                    onTap: { onTapImage(imageData) },
                    isGeneratedImage: true
                )
            }
        }
    }
}
