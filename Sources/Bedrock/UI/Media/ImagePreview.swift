import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImagePreviewModal: View {
    let source: ImagePreviewSource
    let filename: String
    @Binding var isPresented: Bool
    @State private var image: PreparedImagePreview?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var actionTask: Task<Void, Never>?
    @State private var isWorking = false
    @State private var copied = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var previewSize: CGSize {
        let available = NSApp.keyWindow?.screen?.visibleFrame.size ?? CGSize(width: 1_024, height: 768)
        return CGSize(width: min(840, available.width - 64), height: min(640, available.height - 80))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                DesignTokens.canvas
                if let image {
                    CheckerboardPattern(colorScheme: colorScheme)
                        .opacity(colorScheme == .dark ? 0.10 : 0.06)
                    Image(decorative: image.preview, scale: 1)
                        .resizable().interpolation(.high).scaledToFit()
                        .padding(20)
                        .scaleEffect(scale).offset(offset)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Image preview")
                } else if let loadError {
                    EmptyStateView(symbol: "photo", title: "Image could not be opened", detail: loadError)
                } else {
                    ProgressView("Opening image…").controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            // The zoomed image can extend beyond the viewport. Clipping pixels
            // does not clip SwiftUI hit testing: keep gestures on the fixed
            // viewport so an enlarged image cannot cover Fit/Copy/Close.
            .gesture(DragGesture()
                .onChanged { value in
                    guard image != nil else { return }
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                }
                .onEnded { _ in lastOffset = offset })
            .simultaneousGesture(MagnificationGesture()
                .onChanged { if image != nil { scale = min(5, max(0.25, lastScale * $0)) } }
                .onEnded { _ in lastScale = scale })
            .onTapGesture(count: 2) { if image != nil { setZoom(scale == 1 ? 2 : 1) } }
            Divider()
            HStack(spacing: 8) {
                if let image {
                    Text("\(image.width) × \(image.height)")
                    Text("·")
                    Text(image.fileExtension.uppercased())
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(image.original.count), countStyle: .file))
                } else { Spacer() }
            }
            .font(DesignTokens.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).frame(height: 36)
        }
        // Bound the sheet itself, not an inner view beneath an unbounded
        // Color/GeometryReader. This avoids recursive sheet-size negotiation.
        .frame(width: previewSize.width, height: previewSize.height)
        .background(DesignTokens.canvas)
        .buttonStyle(AppButtonStyle())
        .task {
            do {
                let prepared = try await ImagePreviewLoader.shared.load(source)
                try Task.checkCancellation()
                image = prepared
            } catch is CancellationError {
            } catch { loadError = error.localizedDescription }
        }
        .onDisappear { actionTask?.cancel() }
        .onExitCommand { isPresented = false }
        .alert("Image export", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("imagePreview")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.secondary)
            Text(filename).font(DesignTokens.label).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            control("minus", title: "Zoom out") { setZoom(scale - 0.25) }.disabled(image == nil || scale <= 0.25)
            Text("\(Int(scale * 100))%").font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 40)
            control("plus", title: "Zoom in") { setZoom(scale + 0.25) }.disabled(image == nil || scale >= 5)
            control("arrow.counterclockwise", title: "Fit image") { setZoom(1) }.disabled(image == nil)
            Divider().frame(height: 18).padding(.horizontal, 4)
            if isWorking { ProgressView().controlSize(.mini).frame(width: 28) }
            control(copied ? "checkmark" : "doc.on.doc", title: copied ? "Image copied" : "Copy image", action: copy)
                .disabled(image == nil || isWorking)
            control("square.and.arrow.down", title: "Save image", action: save)
                .disabled(image == nil || isWorking)
            control("xmark", title: "Close image preview") { isPresented = false }
        }
        .padding(.horizontal, 14).frame(height: 52)
    }

    private func control(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular)).frame(width: 28, height: 28)
        }
        .buttonStyle(LiquidGlassToolbarButtonStyle()).help(title).accessibilityLabel(title)
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(reduceMotion ? nil : AppMotion.feedback) {
            scale = min(5, max(0.25, value))
            lastScale = scale
            if scale == 1 { offset = .zero; lastOffset = .zero }
        }
    }

    private func copy() {
        guard let image else { return }
        isWorking = true
        actionTask = Task {
            defer { isWorking = false }
            do {
                let bytes = try await ImagePreviewLoader.shared.export(image, as: .png)
                try Task.checkCancellation()
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setData(bytes, forType: .png) else {
                    throw LocalOperationError.invalid("The image could not be copied to the clipboard.")
                }
                copied = true
            } catch is CancellationError {
            } catch { actionError = error.localizedDescription }
        }
    }

    private func save() {
        guard let image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        let base = (filename as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + (image.type == UTType.jpeg.identifier ? ".jpg" : ".png")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isWorking = true
            actionTask = Task {
                defer { isWorking = false }
                do { try await ImagePreviewLoader.shared.save(image, to: url) }
                catch is CancellationError { }
                catch { actionError = error.localizedDescription }
            }
        }
    }
}

struct CheckerboardPattern: View {
    var colorScheme: ColorScheme = .dark
    var body: some View {
        Canvas { context, size in
            var pattern = Path()
            let step: CGFloat = 12
            for row in 0..<(Int(size.height / step) + 1) {
                for column in 0..<(Int(size.width / step) + 1) where (row + column).isMultiple(of: 2) {
                    pattern.addRect(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step))
                }
            }
            context.fill(pattern, with: .color(colorScheme == .dark ? .white : .black))
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}
