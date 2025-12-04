//
//  TitanImageConfigDropdown.swift
//  Amazon Bedrock Client for Mac
//
//  Created for Titan Image Generator configuration
//

import SwiftUI

// MARK: - Titan Image Config Dropdown
struct TitanImageConfigDropdown: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedTaskType: TitanImageTaskType {
        TitanImageTaskType(rawValue: settingManager.titanImageConfig.taskType) ?? .textToImage
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
                    .foregroundColor(.blue)
                
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
            .modifier(ImageConfigDropdownModifier(isHovering: isHovering, colorScheme: colorScheme, accentColor: .blue))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            TitanImageConfigPopoverContent(isShowingPopover: $isShowingPopover)
                .frame(width: 320, height: 380)
        }
    }
}

// MARK: - Popover Content
struct TitanImageConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @Binding var isShowingPopover: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTaskType: TitanImageTaskType = .textToImage
    @State private var width: Int = 1024
    @State private var height: Int = 1024
    @State private var quality: String = "standard"
    @State private var cfgScale: Float = 8.0
    @State private var numberOfImages: Int = 1
    @State private var maskPrompt: String = ""
    @State private var seed: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Titan Image Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset") { resetToDefaults() }
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Task Types
                    TitanSectionHeader(title: "Task Type")
                    
                    ForEach(TitanImageTaskType.allCases, id: \.rawValue) { taskType in
                        TitanTaskTypeRow(
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
                    TitanSectionHeader(title: "Output Size")
                    
                    HStack(spacing: 12) {
                        TitanSizeField(label: "W", value: $width, onChange: saveConfig)
                        Text("×").foregroundColor(.secondary)
                        TitanSizeField(label: "H", value: $height, onChange: saveConfig)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    // Quick presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            TitanSizePresetButton(label: "1:1", w: 1024, h: 1024, currentW: width, currentH: height) {
                                width = 1024; height = 1024; saveConfig()
                            }
                            TitanSizePresetButton(label: "3:2", w: 1152, h: 768, currentW: width, currentH: height) {
                                width = 1152; height = 768; saveConfig()
                            }
                            TitanSizePresetButton(label: "2:3", w: 768, h: 1152, currentW: width, currentH: height) {
                                width = 768; height = 1152; saveConfig()
                            }
                            TitanSizePresetButton(label: "16:9", w: 1173, h: 640, currentW: width, currentH: height) {
                                width = 1173; height = 640; saveConfig()
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 8)
                    
                    // Mask Prompt (for inpainting/outpainting)
                    if selectedTaskType == .inpainting || selectedTaskType == .outpainting {
                        Divider().padding(.vertical, 8)
                        TitanSectionHeader(title: "Mask Prompt")
                        
                        TextField("e.g., the sky, the background", text: $maskPrompt)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                            .onChange(of: maskPrompt) { _, _ in saveConfig() }
                        
                        Text("Describe what to mask")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // Settings
                    TitanSectionHeader(title: "Settings")
                    
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
                            Slider(value: $cfgScale, in: 1.1...10.0, step: 0.5)
                                .frame(width: 100)
                                .onChange(of: cfgScale) { _, _ in saveConfig() }
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
                                    .foregroundColor(seed == 0 ? .blue : .secondary)
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
    
    private func loadConfig() {
        let config = settingManager.titanImageConfig
        selectedTaskType = TitanImageTaskType(rawValue: config.taskType) ?? .textToImage
        width = config.width
        height = config.height
        quality = config.quality
        cfgScale = config.cfgScale
        numberOfImages = config.numberOfImages
        maskPrompt = config.maskPrompt
        seed = config.seed
    }
    
    private func saveConfig() {
        settingManager.titanImageConfig = TitanImageConfig(
            taskType: selectedTaskType.rawValue,
            width: width,
            height: height,
            quality: quality,
            cfgScale: cfgScale,
            numberOfImages: numberOfImages,
            negativePrompt: settingManager.titanImageConfig.negativePrompt,
            similarityStrength: settingManager.titanImageConfig.similarityStrength,
            outpaintingMode: settingManager.titanImageConfig.outpaintingMode,
            maskPrompt: maskPrompt,
            seed: seed
        )
    }
    
    private func resetToDefaults() {
        let defaults = TitanImageConfig.defaultConfig
        selectedTaskType = TitanImageTaskType(rawValue: defaults.taskType) ?? .textToImage
        width = defaults.width
        height = defaults.height
        quality = defaults.quality
        cfgScale = defaults.cfgScale
        numberOfImages = defaults.numberOfImages
        maskPrompt = defaults.maskPrompt
        seed = defaults.seed
        saveConfig()
    }
}


// MARK: - Titan Task Type Row
struct TitanTaskTypeRow: View {
    let taskType: TitanImageTaskType
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: taskType.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(taskType.displayName)
                        .font(.system(size: 13, weight: .medium))
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                
                Text(taskType.taskDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if taskType.requiresInputImage {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(Color.blue.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ?
                      Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08) :
                        (isHovering ? Color.gray.opacity(0.08) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Titan Size Field
struct TitanSizeField: View {
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

// MARK: - Titan Size Preset Button
struct TitanSizePresetButton: View {
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
                        .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .foregroundColor(isSelected ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Titan Section Header
struct TitanSectionHeader: View {
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

// MARK: - Titan Dropdown Modifier
struct TitanDropdownModifier: ViewModifier {
    let isHovering: Bool
    let colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content
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
    }
}
