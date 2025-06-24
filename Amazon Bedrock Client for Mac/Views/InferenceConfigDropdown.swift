//
//  InferenceConfigDropdown.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/9/24.
//

import SwiftUI
import AppKit

// MARK: - InferenceConfigDropdown
struct InferenceConfigDropdown: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @Binding var currentModelId: String
    let backend: Backend
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    private var currentConfig: ModelInferenceConfig {
        settingManager.getInferenceConfig(for: currentModelId)
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowingPopover.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(currentConfig.overrideDefault ? .blue : .secondary)
                
                Text("Config")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(currentConfig.overrideDefault ? .blue : .secondary)
                
                if currentConfig.overrideDefault {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
            InferenceConfigPopoverContent(modelId: currentModelId, backend: backend)
                .frame(width: 340, height: 380) // height 조금 증가
        }
    }
}

// MARK: - InferenceConfigPopoverContent
struct InferenceConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    let modelId: String
    let backend: Backend
    
    // Editing states
    @State private var isEditingMaxTokens = false
    @State private var isEditingTemperature = false
    @State private var isEditingTopP = false
    @State private var isEditingThinkingBudget = false
    @State private var tempMaxTokens = ""
    @State private var tempTemperature = ""
    @State private var tempTopP = ""
    @State private var tempThinkingBudget = ""
    
    private var config: ModelInferenceConfig {
        settingManager.getInferenceConfig(for: modelId)
    }
    
    private var range: ModelInferenceRange {
        ModelInferenceRange.getRangeForModel(modelId)
    }
    
    private var modelName: String {
        // Extract readable model name from ID
        let parts = modelId.split(separator: ".")
        if let lastPart = parts.last {
            return String(lastPart).split(separator: ":").first?.description ?? modelId
        }
        return modelId
    }
    
    // Check if reasoning is supported for this model
    private var isReasoningSupported: Bool {
        return backend.isReasoningSupported(modelId)
    }
    
    // Check if Top P should be disabled (when thinking is enabled)
    private var isTopPDisabled: Bool {
        return isReasoningSupported && settingManager.enableModelThinking && !backend.hasAlwaysOnReasoning(modelId)
    }
    
    // Check if temperature should be disabled (when thinking is enabled)
    private var isTemperatureDisabled: Bool {
        return isReasoningSupported && settingManager.enableModelThinking && !backend.hasAlwaysOnReasoning(modelId)
    }
    
    // Check if thinking budget should be enabled
    private var isThinkingBudgetEnabled: Bool {
        return isReasoningSupported && settingManager.enableModelThinking && !backend.hasAlwaysOnReasoning(modelId)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (고정)
            headerView
                .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.8))
                .zIndex(1)
            
            Divider()
            
            // Scrollable content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Override Toggle Section
                    overrideToggleSection
                        .padding(.top, isReasoningSupported && settingManager.enableModelThinking ? 8 : 16)
                    
                    if config.overrideDefault {
                        // Configuration Controls
                        configurationControlsSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        // Default Values Display
                        defaultValuesSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Bottom spacing
                    Spacer()
                        .frame(height: 20)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: config.overrideDefault)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inference Configuration")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Settings for \(modelName)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Override Toggle Section
    private var overrideToggleSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Override Default Config", systemImage: "gearshape.2")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Use custom parameters instead of model defaults")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { config.overrideDefault },
                    set: { newValue in
                        var newConfig = config
                        newConfig.overrideDefault = newValue
                        settingManager.setInferenceConfig(newConfig, for: modelId)
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .scaleEffect(0.8)
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Configuration Controls Section
    private var configurationControlsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            VStack(spacing: 24) {
                // Max Tokens
                maxTokensControl
                
                // Temperature
                temperatureControl
                
                // Top P (conditionally shown/disabled)
                if !isTopPDisabled {
                    topPControl
                } else {
                    topPDisabledControl
                }
                
                // Thinking Budget (reasoning 지원 + thinking 활성화시에만)
                if isThinkingBudgetEnabled {
                    thinkingBudgetControl
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Default Values Section
    private var defaultValuesSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            VStack(spacing: 12) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 20)
                
                Text("Using Model Defaults")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Tokens: \(actualDefaultConfig.maxTokens)")
                    Text("Temperature: \(String(format: "%.2f", actualDefaultConfig.temperature))")
                    if let topP = actualDefaultConfig.topP {
                        Text("Top P: \(String(format: "%.2f", topP))")
                    } else {
                        Text("Top P: Disabled (Reasoning Mode)")
                    }
                    // thinking budget 정보 추가
                    if isThinkingBudgetEnabled {
                        Text("Thinking Budget: \(actualDefaultConfig.thinkingBudget) tokens")
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.bottom, 20)
            }
        }
    }
    
    // actualDefaultConfig
    private var actualDefaultConfig: (maxTokens: Int, temperature: Float, topP: Float?, thinkingBudget: Int) {
        let modelType = backend.getModelType(modelId)
        let defaultConfig = backend.getDefaultInferenceConfig(for: modelType)
        
        return (
            maxTokens: defaultConfig.maxTokens ?? range.defaultMaxTokens,
            temperature: Float(defaultConfig.temperature ?? 0.7),
            topP: defaultConfig.topp.map { Float($0) },
            thinkingBudget: range.defaultThinkingBudget
        )
    }
    
    // MARK: - Individual Controls
    
    private var maxTokensControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Max Tokens", systemImage: "textformat.123")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Editable value display
                Group {
                    if isEditingMaxTokens {
                        TextField("", text: $tempMaxTokens)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                            .frame(width: 80)
                            .onSubmit {
                                applyMaxTokensEdit()
                            }
                            .onAppear {
                                tempMaxTokens = "\(config.maxTokens)"
                            }
                    } else {
                        Text("\(config.maxTokens)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingMaxTokens = true
                                    tempMaxTokens = "\(config.maxTokens)"
                                }
                            }
                    }
                }
            }
            
            Text("Range: \(range.maxTokensRange.lowerBound) - \(range.maxTokensRange.upperBound)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            CustomSlider(
                value: Binding(
                    get: { Float(config.maxTokens) },
                    set: { newValue in
                        updateMaxTokens(Int(newValue))
                    }
                ),
                range: Float(range.maxTokensRange.lowerBound)...Float(range.maxTokensRange.upperBound),
                step: range.maxTokensRange.upperBound > 8192 ? 512 : 256,
                color: .blue
            )
        }
    }
    
    private var temperatureControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Temperature", systemImage: "thermometer.medium")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isTemperatureDisabled ? .secondary : .primary)
                
                Spacer()
                
                Group {
                    if isEditingTemperature && !isTemperatureDisabled {
                        TextField("", text: $tempTemperature)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.orange, lineWidth: 1)
                            )
                            .frame(width: 80)
                            .onSubmit {
                                applyTemperatureEdit()
                            }
                            .onAppear {
                                tempTemperature = String(format: "%.2f", config.temperature)
                            }
                    } else {
                        Text(isTemperatureDisabled ? "1.00" : String(format: "%.2f", config.temperature))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isTemperatureDisabled ? .secondary : .orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background((isTemperatureDisabled ? Color.secondary : Color.orange).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture(count: 2) {
                                if !isTemperatureDisabled {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isEditingTemperature = true
                                        tempTemperature = String(format: "%.2f", config.temperature)
                                    }
                                }
                            }
                    }
                }
            }
            
            if isTemperatureDisabled {
                Text("Temperature is automatically set to 1.0 when Extended Reasoning is enabled")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                // Disabled slider appearance
                HStack(spacing: 8) {
                    Text(String(format: "%.1f", range.temperatureRange.lowerBound))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 35, alignment: .trailing)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .overlay(
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 16, height: 16)
                                .offset(x: 80) // Position at 1.0
                        )
                    
                    Text(String(format: "%.1f", range.temperatureRange.upperBound))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 35, alignment: .leading)
                }
                .frame(height: 20)
            } else {
                Text("Range: \(String(format: "%.1f", range.temperatureRange.lowerBound)) - \(String(format: "%.1f", range.temperatureRange.upperBound))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                if range.temperatureRange.lowerBound == range.temperatureRange.upperBound {
                    Text("Fixed at \(String(format: "%.1f", range.temperatureRange.lowerBound)) for this model")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    CustomSlider(
                        value: Binding(
                            get: { config.temperature },
                            set: { newValue in
                                updateTemperature(newValue)
                            }
                        ),
                        range: range.temperatureRange,
                        step: 0.01,
                        color: .orange
                    )
                }
            }
        }
    }
    
    private var topPControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Top P", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Group {
                    if isEditingTopP {
                        TextField("", text: $tempTopP)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                            .frame(width: 80)
                            .onSubmit {
                                applyTopPEdit()
                            }
                            .onAppear {
                                tempTopP = String(format: "%.2f", config.topP)
                            }
                    } else {
                        Text(String(format: "%.2f", config.topP))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingTopP = true
                                    tempTopP = String(format: "%.2f", config.topP)
                                }
                            }
                    }
                }
            }
            
            Text("Range: \(String(format: "%.2f", range.topPRange.lowerBound)) - \(String(format: "%.2f", range.topPRange.upperBound))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            CustomSlider(
                value: Binding(
                    get: { config.topP },
                    set: { newValue in
                        updateTopP(newValue)
                    }
                ),
                range: range.topPRange,
                step: 0.01,
                color: .green
            )
        }
    }
    
    // MARK: - Disabled Top P Control
    private var topPDisabledControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Top P", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Disabled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            Text("Top P is automatically disabled when Extended Reasoning is enabled")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            // Disabled slider appearance
            HStack(spacing: 8) {
                Text("0.00")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 35, alignment: .trailing)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)
                    .overlay(
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 16, height: 16)
                            .offset(x: -100) // Position at start
                    )
                
                Text("1.00")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 35, alignment: .leading)
            }
            .frame(height: 20)
        }
    }
    
    // MARK: - Thinking Budget Control
    private var thinkingBudgetControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Thinking Budget", systemImage: "brain")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Group {
                    if isEditingThinkingBudget {
                        TextField("", text: $tempThinkingBudget)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.purple, lineWidth: 1)
                            )
                            .frame(width: 80)
                            .onSubmit {
                                applyThinkingBudgetEdit()
                            }
                            .onAppear {
                                tempThinkingBudget = "\(config.thinkingBudget)"
                            }
                    } else {
                        Text("\(config.thinkingBudget)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingThinkingBudget = true
                                    tempThinkingBudget = "\(config.thinkingBudget)"
                                }
                            }
                    }
                }
            }
            
            Text("Range: \(range.thinkingBudgetRange.lowerBound) - \(range.thinkingBudgetRange.upperBound) tokens")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text("Controls how many tokens the model can use for internal reasoning")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            CustomSlider(
                value: Binding(
                    get: { Float(config.thinkingBudget) },
                    set: { newValue in
                        updateThinkingBudget(Int(newValue))
                    }
                ),
                range: Float(range.thinkingBudgetRange.lowerBound)...Float(range.thinkingBudgetRange.upperBound),
                step: 256,
                color: .purple
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateMaxTokens(_ value: Int) {
        var newConfig = config
        newConfig.maxTokens = value
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }
    
    private func updateTemperature(_ value: Float) {
        var newConfig = config
        newConfig.temperature = value
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }
    
    private func updateTopP(_ value: Float) {
        var newConfig = config
        newConfig.topP = value
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }
    
    private func updateThinkingBudget(_ value: Int) {
        var newConfig = config
        newConfig.thinkingBudget = value
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }
    
    private func applyMaxTokensEdit() {
        if let value = Int(tempMaxTokens) {
            let clampedValue = min(max(value, range.maxTokensRange.lowerBound), range.maxTokensRange.upperBound)
            updateMaxTokens(clampedValue)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingMaxTokens = false
        }
    }
    
    private func applyTemperatureEdit() {
        if let value = Float(tempTemperature) {
            let clampedValue = min(max(value, range.temperatureRange.lowerBound), range.temperatureRange.upperBound)
            updateTemperature(clampedValue)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingTemperature = false
        }
    }
    
    private func applyTopPEdit() {
        if let value = Float(tempTopP) {
            let clampedValue = min(max(value, range.topPRange.lowerBound), range.topPRange.upperBound)
            updateTopP(clampedValue)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingTopP = false
        }
    }
    
    private func applyThinkingBudgetEdit() {
        if let value = Int(tempThinkingBudget) {
            let clampedValue = min(max(value, range.thinkingBudgetRange.lowerBound), range.thinkingBudgetRange.upperBound)
            updateThinkingBudget(clampedValue)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingThinkingBudget = false
        }
    }
}

// MARK: - Custom Slider
struct CustomSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let color: Color
    
    @State private var isDragging = false
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            Text(formatRangeValue(range.lowerBound))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    // Active track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.8), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: trackWidth(for: geometry.size.width), height: 4)
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 20 : 16, height: isDragging ? 20 : 16)
                        .shadow(color: .black.opacity(0.2), radius: isDragging ? 4 : 2, x: 0, y: 1)
                        .overlay(
                            Circle()
                                .stroke(color, lineWidth: isDragging ? 2 : 1.5)
                        )
                        .offset(x: thumbOffset(for: geometry.size.width))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    if !isDragging {
                                        isDragging = true
                                    }
                                    
                                    let newValue = range.lowerBound + Float(gesture.location.x / geometry.size.width) * (range.upperBound - range.lowerBound)
                                    let steppedValue = round(newValue / step) * step
                                    value = min(max(steppedValue, range.lowerBound), range.upperBound)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
            .frame(height: 20)
            
            Text(formatRangeValue(range.upperBound))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)
        }
    }
    
    private func trackWidth(for containerWidth: CGFloat) -> CGFloat {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return containerWidth * CGFloat(progress)
    }
    
    private func thumbOffset(for containerWidth: CGFloat) -> CGFloat {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return containerWidth * CGFloat(progress) - (isDragging ? 10 : 8)
    }
    
    private func formatRangeValue(_ value: Float) -> String {
        if value >= 1000 {
            return String(format: "%.0fK", value / 1000)
        } else if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}
