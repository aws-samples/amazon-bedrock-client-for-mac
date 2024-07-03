import SwiftUI

struct HomeView: View {
    @Binding var selection: SidebarSelection?
    @Binding var menuSelection: SidebarSelection?
    
    @State private var hasLoadedModels = false
    
    var body: some View {
        ZStack {
            Color.background
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                headerView
            }
            .padding(EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40))
        }
        .onAppear {
            if menuSelection != .newChat && !hasLoadedModels {
                self.hasLoadedModels = true
            }
        }
        .onChange(of: menuSelection) { newSelection in
            onModelsLoaded()
        }
    }
    
    var headerView: some View {
        VStack {
            Spacer()
            
            Text("Amazon Bedrock")
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundColor(Color.text)
            
            Text("The easiest way to build and scale generative AI applications with foundation models")
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundColor(Color.secondaryText)
            
            if !hasLoadedModels {
                ProgressView("Loading models...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            }
            
            Spacer()
        }
    }
    
    func onModelsLoaded() {
        hasLoadedModels = true
    }
}
