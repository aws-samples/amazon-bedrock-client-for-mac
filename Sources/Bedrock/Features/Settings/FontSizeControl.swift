import AppKit
import SwiftUI
import MCP

struct FontSizeControl: View {
    @AppStorage("adjustedFontSize") private var adjustedFontSize: Int = -1

    // Map internal values to display values (0-12 scale)
    private var displayValue: Int {
        adjustedFontSize + 5  // -4 becomes 1, -1 becomes 4, 0 becomes 5, 8 becomes 13
    }

    private func setDisplayValue(_ value: Int) {
        adjustedFontSize = value - 5  // Convert back to internal scale
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if adjustedFontSize > -4 {
                    adjustedFontSize -= 1
                }
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .disabled(adjustedFontSize <= -4)
            .help("Decrease text size")
            .accessibilityLabel("Decrease text size")

            Text(fontSizeLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 50)

            Button {
                if adjustedFontSize < 8 {
                    adjustedFontSize += 1
                }
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .disabled(adjustedFontSize >= 8)
            .help("Increase text size")
            .accessibilityLabel("Increase text size")
        }
    }

    private var fontSizeLabel: String {
        let displayNum = displayValue
        if adjustedFontSize == -1 {
            return "Default"
        } else {
            return "\(displayNum)"
        }
    }
}

// MARK: - System Prompt Section (for GeneralSettingsView)
