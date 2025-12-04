//
//  NovaCanvasConfigDropdown.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 12/4/25.
//

import SwiftUI

// MARK: - Nova Canvas Task Type UI Extensions
extension NovaCanvasTaskType: Identifiable {
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .textToImage: return "text.below.photo"
        case .colorGuidedGeneration: return "paintpalette"
        case .imageVariation: return "photo.on.rectangle"
        case .inpainting: return "paintbrush.pointed"
        case .outpainting: return "arrow.up.left.and.arrow.down.right"
        case .backgroundRemoval: return "person.crop.rectangle"
        }
    }
    
    var taskDescription: String {
        switch self {
        case .textToImage: return "Generate image from text"
        case .colorGuidedGeneration: return "Generate with color palette"
        case .imageVariation: return "Create variations"
        case .inpainting: return "Edit areas within image"
        case .outpainting: return "Extend image borders"
        case .backgroundRemoval: return "Remove background"
        }
    }
    
    var requiresMask: Bool {
        switch self {
        case .inpainting, .outpainting: return true
        default: return false
        }
    }
}

// MARK: - Nova Canvas Config Dropdown (ModelSelectorDropdown style)
struct NovaCanvasConfigDropdown: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedTaskType: NovaCanvasTaskType {
        NovaCanvasTaskType(rawValue: settingManager.novaCanvasConfig.taskType) ?? .textToImage
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowingPopover.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: selectedTaskType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                
                Text(selectedTaskType.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(isShowingPopover ? Angle(degrees: 180) : Angle(degrees: 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowingPopover)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .modifier(NovaCanvasDropdownModifier(isHovering: isHovering, colorScheme: colorScheme))
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
            NovaCanvasConfigPopoverContent(isShowingPopover: $isShowingPopover)
                .frame(width: 340, height: 500)
        }
    }
}

// MARK: - Popover Content (ModelSelectorPopoverContent style)
struct NovaCanvasConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @Binding var isShowingPopover: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTaskType: NovaCanvasTaskType = .textToImage
    @State private var selectedStyle: NovaCanvasStyle = .none
    @State private var width: Int = 1024
    @State private var height: Int = 1024
    @State private var quality: String = "standard"
    @State private var cfgScale: Float = 8.0
    @State private var numberOfImages: Int = 1
    @State private var negativePrompt: String = ""
    @State private var maskPrompt: String = ""
    @State private var seed: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Canvas Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset") { resetToDefaults() }
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Task Types Section
                    NovaCanvasSectionHeader(title: "Task Type")
                    
                    ForEach(NovaCanvasTaskType.allCases) { taskType in
                        TaskTypeRow(
                            taskType: taskType,
                            isSelected: selectedTaskType == taskType,
                            onSelect: {
                                selectedTaskType = taskType
                                saveConfig()
                            }
                        )
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // Size Section
                    NovaCanvasSectionHeader(title: "Output Size")
                    
                    HStack(spacing: 12) {
                        SizeField(label: "W", value: $width, onChange: saveConfig)
                        Text("×").foregroundColor(.secondary)
                        SizeField(label: "H", value: $height, onChange: saveConfig)
                        Spacer()
                        Text(aspectRatioText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    // Quick size presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            SizePresetButton(label: "1:1", w: 1024, h: 1024, currentW: width, currentH: height) {
                                width = 1024; height = 1024; saveConfig()
                            }
                            SizePresetButton(label: "16:9", w: 1280, h: 720, currentW: width, currentH: height) {
                                width = 1280; height = 720; saveConfig()
                            }
                            SizePresetButton(label: "9:16", w: 720, h: 1280, currentW: width, currentH: height) {
                                width = 720; height = 1280; saveConfig()
                            }
                            SizePresetButton(label: "4:3", w: 1024, h: 768, currentW: width, currentH: height) {
                                width = 1024; height = 768; saveConfig()
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 8)
                    
                    Divider().padding(.vertical, 8)
                    
                    // Style (only for text-to-image)
                    if selectedTaskType == .textToImage {
                        NovaCanvasSectionHeader(title: "Style")
                        
                        Picker("", selection: $selectedStyle) {
                            ForEach(NovaCanvasStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .onChange(of: selectedStyle) { _, _ in saveConfig() }
                        
                        Divider().padding(.vertical, 8)
                        
                        // Negative Prompt
                        NovaCanvasSectionHeader(title: "Negative Prompt")
                        
                        TextField("What to exclude from the image...", text: $negativePrompt)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                            .onChange(of: negativePrompt) { _, _ in saveConfig() }
                        
                        Text("Describe what you don't want in the image")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        
                        Divider().padding(.vertical, 8)
                    }
                    
                    // Mask Prompt (for inpainting/outpainting)
                    if selectedTaskType == .inpainting || selectedTaskType == .outpainting {
                        NovaCanvasSectionHeader(title: "Mask Prompt")
                        
                        TextField("e.g., the sky, the person's shirt", text: $maskPrompt)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                            .onChange(of: maskPrompt) { _, _ in saveConfig() }
                        
                        Text("Describe what to mask (instead of drawing)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        
                        Divider().padding(.vertical, 8)
                    }
                    
                    // Quality & Settings
                    NovaCanvasSectionHeader(title: "Settings")
                    
                    VStack(spacing: 12) {
                        // Quality
                        HStack {
                            Text("Quality").font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $quality) {
                                Text("Standard").tag("standard")
                                Text("Premium").tag("premium")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            .onChange(of: quality) { _, _ in saveConfig() }
                        }
                        
                        // CFG Scale
                        HStack {
                            Text("CFG Scale").font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.1f", cfgScale))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                            Slider(value: $cfgScale, in: 1.0...20.0, step: 0.5)
                                .frame(width: 100)
                                .onChange(of: cfgScale) { _, _ in saveConfig() }
                        }
                        
                        // Number of images
                        HStack {
                            Text("Images").font(.system(size: 12))
                            Spacer()
                            Stepper("\(numberOfImages)", value: $numberOfImages, in: 1...4)
                                .onChange(of: numberOfImages) { _, _ in saveConfig() }
                        }
                        
                        // Seed
                        HStack {
                            Text("Seed").font(.system(size: 12))
                            Spacer()
                            TextField("", value: $seed, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: seed) { _, _ in saveConfig() }
                            Button(action: { seed = 0; saveConfig() }) {
                                Image(systemName: "dice")
                                    .font(.system(size: 12))
                                    .foregroundColor(seed == 0 ? .orange : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("0 = Random seed")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear { loadConfig() }
    }
    
    // MARK: - Helpers
    private var aspectRatioText: String {
        let g = gcd(width, height)
        return "\(width/g):\(height/g)"
    }
    
    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
    
    private func loadConfig() {
        let config = settingManager.novaCanvasConfig
        selectedTaskType = NovaCanvasTaskType(rawValue: config.taskType) ?? .textToImage
        selectedStyle = NovaCanvasStyle(rawValue: config.style) ?? .none
        width = config.width
        height = config.height
        quality = config.quality
        cfgScale = config.cfgScale
        numberOfImages = config.numberOfImages
        negativePrompt = config.negativePrompt
        maskPrompt = config.maskPrompt
        seed = config.seed
    }
    
    private func saveConfig() {
        settingManager.novaCanvasConfig = NovaCanvasConfig(
            taskType: selectedTaskType.rawValue,
            width: width,
            height: height,
            quality: quality,
            cfgScale: cfgScale,
            numberOfImages: numberOfImages,
            negativePrompt: negativePrompt,
            similarityStrength: settingManager.novaCanvasConfig.similarityStrength,
            outpaintingMode: settingManager.novaCanvasConfig.outpaintingMode,
            style: selectedStyle.rawValue,
            maskPrompt: maskPrompt,
            seed: seed
        )
    }
    
    private func resetToDefaults() {
        let defaults = NovaCanvasConfig.defaultConfig
        selectedTaskType = NovaCanvasTaskType(rawValue: defaults.taskType) ?? .textToImage
        selectedStyle = .none
        width = defaults.width
        height = defaults.height
        quality = defaults.quality
        cfgScale = defaults.cfgScale
        numberOfImages = defaults.numberOfImages
        negativePrompt = defaults.negativePrompt
        maskPrompt = defaults.maskPrompt
        seed = defaults.seed
        saveConfig()
    }
}

// MARK: - Task Type Row (EnhancedModelRowView style)
struct TaskTypeRow: View {
    let taskType: NovaCanvasTaskType
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: taskType.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .orange : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                )
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(taskType.displayName)
                        .font(.system(size: 13, weight: .medium))
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.orange)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                
                Text(taskType.taskDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Input image indicator
            if taskType.requiresInputImage {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ?
                      Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08) :
                        (isHovering ? Color.gray.opacity(0.08) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Supporting Views
struct SizeField: View {
    let label: String
    @Binding var value: Int
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .onChange(of: value) { _, _ in onChange() }
        }
    }
}

struct SizePresetButton: View {
    let label: String
    let w: Int
    let h: Int
    let currentW: Int
    let currentH: Int
    let action: () -> Void
    
    private var isSelected: Bool { currentW == w && currentH == h }
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.orange.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .foregroundColor(isSelected ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nova Canvas Dropdown Modifier (macOS 26+ transparent, earlier versions with border)
struct NovaCanvasDropdownModifier: ViewModifier {
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
                                .stroke(isHovering ? Color.orange.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
                )
        }
    }
}

// MARK: - Nova Canvas Section Header
struct NovaCanvasSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}
