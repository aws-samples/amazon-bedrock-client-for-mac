import AppKit
import SwiftUI

struct ThreadInspector: View {
    let chat: ChatModel
    @ObservedObject private var store = AppStore.shared
    @State private var showPrompt = false
    var body: some View {
        Form {
            Section("Thread") {
                LabeledContent("Model", value: chat.name)
                Text(chat.id).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                SkillPicker(threadID: chat.chatId)
            }
            Section("Instructions for this thread") {
                TextEditor(text: Binding(get: { store.thread(chat.chatId).systemPrompt }, set: { value in store.updateThread(chat.chatId) { $0.systemPrompt = value } }))
                    .font(.system(size: 12))
                    .frame(minHeight: 100)
                Button("Inspect effective prompt") { showPrompt = true }
            }
            Section("Local tools") {
                ForEach(LocalToolExecutor.availableTools(threadID: chat.chatId)) { tool in Label(tool.title, systemImage: tool.symbol).font(.callout) }
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
