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
 * Modern document preview modal with clean design
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
                documentContent
                
                // Footer for PDFs with multiple pages
                if isPDF() && totalPages > 1 {
                    pageControls
                } else if isTextDocument() {
                    textFooter
                }
            }
            .background(containerBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
            .frame(width: 900, height: 700)
        }
        .onAppear {
            createTemporaryFile()
            if isPDF() { updatePDFPageCount() }
        }
        .onDisappear { cleanupTemporaryFile() }
        .alert(isPresented: $isPresentingExternalAppAlert) {
            Alert(
                title: Text("Open in External Application?"),
                message: Text("This document will be opened with your default application for \(fileExtension.uppercased()) files."),
                primaryButton: .default(Text("Open")) { openInExternalApp() },
                secondaryButton: .cancel()
            )
        }
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
    
    // MARK: - Text Footer
    private var textFooter: some View {
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
    
    // MARK: - UI Components
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // File icon and name
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(documentIconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: documentIconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(documentIconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    Text("\(fileExtension.uppercased()) • \(formattedFileSize)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Toolbar buttons
            HStack(spacing: 8) {
                if isPDF() {
                    // Zoom controls for PDF
                    HStack(spacing: 8) {
                        toolbarButton(icon: "minus", action: {
                            scale = max(0.5, scale - 0.25)
                            lastScale = scale
                        })
                        .disabled(scale <= 0.5)
                        
                        Text("\(Int(scale * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                        
                        toolbarButton(icon: "plus", action: {
                            scale = min(3.0, scale + 0.25)
                            lastScale = scale
                        })
                        .disabled(scale >= 3.0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    
                    Divider().frame(height: 20)
                }
                
                toolbarButton(icon: "square.and.arrow.down", action: saveDocument)
                    .help("Save Document")
                
                if isPDF() || isTextDocument() {
                    toolbarButton(icon: "doc.on.doc", action: copyDocumentToClipboard)
                        .help("Copy to Clipboard")
                }
                
                toolbarButton(icon: "arrow.up.forward.square", action: { isPresentingExternalAppAlert = true })
                    .help("Open in External App")
                
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
    
    private var documentIconColor: Color {
        switch fileExtension.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "txt", "md": return .gray
        case "html": return .orange
        case "json", "xml": return .purple
        default: return .gray
        }
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if isPDF(),
           let pdfDocument = PDFDocument(data: documentData),
           let firstPage = pdfDocument.page(at: 0) {
            // Copy PDF as image
            let pageImage = firstPage.thumbnail(of: NSSize(width: 200, height: 200), for: .cropBox)
            pasteboard.writeObjects([pageImage])
        } else if isTextDocument() {
            // Copy text content
            if let textContent = String(data: documentData, encoding: .utf8) ??
                                 String(data: documentData, encoding: .isoLatin1) {
                pasteboard.setString(textContent, forType: .string)
            }
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
            
            // Capture values before async context
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
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        
        if let textView = scrollView.documentView as? NSTextView {
            // Try UTF-8 first, then other encodings
            let string: String
            if let utf8String = String(data: documentData, encoding: .utf8) {
                string = utf8String
            } else if let latin1String = String(data: documentData, encoding: .isoLatin1) {
                string = latin1String
            } else {
                string = "Unable to decode text content"
            }
            
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
            textView.layoutManager?.allowsNonContiguousLayout = true  // Better performance for large files
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            
            // Line numbers and better readability
            textView.textContainerInset = NSSize(width: 16, height: 12)
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
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
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
