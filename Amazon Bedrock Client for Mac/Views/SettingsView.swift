//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Foundation

struct SettingsView: View {
    @StateObject private var settingsManager = SettingManager.shared
    @StateObject private var llmSettingsManager = LLMSettingsManager()
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: GeneralSettingsView()) {
                    Label("General", systemImage: "gear")
                }
//                NavigationLink(destination: AppearanceSettingsView()) {
//                    Label("Appearance", systemImage: "paintbrush")
//                }
                NavigationLink(destination: AdvancedSettingsView()) {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
//                NavigationLink(destination: LLMSettingsView(settingsManager: llmSettingsManager)) {
//                    Label("LLM Settings", systemImage: "cpu")
//                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)
            
            GeneralSettingsView()
        }
        .frame(width: 600, height: 400)
        .navigationTitle("Settings")
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    
    var body: some View {
        Form {
            Picker("AWS Region", selection: $settingsManager.selectedRegion) {
                ForEach(AWSRegion.allCases, id: \.self) { region in
                    Text(region.rawValue).tag(region)
                }
            }
            
            Picker("AWS Profile", selection: $settingsManager.selectedProfile) {
                ForEach(settingsManager.profiles, id: \.self) { profile in
                    Text(profile)
                }
            }
            
            Toggle("Check for Updates", isOn: $settingsManager.checkForUpdates)
        }
        .padding()
    }
}


struct AppearanceSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    
    var body: some View {
        Form {
            Picker("Appearance", selection: $settingsManager.appearance) {
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
                Text("Auto").tag("Auto")
            }
            .pickerStyle(SegmentedPickerStyle())
            
            ColorPicker("Accent Color", selection: Binding(
                get: { Color(settingsManager.accentColor) },
                set: { settingsManager.accentColor = NSColor($0) }
            ))
            
            Picker("Sidebar Icon Size", selection: $settingsManager.sidebarIconSize) {
                Text("Small").tag("Small")
                Text("Medium").tag("Medium")
                Text("Large").tag("Large")
            }
        }
        .padding()
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    
    var body: some View {
        Form {
            TextField("Bedrock Endpoint", text: $settingsManager.endpoint)
            TextField("Bedrock Runtime Endpoint", text: $settingsManager.runtimeEndpoint)
            Toggle("Enable Logging", isOn: $settingsManager.enableDebugLog)
        }
        .padding()
    }
}

struct LLMSettingsView: View {
    @ObservedObject var settingsManager: LLMSettingsManager

    var body: some View {
        Form {
            Section(header: Text("Model Selection")) {
                Picker("Model", selection: $settingsManager.selectedModel) {
                    ForEach(settingsManager.models) { model in
                        Text(model.name).tag(model as LLMModel?)
                    }
                }
            }
            
            if let model = settingsManager.selectedModel {
                Section(header: Text("Model Parameters")) {
                    if model.temperature {
                        SliderView(value: $settingsManager.temperature, range: 0...1, title: "Temperature")
                    }
                    if model.topP {
                        SliderView(value: $settingsManager.topP, range: 0...1, title: "Top P")
                    }
                    if model.topK {
                        SliderView(value: Binding(
                            get: { Double(settingsManager.topK) },
                            set: { settingsManager.topK = Int($0) }
                        ), range: 0...100, title: "Top K")
                    }
                    if model.maxTokens {
                        SliderView(value: Binding(
                            get: { Double(settingsManager.maxTokens) },
                            set: { settingsManager.maxTokens = Int($0) }
                        ), range: 1...2048, title: "Max Tokens")
                    }
                    if model.stopSequences {
                        TextField("Stop Sequences", text: $settingsManager.stopSequences)
                    }
                    if model.presencePenalty {
                        SliderView(value: $settingsManager.presencePenalty, range: -2...2, title: "Presence Penalty")
                    }
                    if model.frequencyPenalty {
                        SliderView(value: $settingsManager.frequencyPenalty, range: -2...2, title: "Frequency Penalty")
                    }
                    if model.logitBias {
                        TextField("Logit Bias", text: $settingsManager.logitBias)
                    }
                }
            }
        }
    }
}

struct SliderView: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let title: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: "%.2f", value))
                    .frame(width: 50)
            }
        }
    }
}

class LLMSettingsManager: ObservableObject {
    @Published var models: [LLMModel] = [
        LLMModel(name: "AI21 Jamba-Instruct", temperature: true, topP: true, topK: true, maxTokens: true, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: false),
        LLMModel(name: "Amazon Titan models", temperature: true, topP: true, topK: false, maxTokens: true, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "Anthropic Claude 2 and earlier", temperature: true, topP: true, topK: true, maxTokens: true, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "Anthropic Claude 3", temperature: true, topP: true, topK: true, maxTokens: true, stopSequences: true, presencePenalty: true, frequencyPenalty: true, logitBias: true),
        LLMModel(name: "Anthropic Claude 3.5", temperature: true, topP: true, topK: true, maxTokens: false, stopSequences: true, presencePenalty: true, frequencyPenalty: true, logitBias: true),
        LLMModel(name: "Cohere Command R and Command R+", temperature: true, topP: true, topK: true, maxTokens: true, stopSequences: false, presencePenalty: true, frequencyPenalty: false, logitBias: false),
        LLMModel(name: "Meta Llama 2 and Llama 3", temperature: true, topP: true, topK: true, maxTokens: true, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "Mistral AI Instruct", temperature: true, topP: true, topK: false, maxTokens: true, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "Mistral Large", temperature: true, topP: true, topK: true, maxTokens: true, stopSequences: false, presencePenalty: true, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "Mistral Small", temperature: true, topP: true, topK: true, maxTokens: false, stopSequences: false, presencePenalty: true, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "AI21 Labs Jurassic-2 (Text)", temperature: true, topP: false, topK: false, maxTokens: false, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: true),
        LLMModel(name: "Cohere Command (Text)", temperature: true, topP: true, topK: false, maxTokens: false, stopSequences: false, presencePenalty: false, frequencyPenalty: false, logitBias: false)
    ]
    
    @Published var selectedModel: LLMModel?
    @Published var temperature: Double = 0.7
    @Published var topP: Double = 1.0
    @Published var topK: Int = 0
    @Published var maxTokens: Int = 100
    @Published var stopSequences: String = ""
    @Published var presencePenalty: Double = 0.0
    @Published var frequencyPenalty: Double = 0.0
    @Published var logitBias: String = ""
}

struct LLMModel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var temperature: Bool
    var topP: Bool
    var topK: Bool
    var maxTokens: Bool
    var stopSequences: Bool
    var presencePenalty: Bool
    var frequencyPenalty: Bool
    var logitBias: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LLMModel, rhs: LLMModel) -> Bool {
        lhs.id == rhs.id
    }
}
