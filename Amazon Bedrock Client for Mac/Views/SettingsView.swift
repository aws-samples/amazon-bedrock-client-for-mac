//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation
import Logging
import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingManager.shared
    @State private var selectedTab: SettingsTab = .general
    private var logger = Logger(label: "SettingsView")
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, advanced, appearance
        
        var id: String { self.rawValue }
        
        var title: String {
            switch self {
            case .general: return "General"
            case .advanced: return "Advanced"
            case .appearance: return "Appearance"
            }
        }
        
        var imageName: String {
            switch self {
            case .general: return "gearshape"
            case .advanced: return "wrench.and.screwdriver"
            case .appearance: return "paintbrush"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)
            
            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(SettingsTab.advanced)
        }
        .padding(20)
        .frame(width: 500, height: 500)
    }
}

struct MultilineRoundedTextField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Multiline text editor
            TextEditor(text: $text)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .focused($isFocused)
                .scrollContentBackground(.hidden)  // Hide scroll background
                .background(Color(nsColor: .textBackgroundColor))  // Gray background
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isFocused ? Color.accentColor : Color.gray.opacity(0.5),
                            lineWidth: isFocused ? 2 : 1)
                )
            
            // Placeholder
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundColor(Color.gray)  // Slightly darker placeholder color
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)  // Placeholder is non-interactive
            }
        }
        .background(Color(nsColor: .textBackgroundColor))  // Match background to macOS design
        .cornerRadius(6)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @State private var showingLoginSheet = false
    @State private var loginError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                Section("General Settings") {
                    Picker("AWS Region:", selection: $settingsManager.selectedRegion) {
                        ForEach(AWSRegion.allCases, id: \.self) { region in
                            Text(region.rawValue).tag(region)
                        }
                    }
                    
                    if settingsManager.isSSOLoggedIn {
                        HStack {
                            Text("Logged in with AWS Identity Center")
                            Spacer()
                            Button("Log Out") {
                                // SSO logout functionality
                            }
                        }
                    } else {
                        Picker("AWS Profile:", selection: $settingsManager.selectedProfile) {
                            ForEach(settingsManager.profiles) { profile in
                                Text(profile.name).tag(profile.name)
                            }
                        }
                        //                    Button(action: {
                        //                        showingLoginSheet = true
                        //                    }) {
                        //                        HStack {
                        //                            Image(systemName: "person.crop.circle.badge.plus")
                        //                            Text("Sign in with AWS Identity Center")
                        //                        }
                        //                    }
                        //                    .buttonStyle(PlainButtonStyle())
                    }
                    
                    Toggle("Check for Updates", isOn: $settingsManager.checkForUpdates)
                }.pickerStyle(MenuPickerStyle())
                
                
                Divider()
                
                Section("Model configuration") {
                    Picker("Default Model", selection: $settingsManager.defaultModelId) {
                        ForEach(settingsManager.availableModels, id: \.id) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                    
                    Toggle("Enable thinking (if available) ⌘⇧T", isOn: $settingsManager.enableModelThinking)
                        .keyboardShortcut("t", modifiers: [.shift, .command])
                }
                
                Divider()
                
                Section("Sytem prompt") {
                    MultilineRoundedTextField(
                        text: $settingsManager.systemPrompt,
                        placeholder: "Tell me more about yourself or how you want me to respond"
                    )
                }
            }
            
            Spacer()
        }
        .padding()
        //        .sheet(isPresented: $showingLoginSheet) {
        //            AwsIdentityCenterLoginView(isPresented: $showingLoginSheet, loginError: $loginError)
        //        }
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @Environment(\.colorScheme) var systemColorScheme
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance Settings")
                .font(.title2)
                .bold()
            
            Form {
                Picker("Appearance:", selection: $settingsManager.appearance) {
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                    Text("Auto").tag("Auto")
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: settingsManager.appearance) { newValue in
                    applyAppearance(newValue)
                }
            }
            Spacer()
        }
        .padding()
        .onAppear {
            applyAppearance(settingsManager.appearance)
        }
    }
    
    private func applyAppearance(_ appearance: String) {
        switch appearance {
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil  // Use system default
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @State private var selectedModel = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Advanced Settings")
                .font(.title2)
                .bold()
                .padding(.bottom, 10)
            
            Form {
                HStack {
                    TextField("Default directory", text: $settingsManager.defaultDirectory)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(true)
                    
                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Select"
                        
                        if panel.runModal() == .OK, let url = panel.url {
                            settingsManager.defaultDirectory = url.path
                        }
                    }) {
                        Text("Browse")
                    }
                    .buttonStyle(DefaultButtonStyle())
                }
                .frame(maxWidth: 400)
                
                Divider()
                
                TextField("Bedrock Endpoint:", text: $settingsManager.endpoint)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 400)
                
                TextField("Bedrock Runtime Endpoint:", text: $settingsManager.runtimeEndpoint)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 400)
                
                Divider()
                
                Toggle("Allow Image Pasting", isOn: $settingsManager.allowImagePasting)
                Toggle("Enable Logging", isOn: $settingsManager.enableDebugLog)
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .padding(20)
    }
}

//struct AwsIdentityCenterLoginView: View {
////    @ObservedObject var ssoManager = SSOManager()
//    @Binding var isPresented: Bool
//    @Binding var loginError: String?
//    @State var startUrl: String = ""
//    @State var region: String = ""
//    @State var authUrl: String = ""
//    @State var userCode: String = ""
//    @State var deviceCode: String = ""
//    @State var interval: Int = 5
//    @State var isLoading = false
//    var logger = Logger(label: "AwsIdentityCenterLoginView")
//
//    var body: some View {
//        VStack(spacing: 20) {
//            Text("AWS Identity Center Login")
//                .font(.headline)
//
//            TextField("AWS SSO Start URL", text: $startUrl)
//                .textFieldStyle(RoundedBorderTextFieldStyle())
//
//            TextField("AWS SSO Region (e.g., us-west-2)", text: $region)
//                .textFieldStyle(RoundedBorderTextFieldStyle())
//
//            if isLoading {
//                ProgressView()
//                if !authUrl.isEmpty && !userCode.isEmpty {
//                    VStack(spacing: 10) {
//                        Text("Open the following URL in your browser:")
//                        Text(authUrl)
//                            .font(.footnote)
//                            .foregroundColor(.blue)
//                            .onTapGesture {
//                                if let url = URL(string: authUrl) {
//                                    NSWorkspace.shared.open(url)
//                                }
//                            }
//                        Text("Then enter the code:")
//                        Text(userCode)
//                            .font(.headline)
//                    }
//                }            } else {
//                    Button("Login") {
//                        startSSOLogin()
//                    }
//                    .buttonStyle(DefaultButtonStyle())
//                    .disabled(startUrl.isEmpty || region.isEmpty) // Disable button if inputs are empty
//                }
//
//            if let error = loginError {
//                Text("Login Error: \(error)")
//                    .foregroundColor(.red)
//                Text("Please check your AWS SSO Start URL and Region.")
//                    .foregroundColor(.red)
//            }
//        }
//        .padding()
//        .frame(width: 400)
//    }
//
//    private func startSSOLogin() {
//        isLoading = true
//        loginError = nil
//
//        Task {
//            do {
//                let loginInfo = try await ssoManager.startSSOLogin(startUrl: startUrl, region: region)
//
//                // Update variables immediately
//                self.authUrl = loginInfo.authUrl
//                self.userCode = loginInfo.userCode
//                self.deviceCode = loginInfo.deviceCode
//                self.interval = loginInfo.interval
//
//                if let authURL = URL(string: self.authUrl) {
//                    NSWorkspace.shared.open(authURL)
//                } else {
//                    logger.error("Invalid authUrl: \(self.authUrl)")
//                }
//
//                logger.info("Using deviceCode: \(self.deviceCode)")
//
//                let tokenResponse = try await ssoManager.pollForTokens(deviceCode: self.deviceCode, interval: self.interval)
//
//                ssoManager.completeLogin(tokenResponse: tokenResponse)
//
//                DispatchQueue.main.async {
//                    self.isLoading = false
//                    self.isPresented = false
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    self.isLoading = false
//                    self.loginError = error.localizedDescription
//                }
//                logger.error("SSO Login Error: \(error)")
//            }
//        }
//    }
//}
