import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DraftIndicator: ObservableObject {
    @Published private(set) var hasText: Bool

    init(hasText: Bool) { self.hasText = hasText }

    func update(hasText: Bool) {
        guard self.hasText != hasText else { return }
        self.hasText = hasText
    }
}
