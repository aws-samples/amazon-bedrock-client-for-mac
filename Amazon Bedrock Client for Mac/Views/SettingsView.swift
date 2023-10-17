//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI

struct SettingsView: View {
    @Binding var selectedRegion: AWSRegion
    @State private var selectedTextSize: Int = 14  // Default value
    @State private var showMessage: Bool = false
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let textSizes = [12, 14, 16, 18, 20, 22, 24]  // Sample text sizes
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Title Section
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)
                .padding(.top, 10)
            
            // AWS Region Picker Section
            VStack(alignment: .leading, spacing: 10) {
                Text("AWS Region")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Picker("AWS Region", selection: $selectedRegion) {
                    ForEach(AWSRegion.allCases) { region in
                        Text(region.rawValue).tag(region)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            .padding(.horizontal, 20)
            
            // Text Size Picker Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Text Size")
                    .font(.title2)
                    .fontWeight(.semibold)

                Picker("Text Size", selection: $selectedTextSize) {
                    ForEach(textSizes, id: \.self) { size in
                        Text("\(size) pt").tag(size)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            .padding(.horizontal, 20)
            
            // Save Button Section
            Button(action: {
                SettingManager.shared.saveAWSRegion(selectedRegion)
                showMessage = true
            }) {
                Text("Save")
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
            }
            .background(
                Color.blue
                    .cornerRadius(8)
                    .onTapGesture {
                        SettingManager.shared.saveAWSRegion(selectedRegion)
                        showMessage = true
                    }
            )
            .foregroundColor(.white)
            .alert(isPresented: $showMessage) {
                Alert(title: Text("Saved"), message: Text("Your settings have been saved."), dismissButton: .default(Text("OK")) {
                    self.presentationMode.wrappedValue.dismiss()
                })
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .background(Color(.windowBackgroundColor))
    }
}

// SettingsView_Previews.swift

import SwiftUI

@available(macOS 11.0, *)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(selectedRegion: .constant(.usEast1))
    }
}
