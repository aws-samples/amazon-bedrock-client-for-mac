import Foundation

/// One visible model with its real, selectable invocation variants.
struct BedrockModelChoice: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var provider: String
    var variants: [BedrockModelDescriptor]
    var preferredID: String
    var isFavorite: Bool
    var preferred: BedrockModelDescriptor { variants.first { $0.id == preferredID } ?? variants[0] }

    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let text = ([name, provider, preferred.route.title] + variants.map(\.id)).joined(separator: " ")
        return words.allSatisfy { text.localizedStandardContains(String($0)) }
    }

    static func make(descriptors: [BedrockModelDescriptor], selectedID: String?, favoriteIDs: Set<String>, region: String) -> [Self] {
        let active = descriptors.filter { !$0.isHiddenFromSelection && !$0.needsProvisionedThroughput && !$0.id.isEmpty }
        let groups = Dictionary(grouping: active) { BedrockModelID.base($0.foundationID ?? $0.id) }
        let regionPrefix = region.hasPrefix("us-gov-") ? "us-gov." :
            region.hasPrefix("eu-") ? "eu." : region.hasPrefix("ap-") ? "apac." : "us."
        func rank(_ item: BedrockModelDescriptor) -> Int {
            if !item.isProfile && (item.inferenceTypes.contains("ON_DEMAND") || item.origin != .runtime) { return 0 }
            if item.id.hasPrefix(regionPrefix) { return 1 }
            if item.id.hasPrefix("global.") { return 2 }
            if item.isProfile { return 3 }
            return 4
        }
        return groups.map { base, entries in
            let variants = entries.sorted {
                if rank($0) != rank($1) { return rank($0) < rank($1) }
                return $0.id < $1.id
            }
            let preferred = variants.first { $0.id == selectedID } ??
                variants.first { favoriteIDs.contains($0.id) } ?? variants[0]
            let named = variants.first { !$0.isProfile } ?? preferred
            return Self(id: base, name: named.name, provider: named.provider, variants: variants,
                        preferredID: preferred.id, isFavorite: variants.contains { favoriteIDs.contains($0.id) })
        }.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            if $0.provider != $1.provider { return $0.provider.localizedStandardCompare($1.provider) == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func variantTitle(_ entry: BedrockModelDescriptor) -> String {
        if entry.id.hasPrefix("arn:") { return "Application profile" }
        if entry.origin == .mantle { return "Mantle" }
        if !entry.isProfile {
            return entry.inferenceTypes.contains("ON_DEMAND") ? "In this region" : "Automatic profile"
        }
        let prefix = String(entry.id.split(separator: ".").first ?? "")
        return ["us": "United States", "us-gov": "AWS GovCloud", "global": "Global",
                "eu": "Europe", "apac": "Asia Pacific", "jp": "Japan", "au": "Australia"][prefix] ?? "Inference profile"
    }
}
