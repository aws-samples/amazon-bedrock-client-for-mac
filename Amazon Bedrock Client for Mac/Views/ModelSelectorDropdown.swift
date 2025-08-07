//
//  ModelSelector.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/9/24.
//

import SwiftUI
import AppKit

// MARK: - ModelSelectorDropdown
/// A custom dropdown menu for model selection with search and favorites
struct ModelSelectorDropdown: View {
    let organizedChatModels: [String: [ChatModel]]
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    
    @State private var isShowingPopover = false
    @State private var searchText = ""
    @State private var isHovering = false
    @ObservedObject private var settingManager = SettingManager.shared
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowingPopover.toggle()
            }
        }) {
            HStack(spacing: 10) {
                if case let .chat(model) = menuSelection {
                    // Display model image inside dropdown button
                    getModelImage(for: model.id)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.provider)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(model.name)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("Select Model")
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .rotationEffect(isShowingPopover ? Angle(degrees: 180) : Angle(degrees: 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowingPopover)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.controlBackgroundColor).opacity(0.8) :
                            Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHovering ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            ModelSelectorPopoverContent(
                organizedChatModels: organizedChatModels,
                searchText: $searchText,
                menuSelection: $menuSelection,
                handleSelectionChange: { selection in
                    handleSelectionChange(selection)
                    isShowingPopover = false
                },
                isShowingPopover: $isShowingPopover
            )
            .frame(width: 360, height: 400)
        }
    }
    
    // Helper function to get model image based on ID
    private func getModelImage(for modelId: String) -> Image {
        ModelImageHelper.getImage(for: modelId)
    }
}

// MARK: - ModelSelectorPopoverContent
struct ModelSelectorPopoverContent: View {
    let organizedChatModels: [String: [ChatModel]]
    @Binding var searchText: String
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    @Binding var isShowingPopover: Bool
    @ObservedObject private var settingManager = SettingManager.shared
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation {
                            searchText = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.opacity)
                }
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Enhanced model list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Favorites section
                    if !filteredFavorites.isEmpty {
                        SectionHeader(title: "Favorites")
                        
                        ForEach(filteredFavorites, id: \.id) { model in
                            EnhancedModelRowView(
                                model: model,
                                isSelected: isModelSelected(model),
                                isFavorite: true,
                                toggleFavorite: {
                                    settingManager.toggleFavoriteModel(model.id)
                                },
                                selectModel: {
                                    selectModel(model)
                                }
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                    }
                    
                    // Providers by section
                    ForEach(filteredProviders, id: \.self) { provider in
                        SectionHeader(title: provider)
                        
                        ForEach(filteredModelsByProvider[provider] ?? [], id: \.id) { model in
                            EnhancedModelRowView(
                                model: model,
                                isSelected: isModelSelected(model),
                                isFavorite: settingManager.isModelFavorite(model.id),
                                toggleFavorite: {
                                    settingManager.toggleFavoriteModel(model.id)
                                },
                                selectModel: {
                                    selectModel(model)
                                }
                            )
                        }
                        
                        if provider != filteredProviders.last {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // No results state
                    if filteredProviders.isEmpty && filteredFavorites.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                            
                            Text("No models found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Try a different search term")
                                .font(.subheadline)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            // Focus search field when popover appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    // Helper methods
    private func isModelSelected(_ model: ChatModel) -> Bool {
        if case let .chat(selectedModel) = menuSelection {
            return selectedModel.id == model.id
        }
        return false
    }
    
    private func selectModel(_ model: ChatModel) {
        menuSelection = .chat(model)
        handleSelectionChange(menuSelection)
    }
    
    // Filtering methods
    private var filteredModelsByProvider: [String: [ChatModel]] {
        var result: [String: [ChatModel]] = [:]
        
        for (provider, models) in organizedChatModels {
            let filteredModels = models.filter { model in
                searchText.isEmpty ||
                model.name.localizedCaseInsensitiveContains(searchText) ||
                model.id.localizedCaseInsensitiveContains(searchText) ||
                provider.localizedCaseInsensitiveContains(searchText)
            }
            
            if !filteredModels.isEmpty {
                result[provider] = filteredModels
            }
        }
        
        return result
    }
    
    private var filteredProviders: [String] {
        return filteredModelsByProvider.keys.sorted()
    }
    
    private var filteredFavorites: [ChatModel] {
        var favorites: [ChatModel] = []
        
        for models in organizedChatModels.values {
            for model in models {
                if settingManager.isModelFavorite(model.id) &&
                    (searchText.isEmpty ||
                     model.name.localizedCaseInsensitiveContains(searchText) ||
                     model.id.localizedCaseInsensitiveContains(searchText)) {
                    favorites.append(model)
                }
            }
        }
        
        return favorites
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }
}

struct EnhancedModelRowView: View {
    let model: ChatModel
    let isSelected: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let selectModel: () -> Void
    
    @State private var isHovering = false
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            ModelImageHelper.getImage(for: model.id)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                
                Text(model.id)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering || isFavorite ? 1.0 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ?
                      Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.1) :
                        (isHovering ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture(perform: selectModel)
    }
}

// MARK: - Model Image Helper
struct ModelImageHelper {
    static func getImage(for modelId: String) -> Image {
        switch modelId.lowercased() {
        case let id where id.contains("anthropic"):
            return Image("anthropic")
        case let id where id.contains("meta"):
            return Image("meta")
        case let id where id.contains("cohere"):
            return Image("cohere")
        case let id where id.contains("mistral"):
            return Image("mistral")
        case let id where id.contains("ai21"):
            return Image("AI21")
        case let id where id.contains("amazon"):
            return Image("amazon")
        case let id where id.contains("deepseek"):
            return Image("deepseek")
        case let id where id.contains("stability"):
            return Image("stability ai")
        case let id where id.contains("openai"):
            return Image("openai")
        default:
            return Image("bedrock")
        }
    }
}
