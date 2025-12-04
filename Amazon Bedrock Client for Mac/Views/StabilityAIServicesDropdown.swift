//
//  StabilityAIServicesDropdown.swift
//  Amazon Bedrock Client for Mac
//
//  Dropdown for Stability AI Image Services settings (based on selected model)
//

import SwiftUI

// MARK: - Stability AI Services Dropdown
struct StabilityAIServicesDropdown: View {
    let modelId: String  // Current model ID determines which service settings to show
    
    @ObservedObject private var settingManager = SettingManager.shared
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Determine service from model ID
    private var currentService: StabilityAIImageService? {
        StabilityAIImageService.allCases.first { modelId.contains($0.modelId) || $0.modelId == modelId }
    }
    
    var body: some View {
        if let service = currentService {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isShowingPopover.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: service.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    Text(service.displayName)
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
                .modifier(ServicesDropdownModifier(isHovering: isHovering, colorScheme: colorScheme))
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
                StabilityAIServiceSettingsPopover(service: service, isShowingPopover: $isShowingPopover)
                    .frame(width: 320, height: servicePopoverHeight(for: service))
            }
        }
    }
    
    private func servicePopoverHeight(for service: StabilityAIImageService) -> CGFloat {
        switch service {
        case .outpaint: return 380
        case .searchReplace, .searchRecolor: return 320
        case .creativeUpscale, .conservativeUpscale: return 320
        case .controlSketch, .controlStructure: return 300
        case .styleGuide: return 320
        case .styleTransfer: return 380
        case .inpaint: return 320
        case .erase: return 200
        default: return 180
        }
    }
}

// MARK: - Service Settings Popover (shows settings for specific service)
struct StabilityAIServiceSettingsPopover: View {
    let service: StabilityAIImageService
    @Binding var isShowingPopover: Bool
    
    @ObservedObject private var settingManager = SettingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var creativity: Float = 0.3
    @State private var controlStrength: Float = 0.7
    @State private var fidelity: Float = 0.5
    @State private var styleStrength: Float = 0.5
    @State private var compositionFidelity: Float = 0.9
    @State private var changeStrength: Float = 0.9
    @State private var growMask: Int = 5
    @State private var outpaintLeft: Int = 0
    @State private var outpaintRight: Int = 0
    @State private var outpaintUp: Int = 0
    @State private var outpaintDown: Int = 0
    @State private var searchPrompt: String = ""
    @State private var negativePrompt: String = ""
    @State private var stylePreset: String = ""
    @State private var aspectRatio: String = "1:1"
    @State private var seed: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: service.icon)
                    .foregroundColor(.green)
                Text(service.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset") { resetToDefaults() }
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Service description
            HStack {
                Text(service.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if service.requiresImage {
                    Label("Requires image", systemImage: "photo.badge.plus")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // Service-specific settings
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    serviceSpecificSettings
                    
                    Divider().padding(.vertical, 4)
                    
                    // Seed (common to most services)
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
                                .foregroundColor(seed == 0 ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("0 = Random seed")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear { loadConfig() }
    }
    
    @ViewBuilder
    private var serviceSpecificSettings: some View {
        switch service {
        case .creativeUpscale, .conservativeUpscale:
            VStack(alignment: .leading, spacing: 8) {
                Text("Creativity").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $creativity, in: 0.1...0.5, step: 0.05)
                        .onChange(of: creativity) { _, _ in saveConfig() }
                    Text(String(format: "%.2f", creativity))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                Text("Higher = more creative details")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Divider().padding(.vertical, 4)
                
                // Negative Prompt
                Text("Negative Prompt").font(.system(size: 12, weight: .medium))
                TextField("What to exclude...", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onChange(of: negativePrompt) { _, _ in saveConfig() }
                
                // Style Preset
                stylePresetPicker
            }
            
        case .outpaint:
            VStack(alignment: .leading, spacing: 8) {
                Text("Extend Directions (pixels)").font(.system(size: 12, weight: .medium))
                
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Up").font(.system(size: 11))
                        Slider(value: Binding(get: { Float(outpaintUp) }, set: { outpaintUp = Int($0) }), in: 0...2000, step: 100)
                            .onChange(of: outpaintUp) { _, _ in saveConfig() }
                        Text("\(outpaintUp)").font(.system(size: 10, design: .monospaced)).frame(width: 45)
                    }
                    GridRow {
                        Text("Down").font(.system(size: 11))
                        Slider(value: Binding(get: { Float(outpaintDown) }, set: { outpaintDown = Int($0) }), in: 0...2000, step: 100)
                            .onChange(of: outpaintDown) { _, _ in saveConfig() }
                        Text("\(outpaintDown)").font(.system(size: 10, design: .monospaced)).frame(width: 45)
                    }
                    GridRow {
                        Text("Left").font(.system(size: 11))
                        Slider(value: Binding(get: { Float(outpaintLeft) }, set: { outpaintLeft = Int($0) }), in: 0...2000, step: 100)
                            .onChange(of: outpaintLeft) { _, _ in saveConfig() }
                        Text("\(outpaintLeft)").font(.system(size: 10, design: .monospaced)).frame(width: 45)
                    }
                    GridRow {
                        Text("Right").font(.system(size: 11))
                        Slider(value: Binding(get: { Float(outpaintRight) }, set: { outpaintRight = Int($0) }), in: 0...2000, step: 100)
                            .onChange(of: outpaintRight) { _, _ in saveConfig() }
                        Text("\(outpaintRight)").font(.system(size: 10, design: .monospaced)).frame(width: 45)
                    }
                }
                
                Divider().padding(.vertical, 4)
                
                // Creativity for outpaint
                Text("Creativity").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $creativity, in: 0.1...1.0, step: 0.1)
                        .onChange(of: creativity) { _, _ in saveConfig() }
                    Text(String(format: "%.1f", creativity))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30)
                }
            }
            
        case .inpaint:
            VStack(alignment: .leading, spacing: 8) {
                Text("Grow Mask").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: Binding(get: { Float(growMask) }, set: { growMask = Int($0) }), in: 0...20, step: 1)
                        .onChange(of: growMask) { _, _ in saveConfig() }
                    Text("\(growMask)px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                Text("Expand mask edges for smoother blending")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Divider().padding(.vertical, 4)
                
                // Negative Prompt
                Text("Negative Prompt").font(.system(size: 12, weight: .medium))
                TextField("What to exclude...", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onChange(of: negativePrompt) { _, _ in saveConfig() }
                
                // Style Preset
                stylePresetPicker
            }
            
        case .erase:
            VStack(alignment: .leading, spacing: 8) {
                Text("Grow Mask").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: Binding(get: { Float(growMask) }, set: { growMask = Int($0) }), in: 0...20, step: 1)
                        .onChange(of: growMask) { _, _ in saveConfig() }
                    Text("\(growMask)px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                Text("Expand mask edges for smoother blending")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
        case .searchReplace, .searchRecolor:
            VStack(alignment: .leading, spacing: 8) {
                Text("Search For").font(.system(size: 12, weight: .medium))
                TextField("e.g., jacket, sky, car", text: $searchPrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onChange(of: searchPrompt) { _, _ in saveConfig() }
                Text(service == .searchReplace ? "Object to replace" : "Object to recolor")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Divider().padding(.vertical, 4)
                
                // Grow Mask
                Text("Grow Mask").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: Binding(get: { Float(growMask) }, set: { growMask = Int($0) }), in: 0...20, step: 1)
                        .onChange(of: growMask) { _, _ in saveConfig() }
                    Text("\(growMask)px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                
                // Negative Prompt
                Text("Negative Prompt").font(.system(size: 12, weight: .medium))
                TextField("What to exclude...", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onChange(of: negativePrompt) { _, _ in saveConfig() }
            }
            
        case .controlSketch, .controlStructure:
            VStack(alignment: .leading, spacing: 8) {
                Text("Control Strength").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $controlStrength, in: 0...1, step: 0.05)
                        .onChange(of: controlStrength) { _, _ in saveConfig() }
                    Text(String(format: "%.2f", controlStrength))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                Text("How much the input guides generation")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Divider().padding(.vertical, 4)
                
                // Negative Prompt
                Text("Negative Prompt").font(.system(size: 12, weight: .medium))
                TextField("What to exclude...", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onChange(of: negativePrompt) { _, _ in saveConfig() }
                
                // Style Preset
                stylePresetPicker
            }
            
        case .styleGuide:
            VStack(alignment: .leading, spacing: 8) {
                Text("Style Fidelity").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $fidelity, in: 0...1, step: 0.05)
                        .onChange(of: fidelity) { _, _ in saveConfig() }
                    Text(String(format: "%.2f", fidelity))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                Text("How closely to match reference style")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Divider().padding(.vertical, 4)
                
                // Aspect Ratio
                Text("Aspect Ratio").font(.system(size: 12, weight: .medium))
                Picker("", selection: $aspectRatio) {
                    ForEach(StabilityAIAspectRatio.allCases, id: \.rawValue) { ratio in
                        Text(ratio.displayName).tag(ratio.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: aspectRatio) { _, _ in saveConfig() }
                
                // Negative Prompt
                Text("Negative Prompt").font(.system(size: 12, weight: .medium))
                TextField("What to exclude...", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onChange(of: negativePrompt) { _, _ in saveConfig() }
            }
            
        case .styleTransfer:
            VStack(alignment: .leading, spacing: 8) {
                // Note about two images
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("Requires 2 images: init + style")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
                
                Text("Style Strength").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $styleStrength, in: 0...1, step: 0.05)
                        .onChange(of: styleStrength) { _, _ in saveConfig() }
                    Text(String(format: "%.2f", styleStrength))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                
                Text("Composition Fidelity").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $compositionFidelity, in: 0...1, step: 0.05)
                        .onChange(of: compositionFidelity) { _, _ in saveConfig() }
                    Text(String(format: "%.2f", compositionFidelity))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                
                Text("Change Strength").font(.system(size: 12, weight: .medium))
                HStack {
                    Slider(value: $changeStrength, in: 0.1...1, step: 0.05)
                        .onChange(of: changeStrength) { _, _ in saveConfig() }
                    Text(String(format: "%.2f", changeStrength))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)
                }
                Text("How much the original should change")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
        default:
            Text("No additional settings for this service")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    private func loadConfig() {
        let config = settingManager.stabilityAIServicesConfig
        creativity = config.creativity
        controlStrength = config.controlStrength
        fidelity = config.fidelity
        styleStrength = config.styleStrength
        compositionFidelity = config.compositionFidelity
        changeStrength = config.changeStrength
        growMask = config.growMask
        outpaintLeft = config.outpaintLeft
        outpaintRight = config.outpaintRight
        outpaintUp = config.outpaintUp
        outpaintDown = config.outpaintDown
        searchPrompt = config.searchPrompt
        negativePrompt = config.negativePrompt
        stylePreset = config.stylePreset
        aspectRatio = config.aspectRatio
        seed = config.seed
    }
    
    private func saveConfig() {
        settingManager.stabilityAIServicesConfig = StabilityAIServicesConfig(
            selectedService: service.rawValue,
            creativity: creativity,
            controlStrength: controlStrength,
            fidelity: fidelity,
            styleStrength: styleStrength,
            compositionFidelity: compositionFidelity,
            changeStrength: changeStrength,
            growMask: growMask,
            outpaintLeft: outpaintLeft,
            outpaintRight: outpaintRight,
            outpaintUp: outpaintUp,
            outpaintDown: outpaintDown,
            searchPrompt: searchPrompt,
            negativePrompt: negativePrompt,
            stylePreset: stylePreset,
            aspectRatio: aspectRatio,
            seed: seed
        )
    }
    
    private func resetToDefaults() {
        let defaults = StabilityAIServicesConfig.defaultConfig
        creativity = defaults.creativity
        controlStrength = defaults.controlStrength
        fidelity = defaults.fidelity
        styleStrength = defaults.styleStrength
        compositionFidelity = defaults.compositionFidelity
        changeStrength = defaults.changeStrength
        growMask = defaults.growMask
        outpaintLeft = defaults.outpaintLeft
        outpaintRight = defaults.outpaintRight
        outpaintUp = defaults.outpaintUp
        outpaintDown = defaults.outpaintDown
        searchPrompt = defaults.searchPrompt
        negativePrompt = defaults.negativePrompt
        stylePreset = defaults.stylePreset
        aspectRatio = defaults.aspectRatio
        seed = defaults.seed
        saveConfig()
    }
    
    // MARK: - Reusable Components
    
    private var stylePresetPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Style Preset").font(.system(size: 12, weight: .medium))
            Picker("", selection: $stylePreset) {
                Text("None").tag("")
                ForEach(StabilityAIStylePreset.allCases.filter { $0 != .none }, id: \.rawValue) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: stylePreset) { _, _ in saveConfig() }
        }
    }
}

// MARK: - Services Dropdown Modifier
struct ServicesDropdownModifier: ViewModifier {
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
                                .stroke(isHovering ? Color.green.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
                )
        }
    }
}
