import AppKit
import SwiftUI

struct ModelPicker: View {
    let organizedChatModels: [String: [ChatModel]]
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    @State private var isShowingPopover = false
    @State private var hovering = false
    private var selectedModel: ChatModel? {
        if case .chat(let model) = menuSelection { return model }
        return nil
    }

    var body: some View {
        Button { isShowingPopover.toggle() } label: {
            HStack(spacing: 8) {
                if let model = selectedModel, !model.id.isEmpty {
                    ModelImageHelper.getImage(for: model.id)
                        .resizable().scaledToFit().frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(selectedModel?.name.isEmpty == false ? selectedModel!.name : "Select model")
                    .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isShowingPopover ? 180 : 0))
            }
            .padding(.horizontal, 8).frame(height: DesignTokens.controlSize)
            .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help("Choose a Bedrock model")
        .accessibilityLabel("Model: \(selectedModel?.name ?? "Select model")")
        .accessibilityIdentifier("modelPicker.button")
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            ModelSelectorPopoverContent(models: organizedChatModels.values.flatMap { $0 }, selectedID: selectedModel?.id) { id in
                let model = organizedChatModels.values.lazy.flatMap { $0 }.first { $0.id == id } ?? ModelCatalog.shared.model(id)
                let selection = SidebarSelection.chat(model)
                menuSelection = selection
                handleSelectionChange(selection)
                isShowingPopover = false
            } close: { isShowingPopover = false }
        }
    }
}

private struct ModelSelectorPopoverContent: View {
    let models: [ChatModel]
    let selectedID: String?
    let select: (String) -> Void
    let close: () -> Void
    @ObservedObject private var settings = PreferencesStore.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var focusedID: String?
    @State private var hoveredID: String?
    @State private var choices: [BedrockModelChoice] = []
    @FocusState private var searchFocused: Bool
    private var visible: [BedrockModelChoice] { choices.filter { $0.matches(query) } }

    var body: some View {
        let rows = visible
        let favorites = rows.filter(\.isFavorite)
        let others = rows.filter { !$0.isFavorite }
        let providers = Array(Set(others.map(\.provider))).sorted()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
                TextField("Search models…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                    .onSubmit { if let row = rows.first(where: { $0.id == focusedID }) ?? rows.first { select(row.preferredID) } }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .accessibilityIdentifier("modelPicker.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear model search")
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
            Divider()
            if rows.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No models found", detail: "Try a different search term.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !favorites.isEmpty {
                                sectionHeader("Favorites")
                                ForEach(favorites) { row in modelRow(row).id(row.id) }
                                if !others.isEmpty { Divider().padding(.vertical, 8) }
                            }
                            ForEach(providers, id: \.self) { provider in
                                sectionHeader(provider)
                                ForEach(others.filter { $0.provider == provider }) { row in modelRow(row).id(row.id) }
                                if provider != providers.last { Divider().padding(.vertical, 8) }
                            }
                        }.padding(.bottom, 8)
                    }
                    .onChange(of: focusedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
        .frame(width: 360, height: 400)
        .onAppear { rebuild() }
        .task { await Task.yield(); searchFocused = true }
        .onChange(of: catalog.descriptors) { _, _ in rebuild() }
        .onChange(of: settings.favoriteModelIds) { _, _ in rebuild() }
        .onChange(of: query) { _, _ in focusedID = visible.first?.id }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modelPicker.popover")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    private func modelRow(_ row: BedrockModelChoice) -> some View {
        let selected = row.variants.contains { $0.id == selectedID }
        return HStack(spacing: 0) {
            Button { select(row.preferredID) } label: {
                HStack(spacing: 8) {
                    ModelImageHelper.getImage(for: row.preferredID)
                        .resizable().scaledToFit().frame(width: 38, height: 38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(row.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                            if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DesignTokens.accent) }
                        }
                        Text(row.preferredID).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                }.padding(.leading, 12).padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(row.preferredID)
            .accessibilityLabel("Select \(row.name)")
            .accessibilityIdentifier("modelPicker.row.\(row.id)")
            Button {
                if row.isFavorite {
                    for variant in row.variants where settings.isModelFavorite(variant.id) { settings.toggleFavoriteModel(variant.id) }
                } else { settings.toggleFavoriteModel(row.preferredID) }
            } label: {
                Image(systemName: row.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12)).foregroundStyle(row.isFavorite ? Color.primary : Color.secondary)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.trailing, 6)
            .help(row.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel("\(row.isFavorite ? "Unfavorite" : "Favorite") \(row.name)")
        }
        .background(selected ? DesignTokens.accent.opacity(colorScheme == .dark ? 0.18 : 0.09) :
                    Color.primary.opacity(hoveredID == row.id || focusedID == row.id ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? DesignTokens.accent.opacity(0.25) : .clear, lineWidth: 0.5))
        .onHover { hoveredID = $0 ? row.id : nil }
        .contextMenu {
            if row.variants.count > 1 {
                Section("Inference route") {
                    ForEach(row.variants) { variant in
                        Button { select(variant.id) } label: {
                            if variant.id == selectedID { Label(BedrockModelChoice.variantTitle(variant), systemImage: "checkmark") }
                            else { Text(BedrockModelChoice.variantTitle(variant)) }
                        }.help(variant.id)
                    }
                }
            }
            Button("Copy model ID") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.preferredID, forType: .string)
            }
            Button("Use by default") { settings.defaultModelId = row.preferredID }
        }
    }

    private func rebuild() {
        let entries = models.map { model in
            catalog.descriptor(model.id) ?? BedrockModelDescriptor(id: model.id, name: model.name, provider: model.provider,
                inputModalities: [], outputModalities: [], inferenceTypes: [], streaming: nil)
        }
        choices = BedrockModelChoice.make(descriptors: entries, selectedID: selectedID,
                                          favoriteIDs: Set(settings.favoriteModelIds), region: settings.selectedRegion.rawValue)
        if focusedID == nil { focusedID = choices.first { $0.variants.contains { $0.id == selectedID } }?.id }
    }
    private func move(_ delta: Int) {
        let rows = visible
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == focusedID } ?? (delta > 0 ? -1 : rows.count)
        focusedID = rows[min(max(0, current + delta), rows.count - 1)].id
    }
}

// MARK: - Model Image Helper
struct ModelImageHelper {
    static func getImage(for modelId: String) -> Image {
        switch modelId.lowercased() {
        case let id where id.contains("anthropic"):
            return Image("ProviderAnthropic")
        case let id where id.contains("meta"):
            return Image("ProviderMeta")
        case let id where id.contains("cohere"):
            return Image("ProviderCohere")
        case let id where id.contains("mistral"):
            return Image("ProviderMistral")
        case let id where id.contains("ai21"):
            return Image("ProviderAI21")
        case let id where id.contains("amazon"):
            return Image("ProviderAmazon")
        case let id where id.contains("deepseek"):
            return Image("ProviderDeepSeek")
        case let id where id.contains("stability"):
            return Image("ProviderStability")
        case let id where id.contains("openai"):
            return Image("ProviderOpenAI")
        case let id where id.contains("qwen"):
            return Image("ProviderQwen")
        case let id where id.contains("writer"):
            return Image("ProviderWriter")
        case let id where id.contains("twelvelabs"):
            return Image("ProviderTwelveLabs")
        case let id where id.contains("moonshot"):
            return Image("ProviderMoonshot")
        case let id where id.contains("luma"):
            return Image(systemName: "video")
        case let id where id.contains("nvidia"):
            return Image("ProviderNVIDIA")
        case let id where id.contains("gemma"), let id where id.contains("google"):
            return Image("ProviderGemma")
        case let id where id.contains("minimax"):
            return Image("ProviderMiniMax")
        default:
            return Image(systemName: "cpu")
        }
    }
}

// MARK: - Liquid Glass Dropdown Modifier (macOS 26+ transparent, earlier versions with border)
struct LiquidGlassDropdownModifier: ViewModifier {
    let isHovering: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Transparent, no border
            content
        } else {
            // macOS 25 and earlier: Show border and background
            content
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ?
                              Color(NSColor.controlBackgroundColor).opacity(0.8) :
                              Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isHovering ? DesignTokens.accent.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
                )
        }
    }
}
