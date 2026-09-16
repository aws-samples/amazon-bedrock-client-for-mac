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
    @Binding var currentModelId: String
    let backend: Backend
    @State private var isShowingPopover = false
    private var modelID: String { BedrockModelID.base(currentModelId) }
    private var service: StabilityAIImageService? { StabilityAIImageService.matching(modelID) }
    private var hasConfiguration: Bool {
        [.conversation, .responses, .image, .video].contains(BedrockModelID.route(modelID))
    }

    var body: some View {
        if hasConfiguration {
        Button { isShowingPopover.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.primary)
        }
        .buttonStyle(LiquidGlassToolbarButtonStyle())
        .help("Response settings").accessibilityLabel("Response settings")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            configuration
                .id(currentModelId)
                .frame(width: 360, height: 460)
                .tint(WorkbenchStyle.selection)
                .buttonStyle(WorkbenchButtonStyle())
                .toggleStyle(WorkbenchSwitchStyle())
        }
        .onChange(of: currentModelId) { _, _ in isShowingPopover = false }
        }
    }

    @ViewBuilder private var configuration: some View {
        if modelID.hasPrefix("luma.") {
            LumaVideoConfigContent()
        } else if let service {
            StabilityAIServiceSettingsPopover(service: service, isShowingPopover: $isShowingPopover)
        } else if modelID.contains("nova-reel") {
            NovaReelConfigPopoverContent(isShowingPopover: $isShowingPopover)
        } else if modelID.contains("nova-canvas") {
            NovaCanvasConfigPopoverContent(isShowingPopover: $isShowingPopover)
        } else if modelID.contains("titan-image") {
            TitanImageConfigPopoverContent(isShowingPopover: $isShowingPopover)
        } else if modelID.hasPrefix("stability.") {
            StabilityAIConfigPopoverContent(isShowingPopover: $isShowingPopover,
                                           supportsImageToImage: modelID.contains("sd3"))
        } else {
            InferenceConfigPopoverContent(modelId: currentModelId, backend: backend)
        }
    }
}

private struct LumaVideoConfigContent: View {
    @ObservedObject private var settings = SettingManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Video settings").font(WorkbenchStyle.label)
                Spacer()
                Button("Reset") {
                    settings.lumaVideoConfig = LumaVideoConfiguration(outputBucket: settings.lumaVideoConfig.outputBucket)
                }.buttonStyle(.borderless).font(WorkbenchStyle.caption)
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Aspect ratio") {
                        WorkbenchMenuField(title: "Aspect ratio", selection: $settings.lumaVideoConfig.aspectRatio,
                                           options: LumaVideoConfiguration.aspectRatios.map { ($0, $0) })
                    }
                    field("Duration") {
                        WorkbenchSegmentedControl(title: "Duration", selection: $settings.lumaVideoConfig.duration,
                                                  options: [("5s", "5 seconds"), ("9s", "9 seconds")])
                    }
                    field("Resolution") {
                        WorkbenchSegmentedControl(title: "Resolution", selection: $settings.lumaVideoConfig.resolution,
                                                  options: LumaVideoConfiguration.resolutions.map { ($0, $0) })
                    }
                    Toggle("Loop video", isOn: $settings.lumaVideoConfig.loop)
                    Divider()
                    field("Output S3 location") {
                        TextField("s3://your-bucket/videos", text: $settings.lumaVideoConfig.outputBucket)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Video output S3 location")
                    }
                    Text("Use a bucket in your current AWS region. You can attach a start image and an optional end image.")
                        .font(WorkbenchStyle.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(16)
            }
        }
        .font(WorkbenchStyle.body)
        .background(WorkbenchPopoverFocus().frame(width: 0, height: 0))
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - InferenceConfigPopoverContent
struct InferenceConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    let modelId: String
    let backend: Backend

    private var selectedReasoningEffort: String { config.reasoningEffort }

    private var config: ModelInferenceConfig {
        settingManager.getInferenceConfig(for: modelId)
    }

    private var range: ModelInferenceRange {
        ModelInferenceRange.getRangeForModel(
            BedrockCapabilityRegistry.shared.foundationID(modelId, region: settingManager.selectedRegion.rawValue)
        )
    }

    private var modelName: String {
        WorkbenchModelCatalog.shared.model(modelId).name
    }

    // Check if reasoning is supported for this model
    private var isReasoningSupported: Bool {
        return backend.isReasoningSupported(modelId)
    }

    // Check if this is Claude 4.5+ model which doesn't support both temperature and top_p
    // This applies to all Anthropic models from 4.5 onwards (Sonnet 4.5, Haiku 4.5, Opus 4.5, and future versions)
    private var isClaude45PlusModel: Bool {
        let modelType = backend.getModelType(modelId)
        // All Claude 4.5+ models have this limitation
        return modelType == .claudeSonnet45 || modelType == .claudeHaiku45 || modelType == .claudeOpus45 || modelType == .claudeOpus46 || modelType == .claudeOpus47 || modelType == .claudeOpus48 || modelType == .claudeOpus5 || modelType == .claudeFable5
    }

    private var isClaudeSonnet5Model: Bool {
        backend.getModelType(modelId) == .claudeSonnet5
    }

    private var omitsSamplingParameters: Bool {
        isClaudeSonnet5Model || isClaudeOpus5Model || isClaudeFable5Model || isOpenAIFrontierModel
    }

    // Check if Top P should be disabled by the model or reasoning mode.
    private var isTopPDisabled: Bool {
        if omitsSamplingParameters {
            return true
        }
        return isReasoningSupported && settingManager.enableModelThinking && !backend.hasAlwaysOnReasoning(modelId)
    }

    // The value is fixed while reasoning is enabled and omitted for models without sampling controls.
    private var isTemperatureDisabled: Bool {
        if omitsSamplingParameters {
            return true
        }
        return isReasoningSupported && settingManager.enableModelThinking && !backend.hasAlwaysOnReasoning(modelId)
    }

    // Check if this is a GPT-OSS model
    private var isGptOssModel: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .openaiGptOss120b || modelType == .openaiGptOss20b || modelType == .openaiGptOssSafeguard
    }

    // Check if this is a Kimi K2 Thinking model (uses reasoning_effort like GPT-OSS)
    private var isKimiK2Model: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .kimiK2Thinking
    }

    // Check if this is a Nova 2 model (uses reasoningEffort instead of thinkingBudget)
    private var isNova2Model: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .nova2Lite
    }

    // Check if this is Claude Opus 4.6 (uses adaptive thinking with effort, supports max but not xhigh)
    private var isClaudeOpus46Model: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .claudeOpus46
    }

    // Check if this is Claude Opus 4.7 or 4.8 (uses adaptive thinking with effort, supports xhigh and max)
    private var isClaudeOpus47Model: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .claudeOpus47 || modelType == .claudeOpus48
    }

    // Check if this is Claude Fable 5 (adaptive thinking always on; only effort is configurable)
    private var isClaudeFable5Model: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .claudeFable5
    }

    // Check if this is Claude Opus 5 (adaptive thinking on by default; supports xhigh and max)
    private var isClaudeOpus5Model: Bool {
        backend.getModelType(modelId) == .claudeOpus5
    }

    // Use the runtime's foundation identity, including GPT-6 and profile ARNs.
    private var isOpenAIFrontierModel: Bool {
        backend.isFrontierGPT(modelId)
    }

    // GPT-5.6 (Sol/Terra/Luna) supports none/low/medium/high/xhigh/max reasoning effort,
    // where GPT-5.5/5.4 stop at high.
    private var isOpenAIGpt56Model: Bool {
        let modelType = backend.getModelType(modelId)
        return modelType == .openaiGpt6Astra || modelType == .openaiGpt56Sol || modelType == .openaiGpt56Terra || modelType == .openaiGpt56Luna
    }

    // Check if this model uses reasoning effort.
    private var usesReasoningEffort: Bool {
        return isGptOssModel || isNova2Model || isKimiK2Model || isClaudeOpus46Model || isClaudeOpus47Model || isClaudeOpus5Model || isClaudeSonnet5Model || isClaudeFable5Model || isOpenAIFrontierModel
    }

    // Check if thinking budget should be enabled (Claude models only, not models using effort-based reasoning)
    private var isThinkingBudgetEnabled: Bool {
        return isReasoningSupported && settingManager.enableModelThinking && !backend.hasAlwaysOnReasoning(modelId) && !usesReasoningEffort
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
                        if usesReasoningEffort {
                            reasoningEffortControl.padding(.horizontal, 16).padding(.top, 16)
                        }
                    }

                    streamingControl.padding(.horizontal, 16).padding(.top, 20)
                    // Bottom spacing
                    Spacer()
                        .frame(height: 20)
                }
            }
            .modifier(ScrollEdgeEffectModifier())
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: config.overrideDefault)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("responseSettings.popover")
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Response settings")
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
                    Text("Custom parameters")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Adjust the response limits for this model.")
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
                .toggleStyle(WorkbenchSwitchStyle(showsLabel: false)).frame(width: 36)
                .controlSize(.small)
                .accessibilityLabel("Custom parameters")
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
                if !omitsSamplingParameters {
                    temperatureControl
                    if !isTopPDisabled {
                        topPControl
                    } else {
                        topPDisabledControl
                    }
                }

                // Thinking Budget (reasoning 지원 + thinking 활성화시에만)
                if isThinkingBudgetEnabled {
                    thinkingBudgetControl
                }

                // Reasoning Effort (GPT-OSS, GPT-5.x, Nova 2, Kimi K2, Opus 4.6-4.8, Opus 5, Fable 5)
                // Always-on / mantle models keep effort configurable regardless of the thinking toggle.
                // Opus 5 applies effort in both modes (clamped to `high` when thinking is disabled).
                if usesReasoningEffort && (backend.hasAlwaysOnReasoning(modelId) || isClaudeFable5Model || isClaudeOpus5Model || isOpenAIFrontierModel || (isReasoningSupported && settingManager.enableModelThinking)) {
                    reasoningEffortControl
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    // MARK: - Default Values Section
    private var defaultValuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.bottom, 4)
            Text("Model defaults").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            LabeledContent("Output limit", value: actualDefaultConfig.maxTokens.map { "\($0.formatted()) tokens" } ?? "Model default")
            if !omitsSamplingParameters {
                if let temperature = actualDefaultConfig.temperature {
                    LabeledContent("Temperature", value: String(format: "%.2f", temperature))
                }
                if let topP = actualDefaultConfig.topP {
                    LabeledContent("Top P", value: String(format: "%.2f", topP))
                }
            }
            if isThinkingBudgetEnabled {
                LabeledContent("Thinking budget", value: "\(actualDefaultConfig.thinkingBudget.formatted()) tokens")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16).padding(.top, 16)
    }

    // actualDefaultConfig
    private var actualDefaultConfig: (maxTokens: Int?, temperature: Float?, topP: Float?, thinkingBudget: Int, enableStreaming: Bool) {
        let modelType = backend.getModelType(modelId)
        let defaultConfig = backend.getDefaultInferenceConfig(for: modelType)
        if isOpenAIFrontierModel {
            return (config.requestMaxTokens, nil, nil, config.thinkingBudget, config.enableStreaming)
        }

        return (
            maxTokens: defaultConfig.maxTokens,
            temperature: defaultConfig.temperature.map { Float($0) },
            topP: defaultConfig.topp.map { Float($0) },
            thinkingBudget: range.defaultThinkingBudget,
            enableStreaming: config.enableStreaming
        )
    }

    // MARK: - Individual Controls
    // Explicit setter closures avoid Swift 6.3's actor-isolated method-reference
    // reabstraction crash when Binding specializes a value such as Int.

    private var maxTokensControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Output limit").font(WorkbenchStyle.label)
                Spacer(minLength: 8)
                TextField("Tokens", value: Binding(
                    get: { config.maxTokens },
                    set: { updateMaxTokens(min(max($0, range.maxTokensRange.lowerBound), range.maxTokensRange.upperBound)) }
                ), format: .number.grouping(.never))
                .labelsHidden().textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 84)
                .disabled(!config.includeMaxTokens)
                .accessibilityLabel("Maximum output tokens")
                .accessibilityIdentifier("responseSettings.maxTokens")
                Toggle("Include output limit", isOn: Binding(
                    get: { config.includeMaxTokens }, set: { updateMaxTokensInclusion($0) }
                ))
                .labelsHidden().toggleStyle(WorkbenchSwitchStyle(showsLabel: false)).frame(width: 36)
                .accessibilityLabel("Include output limit")
            }
            Text("\(range.maxTokensRange.lowerBound.formatted())–\(range.maxTokensRange.upperBound.formatted()) tokens")
                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
            // Keep this continuous: a step of 1 creates up to 128,000 native
            // tick marks. Round the value in the binding instead.
            Slider(value: Binding(
                get: { Double(config.maxTokens) },
                set: { updateMaxTokens(Int($0.rounded())) }
            ), in: Double(range.maxTokensRange.lowerBound)...Double(range.maxTokensRange.upperBound))
            .controlSize(.small)
            .disabled(!config.includeMaxTokens)
            .accessibilityLabel("Output token limit")
        }
    }

    private var temperatureControl: some View {
        scalarControl(
            "Temperature",
            value: Binding(get: { isTemperatureDisabled ? 1 : Double(config.temperature) }, set: { updateTemperature(Float($0)) }),
            bounds: Double(range.temperatureRange.lowerBound)...Double(range.temperatureRange.upperBound),
            included: Binding(get: { config.includeTemperature }, set: { updateTemperatureInclusion($0) }),
            enabled: !isTemperatureDisabled,
            explanation: isTemperatureDisabled ? "Fixed at 1.0 while model thinking is enabled." : nil
        )
    }

    private var topPControl: some View {
        scalarControl(
            "Top P",
            value: Binding(get: { Double(config.topP) }, set: { updateTopP(Float($0)) }),
            bounds: Double(range.topPRange.lowerBound)...Double(range.topPRange.upperBound),
            included: Binding(get: { config.includeTopP }, set: { updateTopPInclusion($0) })
        )
    }

    private func scalarControl(_ title: String, value: Binding<Double>, bounds: ClosedRange<Double>,
                               included: Binding<Bool>, enabled: Bool = true, explanation: String? = nil) -> some View {
        let clampedValue = Binding<Double>(
            get: { min(max(value.wrappedValue, bounds.lowerBound), bounds.upperBound) },
            set: { value.wrappedValue = min(max($0, bounds.lowerBound), bounds.upperBound) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title).font(WorkbenchStyle.label)
                Spacer(minLength: 8)
                TextField(title, value: clampedValue, format: .number.grouping(.never).precision(.fractionLength(2)))
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing).frame(width: 84)
                    .disabled(!enabled || !included.wrappedValue)
                    .accessibilityLabel(title)
                Toggle("Include \(title)", isOn: included)
                    .labelsHidden().toggleStyle(WorkbenchSwitchStyle(showsLabel: false)).frame(width: 36)
                    .accessibilityLabel("Include \(title)")
            }
            Text(explanation ?? (included.wrappedValue
                ? String(format: "%.2f–%.2f", bounds.lowerBound, bounds.upperBound)
                : "Omitted from the request."))
                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if bounds.lowerBound < bounds.upperBound {
                Slider(value: Binding(
                    get: { clampedValue.wrappedValue },
                    set: { clampedValue.wrappedValue = ($0 * 100).rounded() / 100 }
                ), in: bounds)
                    .controlSize(.small).disabled(!enabled || !included.wrappedValue)
                    .accessibilityLabel("\(title) slider")
            }
        }
    }

    private var topPDisabledControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top P").font(WorkbenchStyle.label)
                Spacer()
                Text("Omitted").font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            }
            Text("Top P is omitted while model thinking is enabled.")
                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thinkingBudgetControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Thinking budget").font(WorkbenchStyle.label)
                Spacer(minLength: 8)
                TextField("Thinking budget", value: Binding(
                    get: { config.thinkingBudget }, set: { updateThinkingBudget($0) }
                ), format: .number.grouping(.never))
                .labelsHidden().textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).frame(width: 100)
                .accessibilityLabel("Thinking budget in tokens")
            }
            Text("\(range.thinkingBudgetRange.lowerBound.formatted())–\(range.thinkingBudgetRange.upperBound.formatted()) tokens for reasoning.")
                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Slider(value: Binding(
                get: { Double(config.thinkingBudget) }, set: { updateThinkingBudget(Int(($0 / 256).rounded()) * 256) }
            ), in: Double(range.thinkingBudgetRange.lowerBound)...Double(range.thinkingBudgetRange.upperBound))
                .controlSize(.small).accessibilityLabel("Thinking budget slider")
        }
    }

    private var streamingControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Stream responses", isOn: Binding(
                get: { config.enableStreaming },
                set: { value in
                    var updated = config
                    updated.enableStreaming = value
                    settingManager.setInferenceConfig(updated, for: modelId)
                }
            ))
            .font(WorkbenchStyle.label).toggleStyle(WorkbenchSwitchStyle())
            .accessibilityLabel("Stream responses")
            Text("Show the reply as it arrives.")
                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper Methods

    private func updateMaxTokensInclusion(_ isIncluded: Bool) {
        var newConfig = config
        newConfig.includeMaxTokens = isIncluded
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    private func updateTemperatureInclusion(_ isIncluded: Bool) {
        var newConfig = config
        newConfig.includeTemperature = isIncluded
        if isIncluded && isClaude45PlusModel {
            newConfig.includeTopP = false
        }
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    private func updateTopPInclusion(_ isIncluded: Bool) {
        var newConfig = config
        newConfig.includeTopP = isIncluded
        if isIncluded && isClaude45PlusModel {
            newConfig.includeTemperature = false
        }
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    private func updateMaxTokens(_ value: Int) {
        var newConfig = config
        newConfig.maxTokens = min(max(value, range.maxTokensRange.lowerBound), range.maxTokensRange.upperBound)
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    private func updateTemperature(_ value: Float) {
        var newConfig = config
        newConfig.temperature = min(max(value, range.temperatureRange.lowerBound), range.temperatureRange.upperBound)
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    private func updateTopP(_ value: Float) {
        var newConfig = config
        newConfig.topP = min(max(value, range.topPRange.lowerBound), range.topPRange.upperBound)
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    private func updateThinkingBudget(_ value: Int) {
        var newConfig = config
        newConfig.thinkingBudget = min(max(value, range.thinkingBudgetRange.lowerBound), range.thinkingBudgetRange.upperBound)
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }

    // MARK: - Reasoning Effort Control
    private var reasoningEffortControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reasoning effort")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Text(selectedReasoningEffort == "xhigh" ? "Very high" : selectedReasoningEffort.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Adaptive models expose their supported effort levels.
            WorkbenchSegmentedControl(title: "Reasoning effort",
                                      selection: Binding(get: { selectedReasoningEffort }, set: { updateReasoningEffort($0) }),
                                      options: effortOptions)
            .frame(maxWidth: .infinity)


            // Opus 5 rejects disabled thinking above `high` effort, so the request clamps it.
            if isClaudeOpus5Model && !settingManager.enableModelThinking
                && (selectedReasoningEffort == "xhigh" || selectedReasoningEffort == "max") {
                Text("Thinking is off, so this request will use High effort. Enable thinking to use \(selectedReasoningEffort.capitalized).")
                    .font(WorkbenchStyle.detail)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var effortOptions: [(value: String, title: String)] {
        var options = [("low", "Low"), ("medium", "Medium"), ("high", "High")]
        if isClaudeOpus47Model || isClaudeOpus5Model || isClaudeSonnet5Model || isClaudeFable5Model || isOpenAIGpt56Model {
            options.append(("xhigh", "Very high"))
        }
        if isClaudeOpus46Model || isClaudeOpus47Model || isClaudeOpus5Model || isClaudeSonnet5Model || isClaudeFable5Model || isOpenAIGpt56Model {
            options.append(("max", "Max"))
        }
        return options
    }

    private func updateReasoningEffort(_ effort: String) {
        // For adaptive-thinking Claude models and OpenAI frontier models,
        // save effort independently without forcing override on
        var newConfig = settingManager.getInferenceConfig(for: modelId)
        newConfig.reasoningEffort = effort
        if !isClaudeOpus46Model && !isClaudeOpus47Model && !isClaudeOpus5Model && !isClaudeSonnet5Model && !isClaudeFable5Model && !isOpenAIFrontierModel {
            newConfig.overrideDefault = true
        }
        settingManager.setInferenceConfig(newConfig, for: modelId)
    }
}

/// Retained for the image and video panels, using the same native control.
struct CustomSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let color: Color

    var body: some View {
        if range.lowerBound < range.upperBound {
            // SwiftUI's stepped macOS slider creates a native tick for every
            // value. Token/seed ranges can otherwise allocate thousands or
            // millions of tick marks and block the main thread.
            Slider(value: Binding(
                get: { value },
                set: { proposed in
                    let increment = max(step, Float.leastNormalMagnitude)
                    let snapped = range.lowerBound + ((proposed - range.lowerBound) / increment).rounded() * increment
                    value = min(max(snapped, range.lowerBound), range.upperBound)
                }
            ), in: range)
                .controlSize(.small).tint(color)
        } else {
            Text(range.lowerBound.formatted()).font(WorkbenchStyle.detail).foregroundStyle(.secondary)
        }
    }
}
