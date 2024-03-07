//
//  ImageManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/7/24.
//

import Foundation
import SwiftUI

class SharedImageDataSource: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var fileExtensions: [String] = [] // Assuming this stores file extensions corresponding to each image
}
