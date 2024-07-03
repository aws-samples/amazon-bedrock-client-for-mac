//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Foundation
import WebKit
import AWSSSOOIDC
import Logging
import AwsCommonRuntimeKit

struct SettingsView: View {
    @StateObject private var settingsManager = SettingManager.shared
    @StateObject private var llmSettingsManager = LLMSettingsManager()
    @StateObject private var ssoManager = SSOManager()
    @State private var searchText = ""
    private var logger = Logger(label: "SettingsView")
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: GeneralSettingsView(ssoManager: ssoManager)) {
                    Label("General", systemImage: "gear")
                }
//                NavigationLink(destination: AppearanceSettingsView()) {
//                    Label("Appearance", systemImage: "paintbrush")
//                }
//                NavigationLink(destination: LLMSettingsView(settingsManager: llmSettingsManager)) {
//                    Label("LLM Settings", systemImage: "cpu")
//                }
                NavigationLink(destination: AdvancedSettingsView()) {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)
        }
        .frame(width: 600, height: 400)
        .navigationTitle("Settings")
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject var ssoManager: SSOManager
    @State private var showingLoginSheet = false
    @State private var loginError: String?
    
    var body: some View {
        Form {
            Picker("AWS Region", selection: $settingsManager.selectedRegion) {
                ForEach(AWSRegion.allCases, id: \.self) { region in
                    Text(region.rawValue).tag(region)
                }
            }
            
            Picker("AWS Profile", selection: $settingsManager.selectedProfile) {
                ForEach(settingsManager.profiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            
            // Note: TBU
            if ssoManager.isLoggedIn {
                HStack {
                    Text("Logged in with AWS Identity Center")
                        .foregroundColor(.secondary)
//                    Spacer()
//                    Button("Log out") {
//                        ssoManager.logout()
//                    }
//                    .buttonStyle(.borderless)
                }
            } else {
//                Button(action: {
//                    showingLoginSheet = true
//                }) {
//                    HStack {
//                        Image("amazon")
//                            .resizable()
//                            .aspectRatio(contentMode: .fit)
//                            .frame(width: 16, height: 16)
//                        Text("Sign in with AWS Identity Center")
//                    }
//                }
//                .buttonStyle(AWSButtonStyle())
            }


            Toggle("Check for Updates", isOn: $settingsManager.checkForUpdates)
            
            if let error = loginError {
                Text(error)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .sheet(isPresented: $showingLoginSheet) {
            AwsIdentityCenterLoginView(ssoManager: ssoManager, isPresented: $showingLoginSheet, loginError: $loginError)
        }
    }
}

struct AWSButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}


struct AwsIdentityCenterLoginView: View {
    @ObservedObject var ssoManager: SSOManager
    @Binding var isPresented: Bool
    @Binding var loginError: String?
    @State private var startUrl: String = ""
    @State private var region: String = "us-west-2"
    @State private var authUrl: String = ""
    @State private var userCode: String = ""
    @State private var isLoading = false
    var logger = Logger(label: "AwsIdentityCenterLoginView")
    
    var body: some View {
        VStack(spacing: 20) {
            Text("AWS Identity Center Login")
                .font(.headline)
            
            TextField("AWS SSO Start URL", text: $startUrl)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("AWS Region", text: $region)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if isLoading {
                VStack {
                    ProgressView()
                    if !authUrl.isEmpty && !userCode.isEmpty {
                        Text("Open the following URL in your browser:")
                            .padding(.top)
                        Text(authUrl)
                            .font(.footnote)
                            .foregroundColor(.blue)
                        Text("Then enter the code:")
                            .padding(.top)
                        Text(userCode)
                            .font(.headline)
                            .padding(.top)
                    }
                }
            } else {
                Button("Login") {
                    startSSOLogin()
                }
                .buttonStyle(AWSButtonStyle())
            }
            
            if let error = loginError {
                Text(error)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
    
    private func startSSOLogin() {
        isLoading = true
        loginError = nil
        
        Task {
            do {
                let (url, code) = try await ssoManager.startSSOLogin(startUrl: startUrl, region: region)
                DispatchQueue.main.async {
                    self.authUrl = url
                    self.userCode = code
                }
                
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
                
                let tokenResponse = try await ssoManager.pollForTokens(deviceCode: code)
                
                try await ssoManager.completeLogin(tokenResponse: tokenResponse)
                
                DispatchQueue.main.async {
                    self.isPresented = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                // Handle specific SSO errors
                if let ssoError = error as? AWSSSOOIDC.InvalidClientException {
                    handleSSOError("Invalid Client", ssoError)
                } else if let ssoError = error as? AWSSSOOIDC.AuthorizationPendingException {
                    handleSSOError("Authorization Pending", ssoError)
                } else if let ssoError = error as? AWSSSOOIDC.SlowDownException {
                    handleSSOError("Slow Down", ssoError)
                } else if let ssoError = error as? AWSSSOOIDC.ExpiredTokenException {
                    handleSSOError("Token Expired", ssoError)
                } else if let crtError = error as? AwsCommonRuntimeKit.CRTError {
                    // Handle CRTError
                    let errorMessage = "CRT Error: Code \(crtError.code), Message: \(crtError.message)"
                    handleError(errorMessage, crtError)
                } else {
                    // Handle unknown errors
                    handleError("Unknown error", error)
                }
            }
            logger.info("Start URL: \(startUrl), Region: \(region)") // Changed to info level
        }
    }

    private func handleSSOError(_ type: String, _ error: Error) {
        let errorMessage = "\(type) Error: \(error.localizedDescription)"
        handleError(errorMessage, error)
    }

    private func handleError(_ message: String, _ error: Error) {
        DispatchQueue.main.async {
            self.loginError = message
        }
        logger.error("SSO Login Error - \(message)")
        logger.error("Error details: \(String(describing: error))")
    }
}


extension AwsIdentityCenterLoginView {
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AwsIdentityCenterLoginView
        
        init(parent: AwsIdentityCenterLoginView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "amazonbedrock" {
                parent.handleRedirect(url: url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func handleRedirect(url: URL) {
        // Handle the URL redirect here
        print("젠장")
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

extension BackendModel {
    var isLoggedInWithSSO: Bool {
        backend.isLoggedInWithSSO()
    }
}
