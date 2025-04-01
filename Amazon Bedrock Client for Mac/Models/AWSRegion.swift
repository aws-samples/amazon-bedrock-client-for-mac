//
//  AWSRegion.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation

enum AWSRegion: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case usEast1 = "us-east-1"           // US East (N. Virginia) - IAD
    case usEast2 = "us-east-2"           // US East (Ohio) - CMH
    case usWest1 = "us-west-1"           // US West (N. California) - SFO
    case usWest2 = "us-west-2"           // US West (Oregon) - PDX
    case usGovWest1 = "us-gov-west-1"    // GovCloud (US-West) - PDT
    case usGovEast1 = "us-gov-east-1"    // GovCloud (US-East) - OSU
    
    case caCentral1 = "ca-central-1"     // Canada (Central) - YUL
    
    case saEast1 = "sa-east-1"           // South America (São Paulo) - GRU
    
    case euWest1 = "eu-west-1"           // Europe (Ireland) - DUB
    case euWest2 = "eu-west-2"           // Europe (London) - LHR
    case euWest3 = "eu-west-3"           // Europe (Paris) - CDG
    case euCentral1 = "eu-central-1"     // Europe (Frankfurt) - FRA
    case euCentral2 = "eu-central-2"     // Europe (Zurich) - ZRH
    case euSouth1 = "eu-south-1"         // Europe (Milan) - MXP
    case euSouth2 = "eu-south-2"         // Europe (Spain) - ZAZ
    case euNorth1 = "eu-north-1"         // Europe (Stockholm) - ARN
    
    case apSouth1 = "ap-south-1"         // Asia Pacific (Mumbai) - BOM
    case apSouth2 = "ap-south-2"         // Asia Pacific (Hyderabad) - HYD
    case apNorthEast1 = "ap-northeast-1" // Asia Pacific (Tokyo) - NRT
    case apNorthEast2 = "ap-northeast-2" // Asia Pacific (Seoul) - ICN
    case apNorthEast3 = "ap-northeast-3" // Asia Pacific (Osaka) - KIX
    case apSouthEast1 = "ap-southeast-1" // Asia Pacific (Singapore) - SIN
    case apSouthEast2 = "ap-southeast-2" // Asia Pacific (Sydney) - SYD
}

// AWS 리전 상태
enum AWSRegionStatus: String {
    case available = "Available Now"
    case paused = "Paused"
}

// AWS 리전 정보 구조체
struct AWSRegionInfo {
    let id: String          // 리전 코드 (e.g., "us-east-1")
    let name: String        // 리전 이름 (e.g., "US East (N. Virginia)")
    let airportCode: String // 공항 코드 (e.g., "IAD")
    let status: AWSRegionStatus
}

// 리전 매핑 테이블
struct AWSRegionMapping {
    // 모든 리전 정보를 포함하는 배열
    static let allRegions: [AWSRegionInfo] = [
        AWSRegionInfo(id: "us-east-1", name: "US East (N. Virginia)", airportCode: "IAD", status: .available),
        AWSRegionInfo(id: "us-east-2", name: "US East (Ohio)", airportCode: "CMH", status: .available),
        AWSRegionInfo(id: "us-west-1", name: "US West (N. California)", airportCode: "SFO", status: .paused),
        AWSRegionInfo(id: "us-west-2", name: "US West (Oregon)", airportCode: "PDX", status: .available),
        AWSRegionInfo(id: "us-gov-west-1", name: "GovCloud (US-West)", airportCode: "PDT", status: .available),
        AWSRegionInfo(id: "us-gov-east-1", name: "GovCloud (US-East)", airportCode: "OSU", status: .available),
        
        AWSRegionInfo(id: "ca-central-1", name: "Canada (Central)", airportCode: "YUL", status: .available),
        
        AWSRegionInfo(id: "sa-east-1", name: "S. America (Sao Paulo)", airportCode: "GRU", status: .available),
        
        AWSRegionInfo(id: "eu-west-1", name: "Europe (Ireland)", airportCode: "DUB", status: .available),
        AWSRegionInfo(id: "eu-west-2", name: "Europe (London)", airportCode: "LHR", status: .available),
        AWSRegionInfo(id: "eu-west-3", name: "Europe (Paris)", airportCode: "CDG", status: .available),
        AWSRegionInfo(id: "eu-central-1", name: "Europe (Frankfurt)", airportCode: "FRA", status: .available),
        AWSRegionInfo(id: "eu-central-2", name: "Europe (Zurich)", airportCode: "ZRH", status: .available),
        AWSRegionInfo(id: "eu-south-1", name: "Europe (Milan)", airportCode: "MXP", status: .available),
        AWSRegionInfo(id: "eu-south-2", name: "Europe (Spain)", airportCode: "ZAZ", status: .available),
        AWSRegionInfo(id: "eu-north-1", name: "Europe (Stockholm)", airportCode: "ARN", status: .available),
        
        AWSRegionInfo(id: "ap-south-1", name: "Asia Pacific (Mumbai)", airportCode: "BOM", status: .available),
        AWSRegionInfo(id: "ap-south-2", name: "Asia Pacific (Hyderabad)", airportCode: "HYD", status: .available),
        AWSRegionInfo(id: "ap-northeast-1", name: "Asia Pacific (Tokyo)", airportCode: "NRT", status: .available),
        AWSRegionInfo(id: "ap-northeast-2", name: "Asia Pacific (Seoul)", airportCode: "ICN", status: .available),
        AWSRegionInfo(id: "ap-northeast-3", name: "Asia Pacific (Osaka)", airportCode: "KIX", status: .available),
        AWSRegionInfo(id: "ap-southeast-1", name: "Asia Pacific (Singapore)", airportCode: "SIN", status: .available),
        AWSRegionInfo(id: "ap-southeast-2", name: "Asia Pacific (Sydney)", airportCode: "SYD", status: .available)
    ]
    
    // ID로 리전 정보 조회
    static func getRegionInfo(for id: String) -> AWSRegionInfo? {
        return allRegions.first { $0.id == id }
    }
    
    // 공항 코드로 리전 정보 조회
    static func getRegionInfo(byAirportCode code: String) -> AWSRegionInfo? {
        return allRegions.first { $0.airportCode == code }
    }
}

// AWSRegion enum 확장
extension AWSRegion {
    // 리전 정보 조회
    var info: AWSRegionInfo? {
        return AWSRegionMapping.getRegionInfo(for: self.rawValue)
    }
    
    // 리전 이름
    var name: String {
        return info?.name ?? rawValue
    }
    
    // 공항 코드
    var airportCode: String {
        return info?.airportCode ?? ""
    }
    
    // 리전 상태
    var status: AWSRegionStatus {
        return info?.status ?? .available
    }
    
    // 사용 가능한 리전만 필터링
    static var availableRegions: [AWSRegion] {
        return AWSRegion.allCases.filter { $0.status == .available }
    }
}

enum AWSRegionSection: String, CaseIterable, Identifiable {
    case northAmerica = "North America"
    case europe = "Europe"
    case asiaPacific = "Asia Pacific"
    case other = "Other Regions"
    case govCloud = "GovCloud"
    
    var id: String { self.rawValue }
}

extension AWSRegion {
    // 각 리전이 속한 섹션 반환
    var section: AWSRegionSection {
        switch self {
        case .usEast1, .usEast2, .usWest1, .usWest2, .caCentral1:
            return .northAmerica
        case .euWest1, .euWest2, .euWest3, .euCentral1, .euCentral2, .euSouth1, .euSouth2, .euNorth1:
            return .europe
        case .apNorthEast1, .apNorthEast2, .apNorthEast3, .apSouthEast1, .apSouthEast2, .apSouth1, .apSouth2:
            return .asiaPacific
        case .saEast1:
            return .other
        case .usGovEast1, .usGovWest1:
            return .govCloud
        }
    }
    
    // 특정 섹션에 속하는 리전 가져오기
    static func regions(in section: AWSRegionSection, includePaused: Bool = false) -> [AWSRegion] {
        return AWSRegion.allCases.filter {
            $0.section == section && (includePaused || $0.status != .paused)
        }
    }
}
