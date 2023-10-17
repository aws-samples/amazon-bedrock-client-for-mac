import SwiftUI
import AppKit

struct HomeView: View {
    @State var showSettings = false
    @State private var selectedRegion: AWSRegion = .usEast1  // Default region

    let featureHighlightCards = [
        ("Choose from a range of leading foundation models", "Explore developer experience", "image1", "https://aws.amazon.com/bedrock/developer-experience/"),
        ("Build agents that dynamically invoke APIs to execute complex business tasks", "Explore agents", "image2", "https://aws.amazon.com/bedrock/agents/"),
        ("Extend the power of FMs with RAG by connecting them to your company-specific data sources", "Explore RAG capabilities", "image3", "https://aws.amazon.com/bedrock/knowledge-bases/"),
        ("Support data security and compliance standards", "Explore security features", "image4", "https://aws.amazon.com/bedrock/security-compliance/")
    ]

    let cards = [
        ("Amazon Titan", "FM for text generation and classification, question answering, and information extraction and a text embeddings model for personalization and search.", "your-image-1", "https://aws.amazon.com/bedrock/titan/"),
        ("Jurassic", "Instruction-following FMs for any language task, including question answering, summarization, text generation, and more.", "your-image-2", "https://aws.amazon.com/bedrock/jurassic/"),
        ("Claude", "FM for thoughtful dialogue, content creation, complex reasoning, creativity, and coding, based on Constitutional AI and harmlessness training.", "your-image-3", "https://aws.amazon.com/bedrock/claude/"),
        ("Command", "Text generation model that can generate text-based responses optimized for business use cases based on prompts.", "your-image-4", "https://aws.amazon.com/bedrock/cohere-command/"),
        ("Llama 2", "Fine-tuned models ideal for dialogue use cases.", "your-image-5", "https://aws.amazon.com/bedrock/llama-2/"),
        ("Stable Diffusion", "Image generation model produces unique, realistic, and high-quality visuals, art, logos, and designs.", "your-image-6", "https://aws.amazon.com/bedrock/stable-diffusion/")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                featureSection
                modelChoiceSection
            }
            .padding(EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40))
        }
        .background(Color.background)
        .toolbar {
            // Left-aligned items
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    if let url = URL(string: "https://aws.amazon.com/bedrock/") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 0) {
                        Image("bedrock")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .font(.system(size: 40))
                        
                        VStack(alignment: .leading) {
                            Text("Amazon Bedrock")
                                .font(.headline)
                            Text("The easiest way to build and scale generative AI applications with foundation models")
                                .font(.subheadline)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Right-aligned items
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedRegion: $selectedRegion)
        }
    }
    
    var headerView: some View {
        VStack(spacing: 20) {
            Text("Amazon Bedrock")
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundColor(Color.text)
            
            Text("The easiest way to build and scale generative AI applications with foundation models")
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundColor(Color.secondaryText)
            
            Button("Get started with Amazon Bedrock") {
                if let url = URL(string: "https://console.aws.amazon.com/bedrock/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(Color.white)
            .cornerRadius(8)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.bottom, 20)
    }
    
    var featureSection: some View {
        VStack(alignment: .leading) {
            Text("How it Works")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(Color.text)
                .padding(.bottom, 20)
            
            ForEach(featureHighlightCards, id: \.0) { title, subtitle, imageName, url in
                DeluxeCard(title: title, subtitle: subtitle, imageName: imageName, url: URL(string: url)!)
                    .padding(.bottom, 20)
            }
        }
    }
    
    var modelChoiceSection: some View {
        VStack(alignment: .leading) {
            Text("Choice of Models")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(Color.text)
            
            ForEach(0..<(cards.count / 2), id: \.self) { i in
                modelChoiceRow(index: i)
            }
        }
    }

    @ViewBuilder
    private func modelChoiceRow(index: Int) -> some View {
        HStack(spacing: 20) {
            let firstCard = cards[index * 2]
            let firstCardURL = URL(string: firstCard.3)!
            CardView(title: firstCard.0, description: firstCard.1, imageName: firstCard.2, url: firstCardURL)
            
            if index * 2 + 1 < cards.count {
                let secondCard = cards[index * 2 + 1]
                let secondCardURL = URL(string: secondCard.3)!
                CardView(title: secondCard.0, description: secondCard.1, imageName: secondCard.2, url: secondCardURL)
            }
        }
        .padding(.bottom, 20)
    }
}

// DeluxeCard and CardView definitions would remain the same


struct DeluxeCard: View {
    var title: String
    var subtitle: String
    var imageName: String
    var url: URL
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        ZStack {
            // Background Image
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipped()
                .overlay(
                    LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.4), Color.black.opacity(0)]),
                                   startPoint: .bottom,
                                   endPoint: .top)
                )
            
            // Content
            VStack(alignment: .leading, spacing: 12) {  // Alignment set to .leading
                Text("Feature Page")
                    .font(.caption2)  // Increased font size
                    .multilineTextAlignment(.leading)  // Aligned to left
                    .foregroundColor(Color.white)
                    
                Text(title)
                    .font(.title3)  // Increased font size
                    .multilineTextAlignment(.leading)  // Aligned to left
                    .foregroundColor(Color.white)
                    
                HStack {
                    Text(subtitle)
                        .font(.headline)  // Increased font size
                        .multilineTextAlignment(.leading)  // Aligned to left
                        .foregroundColor(Color.white)
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(Color.white)
                }
            }
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
        }
        .frame(height: 200, alignment: .leading)
        .cornerRadius(24)
        .shadow(color: isHovered ? Color.text.opacity(0.7) : .clear, radius: 10, x: 0, y: 0)
        .onHover { hover in
            isHovered = hover
        }
        .onTapGesture {
            NSWorkspace.shared.open(url)
        }
    }
}



struct CardView: View {
    var title: String
    var description: String
    var imageName: String
    var url: URL
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        ZStack {
            Color.secondaryBackground
            
            VStack(alignment: .leading, spacing: 12) {  // Increased spacing
                Text(title)
                    .font(.title3)  // Increased font size
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)  // Aligned text to the left
                    .foregroundColor(Color.text)
                
                Text(description)
                    .font(.headline)  // Increased font size
                    .multilineTextAlignment(.leading)  // Aligned text to the left
                    .foregroundColor(Color.secondaryText)
                
                Spacer()
                
                HStack {
                    Text("Learn More")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)  // Aligned text to the left
                        .foregroundColor(Color.link)
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(Color.link)
                }
            }
            .padding(EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40))
        }
        .cornerRadius(24)
        .shadow(color: isHovered ? Color.text.opacity(0.7) : .clear, radius: 5, x: 0, y: 0)
        .onHover { hover in
            isHovered = hover
        }
        .onTapGesture {
            NSWorkspace.shared.open(url)
        }.frame(alignment: .leading)
    }
}


struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeView()
                .preferredColorScheme(.dark)
            HomeView()
                .preferredColorScheme(.light)
        }
    }
}
