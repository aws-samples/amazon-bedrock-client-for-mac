//
//  ImagePreview.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/2/25.
//

import SwiftUI

/**
 * Modern modal view for displaying full-sized image previews.
 * Features smooth animations, gesture controls, and a clean UI.
 */
struct ImagePreviewModal: View {
    var image: NSImage
    var filename: String
    @Binding var isPresented: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isHoveringControls: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let cornerRadius: CGFloat = 16
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            
            // Main container
            VStack(spacing: 0) {
                headerBar
                imageContent
                footerBar
            }
            .frame(width: 900, height: 700)
            .background(containerBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        }
        .onAppear { resetView() }
    }
    
    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 12) {
            // File info
            HStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 4) {
                toolbarButton(icon: "arrow.counterclockwise", action: resetView, help: "Reset")
                toolbarButton(icon: "square.and.arrow.down", action: saveImage, help: "Save")
                toolbarButton(icon: "doc.on.doc", action: copyToClipboard, help: "Copy")
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 8)
                
                // Close button
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.5).background(.ultraThinMaterial))
    }
    
    // MARK: - Image Content
    private var imageContent: some View {
        GeometryReader { geo in
            ZStack {
                // Checkerboard pattern for transparency
                CheckerboardPattern()
                    .opacity(0.1)
                
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Footer
    private var footerBar: some View {
        HStack {
            // Format info
            Text(filename.components(separatedBy: ".").last?.uppercased() ?? "IMAGE")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            
            Spacer()
            
            // Zoom controls
            HStack(spacing: 12) {
                Button(action: { zoomOut() }) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(scale <= 1.0 ? .white.opacity(0.3) : .white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .disabled(scale <= 1.0)
                
                Text("\(Int(scale * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 50)
                
                Button(action: { zoomIn() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(scale >= 5.0 ? .white.opacity(0.3) : .white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .disabled(scale >= 5.0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5).background(.ultraThinMaterial))
    }
    
    // MARK: - Components
    @ViewBuilder
    private var containerBackground: some View {
        if colorScheme == .dark {
            Color(white: 0.1)
        } else {
            Color(white: 0.15)
        }
    }
    
    private func toolbarButton(icon: String, action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
    
    // MARK: - Gestures
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(5.0, max(0.5, lastScale * value))
            }
            .onEnded { _ in lastScale = scale }
    }
    
    // MARK: - Actions
    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
    
    private func resetView() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if scale > 1.0 {
                resetView()
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }
    
    private func zoomIn() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            scale = min(5.0, scale + 0.25)
            lastScale = scale
        }
    }
    
    private func zoomOut() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            scale = max(1.0, scale - 0.25)
            lastScale = scale
        }
    }
    
    private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = filename
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    let type: NSBitmapImageRep.FileType = url.pathExtension.lowercased() == "png" ? .png : .jpeg
                    let properties: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg ? [.compressionFactor: 0.9] : [:]
                    
                    if let data = bitmap.representation(using: type, properties: properties) {
                        try? data.write(to: url)
                    }
                }
            }
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

// MARK: - Checkerboard Pattern (for transparency)
struct CheckerboardPattern: View {
    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = 10
            let cols = Int(geo.size.width / size) + 1
            let rows = Int(geo.size.height / size) + 1
            
            Canvas { context, _ in
                for row in 0..<rows {
                    for col in 0..<cols {
                        if (row + col) % 2 == 0 {
                            let rect = CGRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size)
                            context.fill(Path(rect), with: .color(.white))
                        }
                    }
                }
            }
        }
    }
}
