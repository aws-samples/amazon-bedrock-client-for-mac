//
//  StabilityAIConfigDropdown.swift
//  Amazon Bedrock Client for Mac
//
//  Created for Stability AI (Stable Diffusion) configuration
//

import SwiftUI

// MARK: - Stability AI Config Dropdown
struct StabilityAIConfigDropdown: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedTaskType: StabilityAITaskType {
        StabilityAITaskType(rawValue: settingManager.stabilityAIConfig.taskType) ?? .textToImage
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
                    .foregroundColor(.purple)
                
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
            .modifier(ImageConfigDropdownModifier(isHovering: isHovering, colorScheme: colorScheme, accentColor: .purple))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            StabilityAIConfigPopoverContent(isShowingPopover: $isShowingPopover)
                .frame(width: 320, height: 400)
        }
    }
}

// MARK: - Popover Content
struct StabilityAIConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @Binding var isShowingPopover: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTaskType: StabilityAITaskType = .textToImage
    @State private var aspectRatio: StabilityAIAspectRatio = .ratio1_1
    @State private var stylePreset: StabilityAIStylePreset = .none
    @State private var negativePrompt: String = ""
    @State private var seed: Int = 0
    @State private var cfgScale: Float = 10.0
    @State private var steps: Int = 50
    @State private var strength: Float = 0.35
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Stability AI Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset") { resetToDefaults() }
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Task Types
                    ImageConfigSectionHeader(title: "Task Type")
                    
                    ForEach(StabilityAITaskType.allCases) { taskType in
                        ImageTaskTypeRow(
                            icon: taskType.icon,
                            name: taskType.displayName,
                            description: taskType.taskDescription,
                            isSelected: selectedTaskType == taskType,
                            requiresImage: taskType.requiresInputImage,
                            accentColor: .purple
                        ) {
                            selectedTaskType = taskType
                            saveConfig()
                        }
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // Aspect Ratio (text-to-image only)
                    if selectedTaskType == .textToImage {
                        ImageConfigSectionHeader(title: "Aspect Ratio")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(StabilityAIAspectRatio.allCases, id: \.self) { ratio in
                                    AspectRatioButton(
                                        label: ratio.displayName,
                                        isSelected: aspectRatio == ratio,
                                        color: .purple
                                    ) {
                                        aspectRatio = ratio
                                        saveConfig()
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(.bottom, 8)
                        
                        Divider().padding(.vertical, 8)
                    }
                    
                    // Strength (image-to-image only)
                    if selectedTaskType == .imageToImage {
                        ImageConfigSectionHeader(title: "Transformation Strength")
                        
                        HStack {
                            Text(String(format: "%.2f", strength))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                            Slider(value: $strength, in: 0.0...1.0, step: 0.05)
                                .onChange(of: strength) { _, _ in saveConfig() }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                        
                        Text("0 = Keep original, 1 = Full transformation")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        
                        Divider().padding(.vertical, 8)
                    }
                    
                    // Style Preset
                    ImageConfigSectionHeader(title: "Style Preset")
                    
                    Picker("", selection: $stylePreset) {
                        ForEach(StabilityAIStylePreset.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .onChange(of: stylePreset) { _, _ in saveConfig() }
                    
                    Divider().padding(.vertical, 8)
                    
                    // Settings
                    ImageConfigSectionHeader(title: "Settings")
                    
                    VStack(spacing: 12) {
                        // CFG Scale
                        HStack {
                            Text("CFG Scale").font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.1f", cfgScale))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                            Slider(value: $cfgScale, in: 1.0...35.0, step: 0.5)
                                .frame(width: 100)
                                .onChange(of: cfgScale) { _, _ in saveConfig() }
                        }
                        
                        // Steps
                        HStack {
                            Text("Steps").font(.system(size: 12))
                            Spacer()
                            Text("\(steps)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                            Slider(value: Binding(
                                get: { Float(steps) },
                                set: { steps = Int($0) }
                            ), in: 10...150, step: 5)
                                .frame(width: 100)
                                .onChange(of: steps) { _, _ in saveConfig() }
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
                                    .foregroundColor(seed == 0 ? .purple : .secondary)
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
        let config = settingManager.stabilityAIConfig
        selectedTaskType = StabilityAITaskType(rawValue: config.taskType) ?? .textToImage
        aspectRatio = StabilityAIAspectRatio(rawValue: config.aspectRatio) ?? .ratio1_1
        stylePreset = StabilityAIStylePreset(rawValue: config.stylePreset) ?? .none
        negativePrompt = config.negativePrompt
        seed = config.seed
        cfgScale = config.cfgScale
        steps = config.steps
        strength = config.strength
    }
    
    private func saveConfig() {
        settingManager.stabilityAIConfig = StabilityAIConfig(
            taskType: selectedTaskType.rawValue,
            aspectRatio: aspectRatio.rawValue,
            stylePreset: stylePreset.rawValue,
            negativePrompt: negativePrompt,
            seed: seed,
            cfgScale: cfgScale,
            steps: steps,
            strength: strength
        )
    }
    
    private func resetToDefaults() {
        let defaults = StabilityAIConfig.defaultConfig
        selectedTaskType = StabilityAITaskType(rawValue: defaults.taskType) ?? .textToImage
        aspectRatio = StabilityAIAspectRatio(rawValue: defaults.aspectRatio) ?? .ratio1_1
        stylePreset = StabilityAIStylePreset(rawValue: defaults.stylePreset) ?? .none
        negativePrompt = defaults.negativePrompt
        seed = defaults.seed
        cfgScale = defaults.cfgScale
        steps = defaults.steps
        strength = defaults.strength
        saveConfig()
    }
}

// Shared components moved to SharedImageConfigComponents.swift
