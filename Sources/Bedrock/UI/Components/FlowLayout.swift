import SwiftUI

/// Wraps compact items without creating a second scroll view in the transcript.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func measure(_ subviews: Subviews, width: CGFloat?) -> (sizes: [CGSize], rows: [Row]) {
        let limit = max(1, width ?? .infinity)
        let sizes = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)) }
        var rows: [Row] = []
        var row = Row()
        for index in sizes.indices {
            let size = sizes[index]
            let extra = row.indices.isEmpty ? size.width : spacing + size.width
            if !row.indices.isEmpty, row.width + extra > limit {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return (sizes, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = measure(subviews, width: proposal.width)
        return .init(width: layout.rows.map(\.width).max() ?? 0,
                     height: layout.rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, layout.rows.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = measure(subviews, width: bounds.width)
        var y = bounds.minY
        for row in layout.rows {
            var x = bounds.minX + (alignment == .trailing ? bounds.width - row.width : 0)
            for index in row.indices {
                subviews[index].place(at: .init(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(layout.sizes[index]))
                x += layout.sizes[index].width + spacing
            }
            y += row.height + spacing
        }
    }
}
