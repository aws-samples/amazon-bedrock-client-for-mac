import AppKit
import SwiftUI

enum WorkbenchStyle {
    static let accent = Color(light: .black, dark: .white)
    static let selection = Color(light: Color(rgba: 0x397e_e8ff), dark: Color(rgba: 0x589b_f5ff))
    static let canvas = Color.background
    static let sidebar = Color(light: Color(rgba: 0xf6f6_f6ff), dark: Color(rgba: 0x1717_17ff))
    static let surface = Color.secondaryBackground
    static let field = Color(light: .white, dark: Color(rgba: 0x2424_24ff))
    static let border = Color.primary.opacity(0.09)
    static let composerBorder = Color(light: .black.opacity(0.08), dark: .white.opacity(0.10))
    static let contentWidth: CGFloat = 800
    static let label = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let detail = Font.system(size: 11)
    static let pagePadding: CGFloat = 24
    static let rowHeight: CGFloat = 32
    static let controlSize: CGFloat = 32
}

struct WorkbenchSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(WorkbenchStyle.body)
                .foregroundStyle(.primary).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(WorkbenchStyle.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? WorkbenchStyle.accent.opacity(0.55) : WorkbenchStyle.border, lineWidth: 1))
    }
}

struct WorkbenchSidebarSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            WorkbenchStyle.sidebar
        } else {
            Rectangle().fill(.regularMaterial)
                .overlay(colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.52))
        }
    }
}

/// One material layer and divider span the entire window, including its titlebar.
/// A second material behind the sidebar content creates a visible color seam.
struct WorkbenchSplitSurface: View {
    let sidebarWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            WorkbenchSidebarSurface().frame(width: sidebarWidth)
            WorkbenchStyle.border.frame(width: sidebarWidth > 0 ? 1 : 0)
            WorkbenchStyle.canvas
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Popovers opened from an NSToolbar item must own keyboard focus too.
/// Otherwise keys can continue to edit the message underneath the controls.
struct WorkbenchPopoverFocus: NSViewRepresentable {
    final class FocusView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in window?.makeKey() }
        }
    }
    func makeNSView(context: Context) -> NSView { FocusView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct WorkbenchComposerMaterial: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                content.glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                content.background(WorkbenchStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WorkbenchStyle.composerBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

struct WorkbenchPageHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
            Text(subtitle).font(WorkbenchStyle.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }
}

struct WorkbenchEmptyState: View {
    var symbol: String
    var title: String
    var detail: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(WorkbenchButtonStyle()) }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkbenchSkillPicker: View {
    let threadID: String
    @ObservedObject private var store = WorkbenchStore.shared
    private var selected: [String] { store.thread(threadID).skillIDs }
    var body: some View {
        WorkbenchActionMenu {
            if store.skills.isEmpty { Text("No local skills installed") }
            ForEach(store.skills) { skill in
                Toggle(isOn: Binding(
                    get: { selected.contains(skill.id) },
                    set: { on in store.updateThread(threadID) {
                        if on && !$0.skillIDs.contains(skill.id) { $0.skillIDs.append(skill.id) }
                        else if !on { $0.skillIDs.removeAll { $0 == skill.id } }
                    }}
                )) { Text(skill.name) }
                .disabled(!store.isSkillEnabled(skill) || store.unavailableReason(for: skill) != nil)
            }
            Divider()
            Button("Manage skills…") { store.showSettings(row: "skills") }
        } label: {
            Label(selected.isEmpty ? "Skills" : "\(selected.count) skill\(selected.count == 1 ? "" : "s")", systemImage: "sparkles")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("workbench.skillPicker")
    }
}

struct WorkbenchRunFooter: View {
    let threadID: String
    @ObservedObject private var store = WorkbenchStore.shared
    @ObservedObject private var settings = SettingManager.shared
    private var run: LocalRunRecord? { store.state.runs.first { $0.threadID == threadID } }
    var body: some View {
        if settings.showUsageInfo, let run {
            Group {
                if run.status == .running {
                    TimelineView(.periodic(from: run.startedAt, by: 1)) { context in metrics(run, date: context.date) }
                } else {
                    metrics(run, date: run.finishedAt ?? run.startedAt)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }
    private func metrics(_ run: LocalRunRecord, date: Date) -> some View {
        HStack(spacing: 10) {
            if run.status == .running { ProgressView().controlSize(.mini) }
            if run.status != .completed { Text(run.status.title) }
            Text("\(max(0, date.timeIntervalSince(run.startedAt)).formatted(.number.precision(.fractionLength(1))))s").monospacedDigit()
            if let input = run.inputTokens { Text("\(input.formatted()) in").monospacedDigit() }
            if let output = run.outputTokens { Text("\(output.formatted()) out").monospacedDigit() }
            if let cache = run.cacheReadTokens, cache > 0 { Text("\(cache.formatted()) cached").monospacedDigit() }
            if let rate = run.tokensPerSecond { Text("\(rate.formatted(.number.precision(.fractionLength(1)))) tok/s").monospacedDigit() }
            Spacer(minLength: 0)
        }
        .font(WorkbenchStyle.detail).foregroundStyle(.secondary).lineLimit(1)
        .frame(maxWidth: WorkbenchStyle.contentWidth)
    }
}

struct WorkbenchToolCallsView: View {
    let calls: [Message.ToolUse]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(calls, id: \.toolId) { call in WorkbenchToolCallRow(call: call) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchRequestError: View {
    let source: String
    private var message: String { BedrockFailureMessage.readable(source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Request couldn't finish", systemImage: "exclamationmark.circle")
                .font(WorkbenchStyle.label)
            Text(message).font(WorkbenchStyle.body).lineSpacing(3)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if source != message {
                DisclosureGroup("Details") {
                    ScrollView([.vertical, .horizontal]) {
                        Text(source).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).padding(10)
                    }.frame(maxHeight: 180)
                }.font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkbenchStyle.border))
    }
}

private struct WorkbenchToolCallRow: View {
    let call: Message.ToolUse
    @State private var isExpanded = false
    @State private var showDetails = false
    private var title: String { call.displayName ?? LocalToolKind(rawValue: call.toolName)?.title ?? call.toolName }
    private var input: String { WorkbenchToolDetailText.input(call.inputs) }
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                detailBlock("Input", text: input)
                if let result = call.result { detailBlock(call.status == "error" ? "Error" : "Output", text: WorkbenchToolDetailText.output(result)) }
                else { Text("Waiting for the tool to finish…").font(WorkbenchStyle.caption).foregroundStyle(.secondary) }
                HStack {
                    Text(call.serverName ?? call.toolName).font(WorkbenchStyle.detail).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Open details") { showDetails = true }.controlSize(.small)
                }
            }.padding(.top, 10).padding(.bottom, 4)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: call.status == "error" ? "exclamationmark.circle" : call.result == nil ? "circle.dotted" : "checkmark.circle")
                    .font(.system(size: 13)).foregroundStyle(call.status == "error" ? Color.orange : Color.secondary)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 8)
                if let elapsed = call.elapsedSeconds {
                    Text(elapsed < 0.1 ? "<0.1s" : "\(elapsed.formatted(.number.precision(.fractionLength(1))))s")
                        .font(WorkbenchStyle.detail).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(WorkbenchStyle.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchStyle.border, lineWidth: 0.5))
        .sheet(isPresented: $showDetails) { WorkbenchToolDetailSheet(call: call) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("toolCall.\(call.toolId)")
    }
    private func detailBlock(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(WorkbenchStyle.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { WorkbenchToolDetailText.copy(text) }
                    .buttonStyle(.borderless).font(WorkbenchStyle.detail).accessibilityLabel("Copy tool \(title.lowercased())")
            }
            ScrollView([.vertical, .horizontal]) {
                Text(text.count > 4_000 ? String(text.prefix(4_000)) + "\n\nOpen details to read the full output." : text)
                    .font(.system(size: 12, design: .monospaced)).lineSpacing(3)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: 220).padding(12)
            .background(WorkbenchStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private enum WorkbenchToolDetailText {
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

private struct WorkbenchToolDetailSheet: View {
    let call: Message.ToolUse
    @Environment(\.dismiss) private var dismiss
    @State private var showInput = false
    @State private var findRequest = 0
    @State private var referencedFiles: [URL] = []
    private var content: String { showInput ? WorkbenchToolDetailText.input(call.inputs) : WorkbenchToolDetailText.output(call.result ?? "The tool has not returned a result yet.") }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(call.displayName ?? LocalToolKind(rawValue: call.toolName)?.title ?? call.toolName)
                        .font(.system(size: 20, weight: .semibold))
                    if let server = call.serverName {
                        Text(server).font(WorkbenchStyle.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Label(call.result == nil ? "Running" : call.status == "error" ? "Failed" : "Completed",
                              systemImage: call.status == "error" ? "exclamationmark.circle" : "checkmark.circle")
                        if let elapsed = call.elapsedSeconds { Text("\(elapsed.formatted(.number.precision(.fractionLength(2)))) seconds") }
                    }.font(WorkbenchStyle.caption).foregroundStyle(call.status == "error" ? Color.orange : Color.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                WorkbenchSegmentedControl(title: "Details", selection: $showInput,
                                          options: [(true, "Input"), (false, "Output")]).frame(width: 200)
                Spacer()
                Button { findRequest += 1 } label: { Label("Find", systemImage: "magnifyingglass") }
                    .keyboardShortcut("f", modifiers: .command)
                Button(showInput ? "Copy input" : "Copy output") { WorkbenchToolDetailText.copy(content) }
            }
            WorkbenchToolOutputView(text: content, findRequest: findRequest)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WorkbenchStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkbenchStyle.border))
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
                                Button("Copy path") { WorkbenchToolDetailText.copy(url.path) }
                            }.font(WorkbenchStyle.caption).controlSize(.small)
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
            let store = WorkbenchStore.shared
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
        if !NSWorkspace.shared.open(url) { WorkbenchStore.shared.errorMessage = "macOS could not open \(url.lastPathComponent)." }
    }
}

struct WorkbenchToolApprovalView: View {
    let request: PendingToolApproval
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised").font(.title2).foregroundStyle(WorkbenchStyle.accent)
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
            .background(WorkbenchStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("View thread") { WorkbenchStore.shared.selectThread(request.threadID) }.buttonStyle(.link)
                Spacer()
                Button("Deny") { ToolApprovalCenter.shared.resolve(request.id, allow: false) }.keyboardShortcut(.cancelAction)
                Button("Allow once") { ToolApprovalCenter.shared.resolve(request.id, allow: true) }
                    .buttonStyle(WorkbenchButtonStyle(prominent: true)).tint(WorkbenchStyle.accent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityIdentifier("workbench.toolApproval")
    }
}

struct WorkbenchThreadInspector: View {
    let chat: ChatModel
    @ObservedObject private var store = WorkbenchStore.shared
    @State private var showPrompt = false
    var body: some View {
        Form {
            Section("Thread") {
                LabeledContent("Model", value: chat.name)
                Text(chat.id).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                WorkbenchSkillPicker(threadID: chat.chatId)
            }
            Section("Instructions for this thread") {
                TextEditor(text: Binding(get: { store.thread(chat.chatId).systemPrompt }, set: { value in store.updateThread(chat.chatId) { $0.systemPrompt = value } }))
                    .font(.system(size: 12))
                    .frame(minHeight: 100)
                Button("Inspect effective prompt") { showPrompt = true }
            }
            Section("Local tools") {
                ForEach(LocalToolManager.availableTools(threadID: chat.chatId)) { tool in Label(tool.title, systemImage: tool.symbol).font(.callout) }
                Button("Configure tools…") { store.showSettings(row: "toolProfile") }
            }
            if let notice = store.thread(chat.chatId).contextNotice { Section("Context") { Text(notice).font(.caption).foregroundStyle(.secondary) } }
        }
        .formStyle(.grouped)
        .frame(minWidth: 270, idealWidth: 300, maxWidth: 360)
        .sheet(isPresented: $showPrompt) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Effective system prompt").font(.headline)
                ScrollView {
                    Text((try? store.effectiveSystemPrompt(for: chat.chatId)) ?? "The selected skills are unavailable.")
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("Done") { showPrompt = false }.keyboardShortcut(.cancelAction) }
            }.padding(24).frame(width: 620, height: 450)
        }
    }
}
