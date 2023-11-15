//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var selectedRegion: AWSRegion

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
                SettingManager.shared.notifySettingsChanged()
            }
        }
        .padding(20)
        .frame(width: 350, height: 100)
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("enableLog") private var enableLog = true

    var body: some View {
        Form {
            Toggle("Enable Debug Log", isOn: $enableLog)
        }
        .padding(20)
        .frame(width: 350, height: 100)
    }
}

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, advanced
    }
    
    @State private var selectedRegion: AWSRegion = SettingManager.shared.getAWSRegion() ?? .usEast1
    @State private var showMessage: Bool = false

    var body: some View {
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
        .frame(width: 375, height: 150)
    }
}
