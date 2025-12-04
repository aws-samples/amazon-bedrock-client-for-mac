//
//  PromptTemplateManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 12/4/25.
//

import Foundation
import Combine
import Logging

// MARK: - System Prompt Template Model
struct SystemPromptTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Default template (empty system prompt)
    static let defaultTemplate = SystemPromptTemplate(
        name: "Default",
        content: ""
    )
    
    // Example templates
    static let examples: [SystemPromptTemplate] = [
        SystemPromptTemplate(
            name: "Concise Assistant",
            content: "You are a helpful assistant. Be concise and direct in your responses. Avoid unnecessary explanations."
        ),
        SystemPromptTemplate(
            name: "Code Expert",
            content: "You are an expert software engineer. Focus on writing clean, efficient, and well-documented code. Always explain your reasoning."
        ),
        SystemPromptTemplate(
            name: "Creative Writer",
            content: "You are a creative writing assistant. Help with storytelling, brainstorming ideas, and improving prose. Be imaginative and engaging."
        )
    ]
}

// MARK: - System Prompt Template Manager
@MainActor
class PromptTemplateManager: ObservableObject {
    static let shared = PromptTemplateManager()
    private var logger = Logger(label: "PromptTemplateManager")
    
    @Published var templates: [SystemPromptTemplate] = [] {
        didSet {
            saveTemplates()
        }
    }
    
    @Published var selectedTemplateId: UUID? {
        didSet {
            if let id = selectedTemplateId,
               let template = templates.first(where: { $0.id == id }) {
                // Update the system prompt in SettingManager
                SettingManager.shared.systemPrompt = template.content
            }
            saveSelectedTemplate()
        }
    }
    
    private let storageKey = "systemPromptTemplates"
    private let selectedTemplateKey = "selectedSystemPromptTemplateId"
    
    private init() {
        loadTemplates()
        loadSelectedTemplate()
    }
    
    // MARK: - Selected Template
    
    var selectedTemplate: SystemPromptTemplate? {
        guard let id = selectedTemplateId else { return nil }
        return templates.first { $0.id == id }
    }
    
    func selectTemplate(_ template: SystemPromptTemplate) {
        selectedTemplateId = template.id
        logger.info("Selected template: \(template.name)")
    }
    
    // MARK: - CRUD Operations
    
    func addTemplate(_ template: SystemPromptTemplate) {
        templates.append(template)
        logger.info("Added template: \(template.name)")
    }
    
    func addTemplate(name: String, content: String) {
        let template = SystemPromptTemplate(name: name, content: content)
        addTemplate(template)
        // Auto-select the newly created template
        selectTemplate(template)
    }
    
    func updateTemplate(_ template: SystemPromptTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            templates[index] = updated
            
            // If this is the selected template, update system prompt
            if selectedTemplateId == template.id {
                SettingManager.shared.systemPrompt = updated.content
            }
            
            logger.info("Updated template: \(template.name)")
        }
    }
    
    func deleteTemplate(_ template: SystemPromptTemplate) {
        // Don't allow deleting if it's the only template
        guard templates.count > 1 else {
            logger.warning("Cannot delete the only template")
            return
        }
        
        templates.removeAll { $0.id == template.id }
        
        // If deleted template was selected, select the first one
        if selectedTemplateId == template.id {
            selectedTemplateId = templates.first?.id
        }
        
        logger.info("Deleted template: \(template.name)")
    }
    
    func deleteTemplate(at offsets: IndexSet) {
        guard templates.count > offsets.count else { return }
        
        let deletedIds = offsets.map { templates[$0].id }
        templates.remove(atOffsets: offsets)
        
        if let selectedId = selectedTemplateId, deletedIds.contains(selectedId) {
            selectedTemplateId = templates.first?.id
        }
    }
    
    // MARK: - Persistence
    
    private func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SystemPromptTemplate].self, from: data),
           !decoded.isEmpty {
            self.templates = decoded
            logger.info("Loaded \(decoded.count) templates")
        } else {
            // First launch - create default template with current system prompt
            let currentPrompt = SettingManager.shared.systemPrompt
            let defaultTemplate = SystemPromptTemplate(
                name: "Default",
                content: currentPrompt
            )
            self.templates = [defaultTemplate]
            self.selectedTemplateId = defaultTemplate.id
            logger.info("Initialized with default template")
        }
    }
    
    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            logger.debug("Saved \(templates.count) templates")
        }
    }
    
    private func loadSelectedTemplate() {
        if let idString = UserDefaults.standard.string(forKey: selectedTemplateKey),
           let id = UUID(uuidString: idString),
           templates.contains(where: { $0.id == id }) {
            self.selectedTemplateId = id
        } else {
            // Select first template by default
            self.selectedTemplateId = templates.first?.id
        }
    }
    
    private func saveSelectedTemplate() {
        if let id = selectedTemplateId {
            UserDefaults.standard.set(id.uuidString, forKey: selectedTemplateKey)
        }
    }
    
    // MARK: - Import Examples
    
    func importExampleTemplates() {
        for example in SystemPromptTemplate.examples {
            if !templates.contains(where: { $0.name == example.name }) {
                templates.append(example)
            }
        }
        logger.info("Imported example templates")
    }
}
