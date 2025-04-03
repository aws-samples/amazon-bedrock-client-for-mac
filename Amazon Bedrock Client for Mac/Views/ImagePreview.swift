//
//  ImagePreview.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/2/25.
//

import SwiftUI

/**
 * Modal view for displaying full-sized image previews.
 * Shows the original image with filename and provides close functionality.
 */
struct ImagePreviewModal: View {
    var image: NSImage
    var filename: String
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showInfo: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background overlay
            backgroundLayer
            
            // Main content container
            VStack(spacing: 0) {
                headerView
                imageViewer
                footerView
            }
            .frame(width: 900, height: 700)
            .background(Color.black.opacity(0.2))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .transition(.opacity)
        .onAppear(perform: resetImage)
    }
    
    // MARK: - Subviews
    
    private var backgroundLayer: some View {
        Color.black.opacity(0.7)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPresented = false
                }
            }
    }
    
    private var headerView: some View {
        HStack {
            Text(filename)
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            controlButtons
        }
        .padding(20)
        .background(Color.black.opacity(0.4))
    }
    
    private var controlButtons: some View {
        HStack(spacing: 16) {
            Button(action: resetImage) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset View")
            
            Button(action: saveImage) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Save Image")
            
            Button(action: copyImageToClipboard) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Copy to Clipboard")
            
            closeButton
        }
    }
    
    private var closeButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPresented = false
            }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Circle())
    }
    
    private var imageViewer: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                resetImage()
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                lastOffset = offset
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, lastScale * value)
            }
            .onEnded { value in
                lastScale = scale
            }
    }
    
    private var footerView: some View {
        Group {
            if showInfo {
                HStack {
                    imageInfoView
                    Spacer()
                    zoomControlsView
                }
                .padding(16)
                .background(Color.black.opacity(0.4))
            }
        }
    }
    
    private var imageInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dimensions: \(Int(image.size.width)) × \(Int(image.size.height))")
            Text("Format: \(filename.components(separatedBy: ".").last?.uppercased() ?? "Unknown")")
        }
        .font(.caption)
        .foregroundColor(.white)
    }
    
    private var zoomControlsView: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring()) {
                    scale = max(1.0, scale - 0.25)
                    lastScale = scale
                }
            }) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(scale <= 1.0)
            
            Text("\(Int(scale * 100))%")
                .font(.caption)
                .foregroundColor(.white)
                .frame(width: 50)
            
            Button(action: {
                withAnimation(.spring()) {
                    scale += 0.25
                    lastScale = scale
                }
            }) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Helper functions
    
    /// Reset image to original position and scale
    private func resetImage() {
        withAnimation(.spring()) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    /// Save image to disk
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
                        do {
                            try data.write(to: url)
                        } catch {
                            print("Failed to save image: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    /// Copy image to clipboard
    private func copyImageToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
