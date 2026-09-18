import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()
    @Published var models: [ChatModel] = []
    @Published private(set) var organized: [String: [ChatModel]] = [:]
    @Published private(set) var descriptors: [BedrockModelDescriptor] = []
    @Published private(set) var importedProfiles: [BedrockModelDescriptor] = []
    @Published private(set) var refreshedAt: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var requestID = UUID()
    private var activeIdentity: String?
    private var importedProfileFile: JSONFile<[BedrockModelDescriptor]>?
    private struct Cache: Codable {
        var updatedAt: Date
        var descriptors: [BedrockModelDescriptor]
    }
    var foundationModels: [BedrockModelDescriptor] {
        descriptors.filter { !$0.isProfile }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func descriptor(_ id: String) -> BedrockModelDescriptor? {
        descriptors.first { $0.id == id } ?? descriptors.first { $0.id == BedrockModelID.base(id) }
    }
    func model(_ id: String) -> ChatModel {
        models.first { $0.id == id } ?? ChatModel(id: id, chatId: id, name: descriptor(id)?.name ?? id,
            title: descriptor(id)?.name ?? id, description: id, provider: descriptor(id)?.provider ?? BedrockModelID.providerName(id), lastMessageDate: Date())
    }
    func invocationModel(_ descriptor: BedrockModelDescriptor) -> ChatModel {
        model(BedrockCapabilityRegistry.shared.invocationID(descriptor.id, region: PreferencesStore.shared.selectedRegion.rawValue))
    }
    var defaultModel: ChatModel? {
        let settings = PreferencesStore.shared
        let requested = settings.defaultModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty, !BedrockModelID.isLegacy(requested),
           !BedrockModelID.isExcludedFromSelection(requested),
           descriptor(requested)?.isHiddenFromSelection != true {
            // An explicit custom model/profile ARN must remain usable even when
            // the caller lacks permission to list the catalog.
            if let descriptor = descriptor(requested), !descriptor.isProfile { return invocationModel(descriptor) }
            return model(requested)
        }
        return models.first { settings.favoriteModelIds.contains($0.id) && descriptor($0.id)?.isConversation == true }
            ?? models.first { $0.name.localizedStandardContains("Sonnet") && $0.id.hasPrefix("global.") }
            ?? models.first { $0.id.contains("nova-micro") }
            ?? models.first { descriptor($0.id)?.isConversation == true }
    }

    func refresh(backend: BedrockService) async {
        if ValidationMode.isOffline {
            install(BedrockBundledCatalog.records.flatMap { $0.descriptors(in: backend.region) } +
                    BedrockMantleCatalog.descriptors(in: backend.region), region: backend.region)
            errorMessage = nil
            return
        }
        let id = UUID()
        requestID = id
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        errorMessage = nil
        let region = backend.region
        let file = activateConnection(backend)
        async let foundations = backend.listFoundationModels()
        async let profiles = backend.listInferenceProfilesResult()
        let (foundationResult, profileResult) = await (foundations, profiles)
        guard requestID == id, !Task.isCancelled else { return }
        var warnings: [String] = []
        var entries: [BedrockModelDescriptor]
        switch foundationResult {
        case .success(let summaries):
            entries = summaries.compactMap { summary in
                guard let id = summary.modelId, !id.isEmpty else { return nil }
                return BedrockModelDescriptor(id: id, name: summary.modelName ?? id,
                    provider: summary.providerName ?? BedrockModelID.providerName(id),
                    inputModalities: summary.inputModalities?.map(\.rawValue) ?? [],
                    outputModalities: summary.outputModalities?.map(\.rawValue) ?? [],
                    inferenceTypes: summary.inferenceTypesSupported?.map(\.rawValue) ?? [],
                    streaming: summary.responseStreamingSupported, lifecycle: summary.modelLifecycle?.status?.rawValue)
            }
        case .failure(let error):
            entries = descriptors.filter { !$0.isProfile && $0.origin == .runtime }
            warnings.append("Model refresh: \(error.localizedDescription)")
        }
        let foundationEntries = entries + BedrockBundledCatalog.records.flatMap { $0.descriptors(in: region) }
        switch profileResult {
        case .success(let summaries):
            entries += summaries.compactMap { profile in
                try? BedrockInferenceProfile.descriptor(id: profile.inferenceProfileId, arn: profile.inferenceProfileArn,
                    name: profile.inferenceProfileName, type: profile.type?.rawValue, status: profile.status?.rawValue,
                    modelARNs: profile.models?.compactMap(\.modelArn) ?? [], foundations: foundationEntries)
            }
        case .failure(let error):
            entries += descriptors.filter { $0.isProfile }
            warnings.append("Inference profile refresh: \(error.localizedDescription)")
        }
        entries += importedProfiles + BedrockMantleCatalog.descriptors(in: region)
        install(entries, region: region)
        if warnings.isEmpty {
            refreshedAt = Date()
            do { try file.save(Cache(updatedAt: refreshedAt!, descriptors: descriptors)) }
            catch { warnings.append("Could not save the local model catalog: \(error.localizedDescription)") }
        }
        errorMessage = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    /// Imports only the requested profile. Broad list permissions are not required.
    func addInferenceProfile(_ arn: String, backend: BedrockService) async throws -> ChatModel {
        _ = activateConnection(backend)
        let identity = activeIdentity
        let profile = try await backend.getInferenceProfile(arn)
        try Task.checkCancellation()
        guard activeIdentity == identity else {
            throw LocalOperationError.invalid("The AWS connection changed. Add the profile again using the current connection.")
        }
        let foundations = descriptors + BedrockBundledCatalog.records.flatMap { $0.descriptors(in: backend.region) }
        let descriptor = try BedrockInferenceProfile.descriptor(id: profile.inferenceProfileId, arn: profile.inferenceProfileArn,
            name: profile.inferenceProfileName, type: profile.type?.rawValue, status: profile.status?.rawValue,
            modelARNs: profile.models?.compactMap(\.modelArn) ?? [], foundations: foundations)
        guard !descriptor.isHiddenFromSelection else {
            throw LocalOperationError.invalid("This profile uses a retired or unavailable model.")
        }
        let updated = importedProfiles.filter { $0.id != descriptor.id } + [descriptor]
        try importedProfileFile?.save(updated)
        importedProfiles = updated
        install(descriptors.filter { $0.id != descriptor.id } + [descriptor], region: backend.region)
        return model(descriptor.id)
    }

    func removeImportedProfile(_ id: String, region: String) throws {
        let updated = importedProfiles.filter { $0.id != id }
        try importedProfileFile?.save(updated)
        importedProfiles = updated
        install(descriptors.filter { $0.id != id }, region: region)
    }

    private func activateConnection(_ backend: BedrockService) -> JSONFile<Cache> {
        let identity = "\(backend.region)|\(backend.profile)|\(backend.endpoint)|\(backend.runtimeEndpoint)|\(PreferencesStore.shared.bedrockApiKey.isEmpty)"
        let hash = SHA256.hash(data: Data(identity.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let file = JSONFile<Cache>(url: AppStore.shared.directory.appendingPathComponent("model-catalog-\(hash).json"))
        if activeIdentity != identity {
            activeIdentity = identity
            importedProfileFile = JSONFile(url: AppStore.shared.directory.appendingPathComponent("inference-profiles-\(hash).json"))
            importedProfiles = (try? importedProfileFile?.load()) ?? []
            if let cached = try? file.load() {
                install(cached.descriptors + importedProfiles, region: backend.region)
                refreshedAt = cached.updatedAt
            } else {
                install(BedrockBundledCatalog.records.flatMap { $0.descriptors(in: backend.region) } +
                        BedrockMantleCatalog.descriptors(in: backend.region) + importedProfiles, region: backend.region)
                refreshedAt = nil
            }
        }
        return file
    }

    private func install(_ entries: [BedrockModelDescriptor], region: String) {
        var seen = Set<String>()
        descriptors = entries.filter { !$0.isHiddenFromSelection && !$0.id.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        BedrockCapabilityRegistry.shared.replace(region: region, descriptors: descriptors)
        models = descriptors.filter { !$0.needsProvisionedThroughput }.map {
            ChatModel(id: $0.id, chatId: $0.id, name: $0.name, title: $0.name,
                      description: $0.id, provider: $0.provider, lastMessageDate: Date())
        }
        organized = Dictionary(grouping: models, by: \.provider)
        PreferencesStore.shared.availableModels = models
    }
}
