//
//  ImagePreview.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/2/25.
//

import SwiftUI
import AppKit

/**
 * Modern image preview modal with clean design
 * Features zoom controls, gestures, and elegant UI matching DocumentPreviewModal
 */
struct ImagePreviewModal: View {
    var image: NSImage
    var filename: String
    @Binding var isPresented: Bool
    var onMaskCreated: ((NSImage) -> Void)? = nil
    var showMaskingTools: Bool = false
    
    // View state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showCopiedFeedback: Bool = false
    
    // Masking state
    @State private var isMaskingMode: Bool = false
    @State private var maskPaths: [MaskPath] = []
    @State private var currentPath: [CGPoint] = []
    @State private var brushSize: CGFloat = 30
    @State private var maskType: MaskType = .inpainting
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    
    private let cornerRadius: CGFloat = 16
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            
            // Main content
            VStack(spacing: 0) {
                headerBar
                    .zIndex(1)  // Keep toolbar above image
                
                imageContent
                    .zIndex(0)  // Image behind toolbar
                
                if isMaskingMode {
                    maskingToolbar
                        .zIndex(1)
                }
                
                footerBar
                    .zIndex(1)  // Keep footer above image
            }
            .background(containerBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
            .frame(width: 900, height: isMaskingMode ? 750 : 700)
            
            // Copied feedback toast
            if showCopiedFeedback {
                copiedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { resetView() }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
    
    @ViewBuilder
    private var containerBackground: some View {
        if colorScheme == .dark {
            Color(NSColor.windowBackgroundColor)
        } else {
            Color(NSColor.controlBackgroundColor)
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            // File icon and name
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) • \(fileExtension.uppercased())")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Toolbar buttons
            HStack(spacing: 8) {
                // Zoom controls
                HStack(spacing: 8) {
                    toolbarButton(icon: "minus", action: zoomOut)
                        .disabled(scale <= 0.5)
                    
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                    
                    toolbarButton(icon: "plus", action: zoomIn)
                        .disabled(scale >= 5.0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                
                Divider().frame(height: 20)
                
                toolbarButton(icon: "arrow.counterclockwise", action: resetView)
                    .help("Reset View")
                
                toolbarButton(icon: "square.and.arrow.down", action: saveImage)
                    .help("Save Image")
                
                toolbarButton(icon: "doc.on.doc", action: copyToClipboard)
                    .help("Copy to Clipboard")
                
                if showMaskingTools {
                    Divider().frame(height: 20)
                    
                    toolbarButton(
                        icon: isMaskingMode ? "pencil.slash" : "pencil.tip.crop.circle",
                        action: { isMaskingMode.toggle() }
                    )
                    .help(isMaskingMode ? "Exit Masking" : "Masking Tools")
                }
                
                Divider().frame(height: 20)
                
                // Close button
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.03).background(.ultraThinMaterial))
    }
    
    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Image Content
    @ViewBuilder
    private var imageContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Checkerboard fills entire area
                CheckerboardPattern(colorScheme: colorScheme)
                    .opacity(colorScheme == .dark ? 0.15 : 0.08)
                
                if isMaskingMode {
                    MaskingCanvasView(
                        image: image,
                        maskPaths: $maskPaths,
                        currentPath: $currentPath,
                        brushSize: brushSize,
                        maskType: maskType,
                        scale: scale,
                        offset: offset
                    )
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .gesture(magnificationGesture)
                        .onTapGesture(count: 2) { toggleZoom() }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }
    
    // MARK: - Masking Toolbar
    private var maskingToolbar: some View {
        HStack(spacing: 16) {
            // Mask type selector
            Picker("Mask Type", selection: $maskType) {
                Text("Inpainting").tag(MaskType.inpainting)
                Text("Outpainting").tag(MaskType.outpainting)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            Divider().frame(height: 24)
            
            // Brush size
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Slider(value: $brushSize, in: 5...100)
                    .frame(width: 120)
                Image(systemName: "circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                Text("\(Int(brushSize))px")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 45)
            }
            
            Divider().frame(height: 24)
            
            // Actions
            Button(action: { maskPaths.removeAll(); currentPath.removeAll() }) {
                Label("Clear", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.8))
            
            Button(action: applyMask) {
                Label("Apply Mask", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(maskPaths.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03).background(.ultraThinMaterial))
    }
    
    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack {
            Text(fileExtension.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            
            Spacer()
            
            Text(formattedFileSize)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - Copied Toast
    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Copied to clipboard")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .position(x: 450, y: 60)
    }
    
    // MARK: - Helpers
    private var fileExtension: String {
        filename.components(separatedBy: ".").last ?? "png"
    }
    
    private var formattedFileSize: String {
        guard let tiffData = image.tiffRepresentation else { return "Unknown" }
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: Int64(tiffData.count))
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
                scale = max(0.5, min(5.0, lastScale * value))
            }
            .onEnded { _ in lastScale = scale }
    }
    
    // MARK: - Actions
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
            scale = max(0.5, scale - 0.25)
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
        
        // Write both NSImage and PNG data for better compatibility
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
        pasteboard.writeObjects([image])
        
        // Show feedback
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showCopiedFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showCopiedFeedback = false
            }
        }
    }
    
    private func applyMask() {
        guard !maskPaths.isEmpty else { return }
        
        let maskImage = createMaskImage()
        onMaskCreated?(maskImage)
        
        maskPaths.removeAll()
        currentPath.removeAll()
        isMaskingMode = false
    }
    
    private func createMaskImage() -> NSImage {
        let size = image.size
        let maskImage = NSImage(size: size)
        
        maskImage.lockFocus()
        
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        NSColor.black.setFill()
        NSColor.black.setStroke()
        
        for maskPath in maskPaths {
            let path = NSBezierPath()
            path.lineWidth = maskPath.brushSize
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            
            if let first = maskPath.points.first {
                path.move(to: first)
                for point in maskPath.points.dropFirst() {
                    path.line(to: point)
                }
            }
            path.stroke()
        }
        
        maskImage.unlockFocus()
        return maskImage
    }
}

// MARK: - Mask Types
enum MaskType {
    case inpainting
    case outpainting
}

struct MaskPath {
    var points: [CGPoint]
    var brushSize: CGFloat
}

// MARK: - Masking Canvas View
struct MaskingCanvasView: View {
    let image: NSImage
    @Binding var maskPaths: [MaskPath]
    @Binding var currentPath: [CGPoint]
    let brushSize: CGFloat
    let maskType: MaskType
    let scale: CGFloat
    let offset: CGSize
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                Canvas { context, _ in
                    for path in maskPaths {
                        var bezierPath = Path()
                        if let first = path.points.first {
                            bezierPath.move(to: first)
                            for point in path.points.dropFirst() {
                                bezierPath.addLine(to: point)
                            }
                        }
                        context.stroke(
                            bezierPath,
                            with: .color(maskType == .inpainting ? .red.opacity(0.5) : .blue.opacity(0.5)),
                            lineWidth: path.brushSize
                        )
                    }
                    
                    if !currentPath.isEmpty {
                        var bezierPath = Path()
                        bezierPath.move(to: currentPath[0])
                        for point in currentPath.dropFirst() {
                            bezierPath.addLine(to: point)
                        }
                        context.stroke(
                            bezierPath,
                            with: .color(maskType == .inpainting ? .red.opacity(0.7) : .blue.opacity(0.7)),
                            lineWidth: brushSize
                        )
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentPath.append(value.location)
                        }
                        .onEnded { _ in
                            if !currentPath.isEmpty {
                                maskPaths.append(MaskPath(points: currentPath, brushSize: brushSize))
                                currentPath.removeAll()
                            }
                        }
                )
            }
            .scaleEffect(scale)
            .offset(offset)
        }
    }
}

// MARK: - Checkerboard Pattern
struct CheckerboardPattern: View {
    var colorScheme: ColorScheme = .dark
    
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
                            context.fill(Path(rect), with: .color(colorScheme == .dark ? .white : .gray))
                        }
                    }
                }
            }
        }
    }
}
