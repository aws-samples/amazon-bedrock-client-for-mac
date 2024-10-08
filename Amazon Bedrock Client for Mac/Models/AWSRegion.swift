//
//  AWSRegion.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation

enum AWSRegion: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case usEast1 = "us-east-1"           // US East (N. Virginia)
    case usEast2 = "us-east-2"           // US East (Ohio)
    case usWest2 = "us-west-2"           // US West (Oregon)
    case apSouth1 = "ap-south-1"         // Asia Pacific (Mumbai)
    case apNorthEast1 = "ap-northeast-1" // Asia Pacific (Tokyo)
    case apNorthEast2 = "ap-northeast-2" // Asia Pacific (Seoul)
    case apSouthEast1 = "ap-southeast-1" // Asia Pacific (Singapore)
    case apSouthEast2 = "ap-southeast-2" // Asia Pacific (Sydney)
    case euCentral1 = "eu-central-1"     // Europe (Frankfurt)
    case euWest1 = "eu-west-1"           // Europe (Ireland)
    case euWest2 = "eu-west-2"           // Europe (London)
    case euWest3 = "eu-west-3"           // Europe (Paris)
    case caCentral1 = "ca-central-1"     // Canada (Central)
    case saEast1 = "sa-east-1"           // South America (São Paulo)
}
