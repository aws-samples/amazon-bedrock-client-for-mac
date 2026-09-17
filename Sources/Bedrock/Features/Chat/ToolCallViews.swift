import AppKit
import SwiftUI

struct ToolCallsView: View {
    let calls: [Message.ToolUse]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(calls, id: \.toolId) { call in ToolCallRow(call: call) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RequestErrorView: View {
    let source: String
    private var message: String { BedrockFailureMessage.readable(source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Request couldn't finish", systemImage: "exclamationmark.circle")
                .font(DesignTokens.label)
            Text(message).font(DesignTokens.body).lineSpacing(3)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("requestError.message")
            if source != message {
                DisclosureGroup("Details") {
                    ScrollView([.vertical, .horizontal]) {
                        Text(source).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).padding(10)
                    }.frame(maxHeight: 180)
                }.font(DesignTokens.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.border))
    }
}

private struct ToolCallRow: View {
    let call: Message.ToolUse
    @State private var isExpanded = false
    @State private var showDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.beginConversationInspection) private var beginInspection
    private var title: String { call.displayName ?? BuiltInTool(rawValue: call.toolName)?.title ?? call.toolName }
    private var input: String { ToolDetailText.input(call.inputs) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                beginInspection()
                withAnimation(reduceMotion ? nil : AppMotion.standard) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    Image(systemName: call.status == "error" ? "exclamationmark.circle" : call.result == nil ? "circle.dotted" : "checkmark.circle")
                        .font(.system(size: 13)).foregroundStyle(call.status == "error" ? Color.orange : Color.secondary)
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let elapsed = call.elapsedSeconds {
                        Text(elapsed < 0.1 ? "<0.1s" : "\(elapsed.formatted(.number.precision(.fractionLength(1))))s")
                            .font(DesignTokens.detail).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("toolCall.\(call.toolId)")
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    detailBlock("Input", text: input)
                    if let result = call.result { detailBlock(call.status == "error" ? "Error" : "Output", text: ToolDetailText.output(result)) }
                    else { Text("Waiting for the tool to finish…").font(DesignTokens.caption).foregroundStyle(.secondary) }
                    if let images = call.resultImages, !images.isEmpty { ToolResultImagesView(images: images) }
                    HStack {
                        Text(call.serverName ?? call.toolName).font(DesignTokens.detail).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Open details") {
                            beginInspection()
                            showDetails = true
                        }.controlSize(.small)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 14)
            }
        }
        .background(DesignTokens.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.border, lineWidth: 0.5))
        .sheet(isPresented: $showDetails) { ToolDetailSheet(call: call) }
        .accessibilityElement(children: .contain)
    }
    private func detailBlock(_ title: String, text: String) -> some View {
        let preview = text.count > 4_000
            ? String(text.prefix(4_000)) + "\n\nOpen details to read the full output."
            : text
        let lines = preview.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(DesignTokens.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { ToolDetailText.copy(text) }
                    .buttonStyle(.borderless).font(DesignTokens.detail).accessibilityLabel("Copy tool \(title.lowercased())")
            }
            // Keep short output aligned to the leading edge and give the
            // transcript a bounded height, independent of nested scroll layout.
            ToolOutputView(text: preview, findRequest: 0,
                           accessibilityLabel: "Tool \(title.lowercased()) preview")
            .frame(height: min(220, CGFloat(lines) * 16 + 28))
            .background(DesignTokens.canvas, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private enum ToolDetailText {
    static func input(_ input: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(input)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    static func output(_ text: String) -> String {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: formatted, encoding: .utf8) else { return text }
        return string
    }
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ToolDetailSheet: View {
    let call: Message.ToolUse
    @Environment(\.dismiss) private var dismiss
    @State private var showInput = false
    @State private var findRequest = 0
    @State private var referencedFiles: [URL] = []
    private var content: String { showInput ? ToolDetailText.input(call.inputs) : ToolDetailText.output(call.result ?? "The tool has not returned a result yet.") }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(call.displayName ?? BuiltInTool(rawValue: call.toolName)?.title ?? call.toolName)
                        .font(.system(size: 20, weight: .semibold))
                    if let server = call.serverName {
                        Text(server).font(DesignTokens.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Label(call.result == nil ? "Running" : call.status == "error" ? "Failed" : "Completed",
                              systemImage: call.status == "error" ? "exclamationmark.circle" : "checkmark.circle")
                        if let elapsed = call.elapsedSeconds { Text("\(elapsed.formatted(.number.precision(.fractionLength(2)))) seconds") }
                    }.font(DesignTokens.caption).foregroundStyle(call.status == "error" ? Color.orange : Color.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                AppSegmentedControl(title: "Details", selection: $showInput,
                                          options: [(true, "Input"), (false, "Output")]).frame(width: 200)
                Spacer()
                Button { findRequest += 1 } label: { Label("Find", systemImage: "magnifyingglass") }
                    .keyboardShortcut("f", modifiers: .command)
                Button(showInput ? "Copy input" : "Copy output") { ToolDetailText.copy(content) }
            }
            ToolOutputView(text: content, findRequest: findRequest)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.canvas, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.border))
            if !showInput, let images = call.resultImages, !images.isEmpty {
                ToolResultImagesView(images: images)
            }
            if !referencedFiles.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(referencedFiles, id: \.path) { url in
                            HStack(spacing: 10) {
                                Label(url.lastPathComponent, systemImage: "doc")
                                    .lineLimit(1).truncationMode(.middle).help(url.path)
                                Spacer(minLength: 8)
                                Button("Open") { open(url) }
                                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button("Copy path") { ToolDetailText.copy(url.path) }
                            }.font(DesignTokens.caption).controlSize(.small)
                        }
                    }
                }.frame(maxHeight: CGFloat(min(3, referencedFiles.count)) * 30)
            }
            Text("\(call.toolName) · \(call.toolId)").font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
        .padding(24).frame(width: 680, height: 510)
        .onAppear { showInput = call.result == nil }
        .task(id: call.toolId) {
            let store = AppStore.shared
            let access = store.preferences.fileAccess(workingDirectory: store.selectedThreadID.flatMap { store.thread($0).workingDirectory })
            let worker = Task.detached(priority: .userInitiated) {
                try ToolOutputFiles.find(input: call.inputs, output: call.result ?? "", access: access)
            }
            do { referencedFiles = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() } }
            catch { referencedFiles = [] }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toolCall.details")
    }
    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { AppStore.shared.errorMessage = "macOS could not open \(url.lastPathComponent)." }
    }
}

private struct ToolResultImagesView: View {
    let images: [ToolResultImage]
    @State private var selected: Int?
    private var showing: Binding<Bool> {
        Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })
    }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    MessageImageView(imageData: image.base64, size: 140, onTap: { selected = index })
                }
            }
        }
        .frame(maxHeight: 150)
        .sheet(isPresented: showing) {
            if let selected, images.indices.contains(selected) {
                let image = images[selected]
                ImagePreviewModal(
                    source: .stored(image.base64, directory: AppStore.shared.directory),
                    filename: "Tool result.\(image.format)", isPresented: showing)
            }
        }
    }
}

struct ToolApprovalView: View {
    let request: PendingToolApproval
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised").font(.title2).foregroundStyle(DesignTokens.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow \(request.name)?").font(.title3.weight(.semibold))
                    Text("Review the tool input before it runs.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let path = request.workingDirectory { Label(path, systemImage: "folder").font(.caption).textSelection(.enabled) }
            ScrollView {
                Text(request.input).font(.system(size: 12, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .padding(12)
            .frame(minHeight: 100, maxHeight: 300)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("View thread") { AppStore.shared.selectThread(request.threadID) }.buttonStyle(.link)
                Spacer()
                Button("Deny") { ToolApprovalCenter.shared.resolve(request.id, allow: false) }.keyboardShortcut(.cancelAction)
                Button("Allow once") { ToolApprovalCenter.shared.resolve(request.id, allow: true) }
                    .buttonStyle(AppButtonStyle(prominent: true)).tint(DesignTokens.accent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityIdentifier("workbench.toolApproval")
    }
}
