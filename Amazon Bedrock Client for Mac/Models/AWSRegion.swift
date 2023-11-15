//
//  AWSRegion.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation

enum AWSRegion: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case usEast1 = "us-east-1"
    case usWest2 = "us-west-2"
    case apSouthEast1 = "ap-southeast-1"
    case apNortheEast1 = "ap-northeast-1"
    case euCentral1 = "eu-central-1"
    
    // ... add other regions
}
