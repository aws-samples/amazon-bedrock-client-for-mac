import AppKit
import SwiftUI
import MCP

struct SystemPromptEditor: View {
    @StateObject private var templateManager = PromptTemplateStore.shared
    @State private var showingAddSheet = false
    @State private var showingRenameSheet = false
    @State private var showingDeleteAlert = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Menu-style template selector with management options
            HStack(spacing: 12) {
                Text("System prompt").font(DesignTokens.label)
                Spacer(minLength: 12)
                ActionMenu {
                    // Template list
                    ForEach(templateManager.templates) { template in
                        Button {
                            templateManager.selectTemplate(template)
                        } label: {
                            HStack {
                                Text(template.name)
                                if templateManager.selectedTemplateId == template.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    // Management options
                    Button {
                        newName = ""
                        showingAddSheet = true
                    } label: {
                        Label("Add New Preset...", systemImage: "plus")
                    }

                    if templateManager.selectedTemplate != nil {
                        Button {
                            newName = templateManager.selectedTemplate?.name ?? ""
                            showingRenameSheet = true
                        } label: {
                            Label("Rename...", systemImage: "pencil")
                        }

                        if templateManager.templates.count > 1 {
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(templateManager.selectedTemplate?.name ?? "Default")
                            .font(DesignTokens.body).lineLimit(1).truncationMode(.tail)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("System prompt preset")
            }

            if let selected = templateManager.selectedTemplate {
                // Capture the preset identity: a pending edit must never write
                // into the next preset when the selection changes.
                MultilineRoundedTextField(
                    text: Binding(
                        get: { templateManager.templates.first { $0.id == selected.id }?.content ?? "" },
                        set: { newContent in
                            if var template = templateManager.templates.first(where: { $0.id == selected.id }), template.content != newContent {
                                template.content = newContent
                                templateManager.updateTemplate(template)
                            }
                        }
                    ),
                    placeholder: "Instructions for how the model should respond…"
                )
                .id(selected.id)
                .frame(height: 128)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            PromptNameSheet(
                isPresented: $showingAddSheet,
                title: "New System Prompt",
                name: $newName,
                buttonTitle: "Create",
                onSave: {
                    templateManager.addTemplate(name: newName, content: "")
                }
            )
        }
        .sheet(isPresented: $showingRenameSheet) {
            PromptNameSheet(
                isPresented: $showingRenameSheet,
                title: "Rename Preset",
                name: $newName,
                buttonTitle: "Save",
                onSave: {
                    if var template = templateManager.selectedTemplate {
                        template.name = newName
                        templateManager.updateTemplate(template)
                    }
                }
            )
        }
        .alert("Delete Preset?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let template = templateManager.selectedTemplate {
                    templateManager.deleteTemplate(template)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(templateManager.selectedTemplate?.name ?? "")\"?")
        }
    }
}

// MARK: - Prompt Name Sheet (for Add/Rename)
struct PromptNameSheet: View {
    @Binding var isPresented: Bool
    let title: String
    @Binding var name: String
    let buttonTitle: String
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(buttonTitle) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
