//
//  SidebarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit  // Import AppKit for file operations

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
    }
}



struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var channelModels: [ChannelModel]
    @State private var organizedChannelModels: [String: [ChannelModel]] = [:]
    @State private var sectionVisibility: [String: Bool] = [:]
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    @ObservedObject var backendModel: BackendModel
    @ObservedObject var messageManager: ChannelManager = ChannelManager.shared

    var body: some View {
        List(selection: $selection) {
            homeSection
                .tag(SidebarSelection.preferences)
            
            ForEach(organizedChannelModels.keys.sorted(), id: \.self) { provider in
                dynamicSection(provider: provider)
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 100, idealWidth: 150, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: fetchData)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // Updated dynamicSection
    func dynamicSection(provider: String) -> some View {
        // Initialize from UserDefaults or default to true
        let initialVisibility = UserDefaults.standard.bool(forKey: "sectionVisibility_\(provider)")

        // Create a binding for section visibility
        let isOnBinding = Binding<Bool>(
            get: {
                sectionVisibility[provider, default: initialVisibility]
            },
            set: { newValue in
                sectionVisibility[provider] = newValue
                UserDefaults.standard.set(newValue, forKey: "sectionVisibility_\(provider)")
            }
        )

        return Section(
            header: SectionHeader(title: provider)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isOnBinding.wrappedValue.toggle()
                    }
                }
        ) {
            if isOnBinding.wrappedValue {  // Use isOnBinding here
                ForEach(organizedChannelModels[provider] ?? [], id: \.self) { channel in
                    channelRowView(for: channel, provider: provider)
                }
            }
        }
        .onAppear {
            // Sync the section visibility from UserDefaults when this view appears
            sectionVisibility[provider] = UserDefaults.standard.bool(forKey: "sectionVisibility_\(provider)")
        }
    }


    func channelRowView(for channel: ChannelModel, provider: String) -> some View {
        let components = channel.id.split(separator: ".", maxSplits: 1)
        let channelName = components.count > 1 ? String(components[1]) : channel.id

        return HStack {
            Label(channelName, systemImage: "number")
            Spacer()
            if messageManager.getIsLoading(for: channel.id) {
                // Display an ellipsis next to the SidebarModel to indicate loading
                Text("…")
                    .font(.body)  // Adjust font size if needed
                    .foregroundColor(.gray)  // Optional: set the text color
            }
        }
        .tag(SidebarSelection.channel(channel))
    }


    var homeSection: some View {
        Label("Home", systemImage: "house")
            .tag(SidebarSelection.preferences)
    }
    
    func fetchData() {
        Task {
            let result = await backendModel.backend.listFoundationModels()
            switch result {
            case .success(let modelSummaries):
                for modelSummary in modelSummaries {
                    let channel = ChannelModel.fromSummary(modelSummary)
                    organizedChannelModels[channel.provider, default: []].append(channel)
                }
            case .failure(let error):
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}
