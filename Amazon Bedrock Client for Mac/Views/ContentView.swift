// ContentView.swift

import SwiftUI

struct ContentView: View {
    @State var selection: SidebarSelection? = .preferences
    @State var channelModels: [ChannelModel] = []
    @State var showAlert: Bool = false
    @State var alertMessage: String = ""
    @State var channelMessages: [ChannelModel: [MessageData]] = [:] // Add this line
    @ObservedObject var backendModel: BackendModel = BackendModel()
    @State var showSettings = false
    @State private var key = UUID()  // Used to force-refresh the view
    
    var body: some View {
        NavigationView {
            if showSettings {
                SettingsView(selectedRegion: .constant(.usEast1))
            } else {
                SidebarView(selection: $selection, channelModels: $channelModels, showAlert: $showAlert, alertMessage: $alertMessage, backendModel: backendModel)
                MainContentView(selection: $selection, channelMessages: $channelMessages, backendModel: backendModel)
            }
        }
        .frame(idealWidth: 1200, idealHeight: 800)
        .onReceive(SettingManager.shared.settingsChangedPublisher) {
            // Refresh the view by changing the key
            self.key = UUID()
        }
        .id(key)
    }
}
