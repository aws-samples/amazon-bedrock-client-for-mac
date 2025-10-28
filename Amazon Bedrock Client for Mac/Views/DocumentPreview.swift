//
//  DocumentPreviewModal.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/4/25.
//

import SwiftUI
import PDFKit
import AppKit

/**
 * Modern document preview modal with macOS 15.3+ design language
 * Features multi-page PDF support and elegant UI
 */
struct DocumentPreviewModal: View {
    var documentData: Data
    var filename: String
    var fileExtension: String
    @Binding var isPresented: Bool
    
    // View state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls: Bool = true
    @State private var temporaryFileURL: URL?
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var isPresentingExternalAppAlert: Bool = false
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .blur(radius: 30)
            
            // Main content
            VStack(spacing: 0) {
                // Header area
                headerBar
                
                // Document viewer area
                documentContent
                
                // Footer area - Page controls for PDFs
                if isPDF() && totalPages > 1 {
                    pageControls
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ?
                          NSColor.windowBackgroundColor : NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .frame(width: 900, height: 700)
        }
        .transition(.opacity)
        .onAppear {
            createTemporaryFile()
            if isPDF() {
                updatePDFPageCount()
            }
        }
        .onDisappear {
            cleanupTemporaryFile()
        }
        .alert(isPresented: $isPresentingExternalAppAlert) {
            Alert(
                title: Text("Open in External Application?"),
                message: Text("This document will be opened with your default application for \(fileExtension.uppercased()) files."),
                primaryButton: .default(Text("Open")) {
                    openInExternalApp()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - UI Components
    
    private var headerBar: some View {
        HStack {
            // File icon and name
            HStack(spacing: 10) {
                Image(systemName: documentIconName)
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.headline)
                    
                    Text("\(fileExtension.uppercased()) • \(formattedFileSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Toolbar buttons
            HStack(spacing: 16) {
                if isPDF() {
                    // Zoom controls for PDF
                    Button(action: {
                        scale = max(0.5, scale - 0.25)
                        lastScale = scale
                    }) {
                        Image(systemName: "minus")
                            .padding(6)
                    }
                    .buttonStyle(CustomToolbarButtonStyle())
                    .disabled(scale <= 0.5)
                    
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 45)
                    
                    Button(action: {
                        scale = min(3.0, scale + 0.25)
                        lastScale = scale
                    }) {
                        Image(systemName: "plus")
                            .padding(6)
                    }
                    .buttonStyle(CustomToolbarButtonStyle())
                    .disabled(scale >= 3.0)
                }
                
                Divider()
                    .frame(height: 16)
                
                // Save button
                Button(action: saveDocument) {
                    Image(systemName: "square.and.arrow.down")
                        .padding(6)
                }
                .buttonStyle(CustomToolbarButtonStyle())
                .help("Save Document")
                
                // Copy button for PDF
                if isPDF() {
                    Button(action: copyDocumentToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .padding(6)
                    }
                    .buttonStyle(CustomToolbarButtonStyle())
                    .help("Copy to Clipboard")
                }
                
                // Close button
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .padding(6)
                }
                .buttonStyle(CustomToolbarButtonStyle())
                .help("Close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Updated background with frosted glass effect
        .background(
            ZStack {
                if colorScheme == .dark {
                    Color.black.opacity(0.3)
                } else {
                    Color.white.opacity(0.7)
                }
            }
            .background(Material.regular)
        )
        .cornerRadius(16, corners: [.topLeft, .topRight])
    }

    
    @ViewBuilder
    private var documentContent: some View {
        ZStack {
            Color(colorScheme == .dark ? NSColor.textBackgroundColor : .white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            if isPDF() {
                EnhancedPDFPreview(
                    documentData: documentData,
                    scale: scale,
                    currentPage: $currentPage,
                    totalPages: $totalPages
                )
                .gesture(dragGesture)
                .gesture(magnificationGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            resetView()
                        } else {
                            scale = 2.0
                            lastScale = 2.0
                        }
                    }
                }
            } else if isTextDocument() {
                TextDocumentPreview(documentData: documentData)
                    .padding()
            } else {
                // Other document types
                VStack(spacing: 24) {
                    Image(systemName: documentIconName)
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Preview not available for this file type")
                        .font(.headline)
                    
                    Button("Open with Default Application") {
                        isPresentingExternalAppAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(10)
    }
    
    private var pageControls: some View {
        HStack(spacing: 20) {
            Button(action: {
                if currentPage > 1 {
                    currentPage -= 1
                }
            }) {
                Image(systemName: "chevron.left")
                    .padding(6)
            }
            .buttonStyle(CustomToolbarButtonStyle())
            .disabled(currentPage <= 1)
            
            Text("Page \(currentPage) of \(totalPages)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            Button(action: {
                if currentPage < totalPages {
                    currentPage += 1
                }
            }) {
                Image(systemName: "chevron.right")
                    .padding(6)
            }
            .buttonStyle(CustomToolbarButtonStyle())
            .disabled(currentPage >= totalPages)
        }
        .padding(.vertical, 12)
        // Updated to match header style
        .background(
            ZStack {
                if colorScheme == .dark {
                    Color.black.opacity(0.3)
                } else {
                    Color.white.opacity(0.7)
                }
            }
            .background(Material.regular)
        )
        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
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
            .onEnded { value in
                lastOffset = offset
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.5, min(3.0, lastScale * value))
            }
            .onEnded { value in
                lastScale = scale
            }
    }
    
    // MARK: - Helper Methods
    
    private var documentIconName: String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.text"
        case "csv", "xls", "xlsx": return "tablecells"
        case "doc", "docx": return "doc.text"
        case "json", "xml": return "curlybraces"
        case "html": return "globe"
        default: return "doc"
        }
    }
    
    private var formattedFileSize: String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: Int64(documentData.count))
    }
    
    private func isPDF() -> Bool {
        return fileExtension.lowercased() == "pdf"
    }
    
    private func isTextDocument() -> Bool {
        let textExtensions = ["txt", "md", "json", "csv", "html", "xml"]
        return textExtensions.contains(fileExtension.lowercased())
    }
    
    private func resetView() {
        withAnimation(.spring()) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func updatePDFPageCount() {
        if let pdfDocument = PDFDocument(data: documentData) {
            totalPages = pdfDocument.pageCount
        }
    }
    
    private func createTemporaryFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + "." + fileExtension
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try documentData.write(to: fileURL)
            temporaryFileURL = fileURL
        } catch {
            print("Failed to create temporary file: \(error)")
        }
    }
    
    private func cleanupTemporaryFile() {
        if let url = temporaryFileURL {
            try? FileManager.default.removeItem(at: url)
            temporaryFileURL = nil
        }
    }
    
    private func saveDocument() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try documentData.write(to: url)
                } catch {
                    print("Failed to save document: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func copyDocumentToClipboard() {
        if isPDF(),
           let pdfDocument = PDFDocument(data: documentData),
           let firstPage = pdfDocument.page(at: 0) {
            let pageImage = firstPage.thumbnail(of: NSSize(width: 200, height: 200), for: .cropBox)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([pageImage])
        }
    }
    
    private func openInExternalApp() {
        if let url = temporaryFileURL {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Modern Button Style
struct CustomToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .foregroundColor(configuration.isPressed ? .secondary : .primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.0))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - PDF Preview View
struct EnhancedPDFPreview: NSViewRepresentable {
    var documentData: Data
    var scale: CGFloat
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(data: documentData)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous // Use correct enum case
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.delegate = context.coordinator
        
        // Update page count
        if let document = pdfView.document {
            totalPages = document.pageCount
        }
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.scaleFactor = scale
        
        // Update PDF current page when page number changes
        if let document = nsView.document,
           currentPage <= document.pageCount,
           let page = document.page(at: currentPage - 1) {
            nsView.go(to: page)
        }
    }
    
    class Coordinator: NSObject, PDFViewDelegate {
        var parent: EnhancedPDFPreview
        
        init(_ parent: EnhancedPDFPreview) {
            self.parent = parent
        }
        
        // Called when PDF page changes
        func pdfViewPageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            
            // Directly assign the non-optional Int value
            let pageIndex = document.index(for: currentPage)
            let parent = self.parent
            
            Task { @MainActor in
                parent.currentPage = pageIndex + 1
            }
        }
    }
}

// MARK: - Text Document Preview
struct TextDocumentPreview: NSViewRepresentable {
    var documentData: Data
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView,
           let string = String(data: documentData, encoding: .utf8) {
            textView.string = string
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.backgroundColor = NSColor.clear
            textView.textColor = NSColor.textColor
            
            // Enable word wrap
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.layoutManager?.allowsNonContiguousLayout = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Additional configuration if needed
    }
}


// Helper extension for rounded corners on specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

// RoundedCornerShape that works with specific corners
struct RoundedCornerShape: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadius: radius
        )
        return Path(path.cgPath)
    }
}

// Extension for NSBezierPath to support cornerRadius on specific corners
extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadius: CGFloat) {
        self.init()
        
        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)
        
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        let radius = cornerRadius
        
        self.move(to: NSPoint(x: minX + (topLeft ? radius : 0), y: minY))
        
        // Top edge and top-right corner
        self.line(to: NSPoint(x: maxX - (topRight ? radius : 0), y: minY))
        if topRight {
            self.appendArc(
                withCenter: NSPoint(x: maxX - radius, y: minY + radius),
                radius: radius,
                startAngle: 270,
                endAngle: 0
            )
        }
        
        // Right edge and bottom-right corner
        self.line(to: NSPoint(x: maxX, y: maxY - (bottomRight ? radius : 0)))
        if bottomRight {
            self.appendArc(
                withCenter: NSPoint(x: maxX - radius, y: maxY - radius),
                radius: radius,
                startAngle: 0,
                endAngle: 90
            )
        }
        
        // Bottom edge and bottom-left corner
        self.line(to: NSPoint(x: minX + (bottomLeft ? radius : 0), y: maxY))
        if bottomLeft {
            self.appendArc(
                withCenter: NSPoint(x: minX + radius, y: maxY - radius),
                radius: radius,
                startAngle: 90,
                endAngle: 180
            )
        }
        
        // Left edge and top-left corner
        self.line(to: NSPoint(x: minX, y: minY + (topLeft ? radius : 0)))
        if topLeft {
            self.appendArc(
                withCenter: NSPoint(x: minX + radius, y: minY + radius),
                radius: radius,
                startAngle: 180,
                endAngle: 270
            )
        }
        
        self.close()
    }
    
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        
        return path
    }
}

// UIRectCorner implementation for macOS
struct UIRectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
