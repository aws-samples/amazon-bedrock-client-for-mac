// ContentView.swift

import SwiftUI

struct ContentView: View {
    @State var selection: SidebarSelection? = .preferences
    @State var channelModels: [ChannelModel] = []
    @State var showAlert: Bool = false
    @State var alertMessage: String = ""
    @State var channelMessages: [ChannelModel: [MessageData]] = [:] // Add this line
    @ObservedObject var backendModel: BackendModel = BackendModel()

    var body: some View {
        NavigationView {
            SidebarView(selection: $selection, channelModels: $channelModels, showAlert: $showAlert, alertMessage: $alertMessage, backendModel: backendModel)
            MainContentView(selection: $selection, channelMessages: $channelMessages, backendModel: backendModel)
        }
    }
}
