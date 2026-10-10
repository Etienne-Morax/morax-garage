import SwiftUI

/// Grid that never leaves an orphan card stranded in a half-empty row.
///
/// The column count is derived from the available width (`minItemWidth`,
/// capped by `maxColumns`), then items are spread as evenly as possible across
/// the needed rows: 3 items on 2 columns become one row of 2 and one row of 1
/// that fills the full width, 5 items on 3 columns become 3 + 2, etc.
/// Every item in a row receives the row's tallest height so cards line up.
public struct BalancedGrid: Layout {
    public var minItemWidth: CGFloat
    public var maxColumns: Int
    public var spacing: CGFloat

    public init(minItemWidth: CGFloat, maxColumns: Int = .max, spacing: CGFloat = 12) {
        self.minItemWidth = minItemWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
    }

    public struct Cache {
        var width: CGFloat = -1
        var rows: [Range<Int>] = []
        var rowHeights: [CGFloat] = []
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = resolvedWidth(proposal)
        computeRows(width: width, subviews: subviews, cache: &cache)
        let totalHeight = cache.rowHeights.reduce(0, +) + spacing * CGFloat(max(0, cache.rows.count - 1))
        return CGSize(width: width, height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty else { return }
        computeRows(width: bounds.width, subviews: subviews, cache: &cache)

        var y = bounds.minY
        for (rowIndex, row) in cache.rows.enumerated() {
            let itemWidth = columnWidth(for: row.count, in: bounds.width)
            let rowHeight = cache.rowHeights[rowIndex]
            var x = bounds.minX
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: itemWidth, height: rowHeight)
                )
                x += itemWidth + spacing
            }
            y += rowHeight + spacing
        }
    }

    // MARK: - Row computation

    private func resolvedWidth(_ proposal: ProposedViewSize) -> CGFloat {
        guard let width = proposal.width, width.isFinite else {
            return minItemWidth * CGFloat(min(maxColumns, 3)) + spacing * 2
        }
        return max(0, width)
    }

    /// Number of columns that fit `width`, bounded by `maxColumns` and `itemCount`.
    public func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        let fitting = Int((width + spacing) / (minItemWidth + spacing))
        return max(1, min(fitting, maxColumns, itemCount))
    }

    /// Items per row, spread evenly: the first rows take the extra items.
    public static func rowSizes(itemCount: Int, columns: Int) -> [Int] {
        guard itemCount > 0 else { return [] }
        let columns = max(1, columns)
        let rowCount = (itemCount + columns - 1) / columns
        let base = itemCount / rowCount
        let extra = itemCount % rowCount
        return (0..<rowCount).map { base + ($0 < extra ? 1 : 0) }
    }

    private func columnWidth(for itemsInRow: Int, in width: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, itemsInRow))
        return max(0, (width - spacing * (count - 1)) / count)
    }

    private func computeRows(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        if cache.width == width, !cache.rows.isEmpty { return }

        let columns = columnCount(for: width, itemCount: subviews.count)
        var rows: [Range<Int>] = []
        var start = 0
        for count in Self.rowSizes(itemCount: subviews.count, columns: columns) {
            rows.append(start..<(start + count))
            start += count
        }

        let heights = rows.map { row -> CGFloat in
            let itemWidth = columnWidth(for: row.count, in: width)
            return row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }.max() ?? 0
        }

        cache = Cache(width: width, rows: rows, rowHeights: heights)
    }
}
