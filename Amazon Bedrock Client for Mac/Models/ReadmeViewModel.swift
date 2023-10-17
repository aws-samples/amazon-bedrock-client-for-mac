//
//  ReadmeViewModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/07.
//

import Foundation
import Combine

class ReadmeViewModel: ObservableObject {
    @Published var readmeContent: String = ""
    
    var cancellables = Set<AnyCancellable>()
    
    init() {
        guard let url = URL(string: "https://raw.githubusercontent.com/didhd/amazon-bedrock-client-for-mac/main/README.md") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { String(data: $0.data, encoding: .utf8) ?? "" }
            .replaceError(with: "")
            .receive(on: DispatchQueue.main)
            .assign(to: \.readmeContent, on: self)
            .store(in: &cancellables)
    }
}
