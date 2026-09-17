import SwiftUI

struct MessageDisclosureView: View {
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.beginConversationInspection) private var beginInspection

    let header: String
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    var summary: String? = nil  // Optional summary to show in header
    var isStreaming: Bool = false  // Whether content is still streaming

    init(header: String, text: String, fontSize: CGFloat, searchRanges: [NSRange] = [], summary: String? = nil, isStreaming: Bool = false) {
        self.header = header
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.summary = summary
        self.isStreaming = isStreaming
    }

    // Display text for header - shows summary if available
    private var displayHeader: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        } else {
            return header
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Toggle button with summary
            Button(action: {
                beginInspection()
                isExpanded.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: fontSize - 4))
                        .foregroundColor(.secondary)

                    // Show animated dots only when streaming without summary
                    if isStreaming && summary == nil {
                        ThinkingDotsView(fontSize: fontSize)
                    } else {
                        Text(displayHeader)
                            .font(.system(size: fontSize - 1, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.borderless)

            // Expandable content
            if isExpanded {
                MessageMarkdownView(
                    text: text,
                    fontSize: fontSize - 2,
                    searchRanges: searchRanges,
                    isStreaming: isStreaming
                )
                .padding(.leading, fontSize / 2)
            }
        }
        .padding(.vertical, 6)
    }
}

// Separate view for animated dots using TimelineView
private struct ThinkingDotsView: View {
    let fontSize: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            let seconds = Calendar.current.component(.nanosecond, from: timeline.date) / 100_000_000
            let dotCount = (seconds % 3) + 1
            Text("Thinking" + String(repeating: ".", count: dotCount))
                .font(.system(size: fontSize - 1, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
