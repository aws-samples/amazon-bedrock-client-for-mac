import AppKit
import SwiftUI
import AVKit

struct GeneratedVideoView: View {
    let videoUrl: URL
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                colorScheme == .dark ?
                                Color.white.opacity(0.15) :
                                    Color.primary.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 640)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading video...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    )
            }

            // Video controls
            HStack(spacing: 12) {
                Button(action: { openInFinder() }) {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Button(action: { saveVideoToFile() }) {
                    Label("Save Video...", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            .foregroundColor(.secondary)
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadVideo() {
        guard FileManager.default.fileExists(atPath: videoUrl.path) else { return }
        player = AVPlayer(url: videoUrl)
    }

    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([videoUrl])
    }

    private func saveVideoToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = "generated-video-\(Date().timeIntervalSince1970).mp4"

        savePanel.begin { response in
            if response == .OK, let destinationUrl = savePanel.url {
                try? FileManager.default.copyItem(at: videoUrl, to: destinationUrl)
            }
        }
    }
}
