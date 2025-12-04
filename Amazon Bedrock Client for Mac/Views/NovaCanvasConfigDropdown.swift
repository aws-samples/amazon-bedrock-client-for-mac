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
        case .textToImage: return "Generate image from text prompt"
        case .colorGuidedGeneration: return "Generate with specific color palette"
        case .imageVariation: return "Create variations of existing images"
        case .inpainting: return "Edit specific areas within an image"
        case .outpainting: return "Extend image beyond its borders"
        case .backgroundRemoval: return "Remove background automatically"
        }
    }
    
    var requiresMask: Bool {
        switch self {
        case .inpainting, .outpainting: return true
        default: return false
        }
    }
}

// MARK: - Nova Canvas Config Dropdown
struct NovaCanvasConfigDropdown: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowingPopover.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                
                Text("Canvas")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ?
                          Color.blue.opacity(0.15) :
                          Color.blue.opacity(0.1))
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
            NovaCanvasConfigPopoverContent()
                .frame(width: 380, height: 480)
        }
    }
}

// MARK: - Popover Content
struct NovaCanvasConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTaskType: NovaCanvasTaskType = .textToImage
    @State private var width: Int = 1024
    @State private var height: Int = 1024
    @State private var quality: String = "standard"
    @State private var cfgScale: Float = 8.0
    @State private var numberOfImages: Int = 1
    @State private var negativePrompt: String = ""
    
    // Preset sizes
    private let presetSizes: [(String, Int, Int)] = [
        ("Square (1024×1024)", 1024, 1024),
        ("Landscape (1280×720)", 1280, 720),
        ("Portrait (720×1280)", 720, 1280),
        ("Wide (1536×640)", 1536, 640),
        ("Tall (640×1536)", 640, 1536),
        ("HD (1920×1080)", 1920, 1080),
        ("2K (2048×2048)", 2048, 2048),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    taskTypeSection
                    sizeSection
                    qualitySection
                    generationSection
                    negativePromptSection
                }
                .padding(16)
            }
        }
        .onAppear { loadConfig() }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nova Canvas Settings")
                    .font(.system(size: 14, weight: .semibold))
                Text("Configure image generation")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Reset") { resetToDefaults() }
                .font(.system(size: 12))
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.8))
    }
    
    // MARK: - Task Type Section
    private var taskTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Type")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(NovaCanvasTaskType.allCases) { taskType in
                    TaskTypeButton(
                        taskType: taskType,
                        isSelected: selectedTaskType == taskType,
                        action: { selectedTaskType = taskType; saveConfig() }
                    )
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text(selectedTaskType.taskDescription)
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
            .padding(.top, 4)
            
            if selectedTaskType.requiresInputImage {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 11))
                    Text("Requires input image")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Size Section
    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Size")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("Preset", selection: Binding(
                get: { "\(width)×\(height)" },
                set: { _ in }
            )) {
                ForEach(presetSizes, id: \.0) { preset in
                    Text(preset.0).tag("\(preset.1)×\(preset.2)")
                }
            }
            .pickerStyle(.menu)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width").font(.system(size: 10)).foregroundColor(.secondary)
                    TextField("Width", value: $width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: width) { _, _ in saveConfig() }
                }
                
                Text("×").foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height").font(.system(size: 10)).foregroundColor(.secondary)
                    TextField("Height", value: $height, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: height) { _, _ in saveConfig() }
                }
                
                Spacer()
                
                Text(aspectRatioText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            
            if !isValidSize {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text("Size must be 320-4096px, divisible by 16, max 4.19M pixels").font(.system(size: 10))
                }
                .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Quality Section
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("Quality", selection: $quality) {
                Text("Standard").tag("standard")
                Text("Premium").tag("premium")
            }
            .pickerStyle(.segmented)
            .onChange(of: quality) { _, _ in saveConfig() }
        }
    }
    
    // MARK: - Generation Section
    private var generationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generation Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CFG Scale").font(.system(size: 11))
                    Spacer()
                    Text(String(format: "%.1f", cfgScale))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $cfgScale, in: 1.0...20.0, step: 0.5)
                    .onChange(of: cfgScale) { _, _ in saveConfig() }
            }
            
            HStack {
                Text("Number of Images").font(.system(size: 11))
                Spacer()
                Stepper("\(numberOfImages)", value: $numberOfImages, in: 1...4)
                    .onChange(of: numberOfImages) { _, _ in saveConfig() }
            }
        }
    }
    
    // MARK: - Negative Prompt Section
    private var negativePromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Negative Prompt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            TextEditor(text: $negativePrompt)
                .font(.system(size: 12))
                .frame(height: 60)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: negativePrompt) { _, _ in saveConfig() }
            
            Text("Describe what you don't want in the image")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helpers
    private var aspectRatioText: String {
        let g = gcd(width, height)
        return "\(width/g):\(height/g)"
    }
    
    private var isValidSize: Bool {
        width >= 320 && width <= 4096 &&
        height >= 320 && height <= 4096 &&
        width % 16 == 0 && height % 16 == 0 &&
        width * height <= 4_194_304 &&
        Double(max(width, height)) / Double(min(width, height)) <= 4.0
    }
    
    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
    
    private func loadConfig() {
        let config = settingManager.novaCanvasConfig
        selectedTaskType = NovaCanvasTaskType(rawValue: config.taskType) ?? .textToImage
        width = config.width
        height = config.height
        quality = config.quality
        cfgScale = config.cfgScale
        numberOfImages = config.numberOfImages
        negativePrompt = config.negativePrompt
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
            outpaintingMode: settingManager.novaCanvasConfig.outpaintingMode
        )
    }
    
    private func resetToDefaults() {
        let defaults = NovaCanvasConfig.defaultConfig
        selectedTaskType = NovaCanvasTaskType(rawValue: defaults.taskType) ?? .textToImage
        width = defaults.width
        height = defaults.height
        quality = defaults.quality
        cfgScale = defaults.cfgScale
        numberOfImages = defaults.numberOfImages
        negativePrompt = defaults.negativePrompt
        saveConfig()
    }
}

// MARK: - Task Type Button
struct TaskTypeButton: View {
    let taskType: NovaCanvasTaskType
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: taskType.icon)
                    .font(.system(size: 12))
                Text(taskType.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ?
                          Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.15) :
                          Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isSelected ? .blue : .primary)
        }
        .buttonStyle(.plain)
    }
}
