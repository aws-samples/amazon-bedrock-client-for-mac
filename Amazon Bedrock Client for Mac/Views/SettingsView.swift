//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var selectedRegion: AWSRegion
    @AppStorage("checkForUpdatesKey") private var checkForUpdates = true
    
    @AppStorage("showPreview") private var showPreview = true
    @AppStorage("fontSize") private var fontSize = 12.0
    
    var body: some View {
        Form {
            Picker("AWS Region", selection: $selectedRegion) {
                ForEach(AWSRegion.allCases) { region in
                    Text(region.rawValue).tag(region)
                }
            }
            .pickerStyle(DefaultPickerStyle())
            .onChange(of: selectedRegion) { newValue in
                SettingManager.shared.saveAWSRegion(newValue)
            }
            
            Toggle("Check for Version Updates", isOn: $checkForUpdates)
                .onChange(of: checkForUpdates) { newValue in
                    SettingManager.shared.saveCheckForUpdates(newValue)
                }
        }
        .padding(20)
        .frame(width: 350, height: 100)
        
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("enableLog") private var enableLog = true
    
    @State private var endpoint: String = SettingManager.shared.getEndpoint() ?? ""
    @State private var tempEndpoint: String = ""
    @State private var runtimeEndpoint: String = SettingManager.shared.getRuntimeEndpoint() ?? ""
    @State private var tempRuntimeEndpoint: String = ""
    
    
    var body: some View {
        Form {
            TextField("Bedrock Endpoint", text: $tempEndpoint, onEditingChanged: { _ in
                endpoint = tempEndpoint
            }).disableAutocorrection(true)
                .onAppear {
                    tempEndpoint = endpoint
                }
            
            TextField("Bedrock Runtime Endpoint", text: $tempRuntimeEndpoint, onEditingChanged: { _ in
                runtimeEndpoint = tempRuntimeEndpoint
            }).disableAutocorrection(true)
                .onAppear {
                    tempRuntimeEndpoint = runtimeEndpoint
                }
            
            Toggle("Enable Debug Log", isOn: $enableLog)
        }
        .padding(20)
        .frame(width: 500, height: 100)
        
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode // To handle closing the view
    
    private enum Tabs: Hashable {
        case general, advanced
    }
    
    @State private var selectedRegion: AWSRegion = SettingManager.shared.getAWSRegion() ?? .usEast1
    
    var body: some View {
        VStack {
            TabView {
                GeneralSettingsView(selectedRegion: $selectedRegion)
                    .tabItem {
                        Label("General", systemImage: "network")
                    }
                    .tag(Tabs.general)
                AdvancedSettingsView()
                    .tabItem {
                        Label("Advanced", systemImage: "star")
                    }
                    .tag(Tabs.advanced)
            }
            .padding(20)
            .frame(width: 480, height: 300) // Increased width and height
            
            Button("Save", action: {
                self.presentationMode.wrappedValue.dismiss() // Close the settings view
                SettingManager.shared.notifySettingsChanged()
            })
            .padding()
        }.frame(width: 500, height: 350) // Adjusted overall frame size
    }
}
