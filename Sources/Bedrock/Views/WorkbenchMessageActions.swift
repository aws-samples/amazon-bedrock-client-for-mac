import SwiftUI

enum WorkbenchMessageAction {
    case edit, retry, branch, details
}

struct WorkbenchMessageEditor: View {
    let message: Message
    var title = "Edit message"
    var detail = "Send a revision in a new branch. Your original conversation stays available."
    var saveTitle = "Save & send"
    let onSave: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var attachmentCount: Int {
        (message.imageBase64Strings?.count ?? 0) + (message.documentBase64Strings?.count ?? 0) + (message.pastedTexts?.count ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(detail)
                .font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(WorkbenchStyle.body).scrollContentBackground(.hidden)
                .padding(12).background(WorkbenchStyle.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchStyle.border))
                .frame(minHeight: 180, maxHeight: 360).focused($focused).disabled(saving)
            if attachmentCount > 0 {
                Label("\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s") kept with this message", systemImage: "paperclip")
                    .font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(WorkbenchStyle.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(saveTitle) {
                    saving = true
                    Task {
                        do { try await onSave(text); dismiss() }
                        catch { self.error = error.localizedDescription; saving = false }
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(saving || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachmentCount == 0))
            }.controlSize(.regular)
        }
        .padding(24).frame(width: 580).background(WorkbenchStyle.canvas)
        .onAppear { text = message.text; focused = true }
        .interactiveDismissDisabled(saving)
    }
}

struct WorkbenchQueueView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var editing: QueuedPrompt?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var prompts: [QueuedPrompt] { viewModel.outbox.queued }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(viewModel.outbox.pauseReason == nil ? "Up next" : "Queue paused")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if viewModel.isUpdatingQueue { ProgressView().controlSize(.mini) }
                Button(viewModel.outbox.pauseReason == nil ? "Pause queue" : "Resume") {
                    Task { await viewModel.setQueuePaused(viewModel.outbox.pauseReason == nil) }
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
            }.padding(.horizontal, 12).padding(.top, 9)
            if let reason = viewModel.outbox.pauseReason {
                Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).padding(.horizontal, 12)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(expanded ? prompts : Array(prompts.prefix(3))) { prompt in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button { editing = prompt } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(prompt.message.text.isEmpty ? "Attachments" : prompt.message.text).font(.system(size: 12)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(WorkbenchModelCatalog.shared.model(prompt.modelID).name)
                                        if prompt.attachmentCount > 0 { Label("\(prompt.attachmentCount)", systemImage: "paperclip") }
                                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Edit queued message").accessibilityLabel("Edit queued message: \(String(prompt.message.text.prefix(80)))")
                            Button { Task { await viewModel.sendQueuedPromptNow(prompt.id) } } label: {
                                Image(systemName: "arrow.up.circle").font(.system(size: 15)).frame(width: 26, height: 26)
                            }.buttonStyle(LiquidGlassToolbarButtonStyle()).help("Stop the current response and send this next").accessibilityLabel("Send queued message now")
                            Button { Task { await viewModel.removeQueuedPrompt(prompt.id) } } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 24, height: 26)
                            }.buttonStyle(LiquidGlassToolbarButtonStyle()).help("Remove from queue").accessibilityLabel("Remove queued message")
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
            }.frame(height: CGFloat(min(expanded ? 5 : 3, prompts.count)) * 49)
            if prompts.count > 3 {
                Button(expanded ? "Show fewer" : "\(prompts.count - 3) more messages") { expanded.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .background(WorkbenchStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkbenchStyle.border))
        .disabled(viewModel.isUpdatingQueue)
        .animation(reduceMotion ? nil : WorkbenchMotion.standard, value: prompts.map(\.id))
        .animation(reduceMotion ? nil : WorkbenchMotion.standard, value: expanded)
        .accessibilityIdentifier("conversation.queue")
        .sheet(item: $editing) { prompt in
            let message = ConversationHistory.fromMessages([prompt.message], chatID: viewModel.chatId, modelID: prompt.modelID).messages[0]
            WorkbenchMessageEditor(message: message, title: "Queued message",
                detail: "Your text, attachments and model are saved together until this message is sent.", saveTitle: "Save changes") { text in
                try await viewModel.editQueuedPrompt(prompt.id, text: text)
            }
        }
    }
}

struct WorkbenchMessageDetails: View {
    let message: MessageData
    let fallbackModelID: String
    @Environment(\.dismiss) private var dismiss
    private var modelID: String { message.modelID ?? fallbackModelID }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Message details").font(.system(size: 20, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                GridRow {
                    Text("Sent").foregroundStyle(.secondary)
                    Text(message.sentTime.formatted(date: .abbreviated, time: .standard))
                }
                GridRow {
                    Text("Model").foregroundStyle(.secondary)
                    Text(WorkbenchModelCatalog.shared.model(modelID).name)
                }
                GridRow {
                    Text("Model ID").foregroundStyle(.secondary)
                    Text(modelID).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
                GridRow {
                    Text("Message ID").foregroundStyle(.secondary)
                    Text(message.id.uuidString).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }.font(WorkbenchStyle.body)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 540).background(WorkbenchStyle.canvas)
    }
}

struct WorkbenchPastedTextEditor: View {
    let filename: String
    let initialText: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private var valid: Bool { !text.isEmpty && text.utf8.count <= 4_500_000 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pasted text").font(.system(size: 20, weight: .semibold))
            Text(filename).font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 12, design: .monospaced))
                .accessibilityIdentifier("pastedText.editor")
                .scrollContentBackground(.hidden).padding(12)
                .background(WorkbenchStyle.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchStyle.border))
                .frame(height: 330)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file))
                    .font(WorkbenchStyle.caption).foregroundStyle(.secondary)
                Button("Save changes") { onSave(text); dismiss() }
                    .keyboardShortcut("s", modifiers: .command).disabled(!valid)
            }
        }.padding(24).frame(width: 600).background(WorkbenchStyle.canvas)
            .onAppear { text = initialText }
    }
}
