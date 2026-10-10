import Foundation
import SwiftUI

public struct TreemapRenderItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let node: StorageNode
    public let rect: CGRect
    public let depth: Int
    public let category: StorageCategory
    public let percentageOfTotal: Double
    public let isContainer: Bool
    public let hasVisibleChildren: Bool

    /// Fill colour for this tile, resolved once at layout time.
    ///
    /// The canvas redraws every tile on each frame, so resolving the category colour
    /// inside the drawing loop made the cost scale with tiles times frames rather
    /// than with the layout.
    public let categoryColor: Color
    
    public init(
        id: UUID = UUID(),
        node: StorageNode,
        rect: CGRect,
        depth: Int = 0,
        category: StorageCategory,
        percentageOfTotal: Double = 0,
        isContainer: Bool = false,
        hasVisibleChildren: Bool = false
    ) {
        self.categoryColor = category.color
        self.id = id
        self.node = node
        self.rect = rect
        self.depth = depth
        self.category = category
        self.percentageOfTotal = percentageOfTotal
        self.isContainer = isContainer
        self.hasVisibleChildren = hasVisibleChildren
    }
}

public struct TreemapLayoutEngine: Sendable {
    
    public static func computeLayout(
        for rootNode: StorageNode,
        in bounds: CGRect,
        maxDepth: Int = 3,
        minPixelSize: CGFloat = 3.0
    ) -> [TreemapRenderItem] {
        guard bounds.width > 0 && bounds.height > 0 else { return [] }
        
        // Tiles are sized by bytes actually occupying the disk. Weighting by logical size
        // would let a folder of cloud placeholders — terabytes on paper, nothing on disk —
        // swallow the whole map.
        let children = rootNode.children.filter { $0.allocatedSizeBytes > 0 }
        guard !children.isEmpty else {
            // Root has no sizable children; return single full-bounds item
            return [
                TreemapRenderItem(
                    id: rootNode.id,
                    node: rootNode,
                    rect: bounds,
                    depth: 0,
                    category: rootNode.category,
                    percentageOfTotal: 1.0,
                    isContainer: false,
                    hasVisibleChildren: false
                )
            ]
        }
        
        let totalSize = max(1, children.reduce(Int64(0)) { $0 + $1.allocatedSizeBytes })
        
        // Sort children descending
        let sortedChildren = children.sorted { $0.allocatedSizeBytes > $1.allocatedSizeBytes }
        
        return layoutChildren(
            children: sortedChildren,
            totalSize: totalSize,
            bounds: bounds,
            depth: 0,
            maxDepth: maxDepth,
            minPixelSize: minPixelSize
        )
    }
    
    private static func layoutChildren(
        children: [StorageNode],
        totalSize: Int64,
        bounds: CGRect,
        depth: Int,
        maxDepth: Int,
        minPixelSize: CGFloat
    ) -> [TreemapRenderItem] {
        guard !children.isEmpty && bounds.width >= minPixelSize && bounds.height >= minPixelSize else {
            return []
        }
        
        var result: [TreemapRenderItem] = []
        let totalArea = bounds.width * bounds.height
        
        // Compute normalized areas for all children
        let itemsWithAreas: [(node: StorageNode, area: CGFloat, weight: Int64)] = children.map { node in
            let weight = node.allocatedSizeBytes
            let area = totalArea * CGFloat(Double(weight) / Double(totalSize))
            return (node, area, weight)
        }
        
        // Run squarified layout
        let rects = squarify(items: itemsWithAreas.map { $0.area }, bounds: bounds)
        
        for (index, rect) in rects.enumerated() {
            guard index < itemsWithAreas.count else { break }
            let item = itemsWithAreas[index]
            let percentage = Double(item.weight) / Double(totalSize)
            
            // Packages are walked for their size but stay a single tile: nobody navigates
            // the inside of a .app or a .photoslibrary on a storage map.
            let canExpandChildren = depth < maxDepth &&
                item.node.isDirectory &&
                !item.node.isPackage &&
                !item.node.children.isEmpty &&
                rect.width >= 18 &&
                rect.height >= 18
            
            let renderItem = TreemapRenderItem(
                id: item.node.id,
                node: item.node,
                rect: rect,
                depth: depth,
                category: item.node.category,
                percentageOfTotal: percentage,
                isContainer: item.node.isDirectory,
                hasVisibleChildren: canExpandChildren
            )
            result.append(renderItem)
            
            // Nested layout if directory and has expandable space
            if canExpandChildren {
                let headerHeight: CGFloat = (rect.height >= 40 && rect.width >= 50) ? 14.0 : 2.0
                let innerPadding: CGFloat = 2.0
                let innerBounds = CGRect(
                    x: rect.origin.x + innerPadding,
                    y: rect.origin.y + headerHeight,
                    width: max(0, rect.width - (innerPadding * 2)),
                    height: max(0, rect.height - headerHeight - innerPadding)
                )
                
                let subChildren = item.node.children.filter { $0.allocatedSizeBytes > 0 }
                if !subChildren.isEmpty && innerBounds.width >= minPixelSize && innerBounds.height >= minPixelSize {
                    let subTotal = max(1, subChildren.reduce(Int64(0)) { $0 + $1.allocatedSizeBytes })
                    let sortedSubChildren = subChildren.sorted {
                        $0.allocatedSizeBytes > $1.allocatedSizeBytes
                    }
                    
                    let nestedItems = layoutChildren(
                        children: sortedSubChildren,
                        totalSize: subTotal,
                        bounds: innerBounds,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        minPixelSize: minPixelSize
                    )
                    result.append(contentsOf: nestedItems)
                }
            }
        }
        
        return result
    }
    
    /// Core Squarified Treemap layout algorithm (Bruls, Huizing, van Wijk)
    public static func squarify(items: [CGFloat], bounds: CGRect) -> [CGRect] {
        var results: [CGRect] = []
        var remainingBounds = bounds
        var row: [CGFloat] = []
        var remainingItems = items
        
        while !remainingItems.isEmpty {
            let nextItem = remainingItems.removeFirst()
            
            if row.isEmpty {
                row.append(nextItem)
            } else {
                let shortestSide = min(remainingBounds.width, remainingBounds.height)
                let currentWorst = worstAspectRatio(row: row, sideLength: shortestSide)
                var candidateRow = row
                candidateRow.append(nextItem)
                let candidateWorst = worstAspectRatio(row: candidateRow, sideLength: shortestSide)
                
                if candidateWorst <= currentWorst {
                    row = candidateRow
                } else {
                    // Current row is optimal, lay it out
                    let (rowRects, newRemainingBounds) = layoutRow(row: row, bounds: remainingBounds)
                    results.append(contentsOf: rowRects)
                    remainingBounds = newRemainingBounds
                    row = [nextItem]
                }
            }
        }
        
        if !row.isEmpty {
            let (rowRects, _) = layoutRow(row: row, bounds: remainingBounds)
            results.append(contentsOf: rowRects)
        }
        
        return results
    }
    
    /// Calculates the worst (maximum) aspect ratio for a row of rectangle areas along side length s
    private static func worstAspectRatio(row: [CGFloat], sideLength: CGFloat) -> CGFloat {
        guard sideLength > 0, !row.isEmpty else { return .infinity }
        let totalRowArea = row.reduce(0, +)
        guard totalRowArea > 0 else { return .infinity }
        
        let sideSq = sideLength * sideLength
        let totalRowAreaSq = totalRowArea * totalRowArea
        
        var maxRatio: CGFloat = 0
        for area in row {
            guard area > 0 else { continue }
            let r1 = (sideSq * area) / totalRowAreaSq
            let r2 = totalRowAreaSq / (sideSq * area)
            let ratio = max(r1, r2)
            if ratio > maxRatio {
                maxRatio = ratio
            }
        }
        
        return maxRatio
    }
    
    /// Lays out a row of rectangles in the given bounds and returns remaining bounds
    private static func layoutRow(row: [CGFloat], bounds: CGRect) -> ([CGRect], CGRect) {
        guard !row.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return ([], bounds)
        }
        
        var rowRects: [CGRect] = []
        let totalRowArea = row.reduce(0, +)
        let isHorizontalSplit = bounds.width < bounds.height // Split along height
        
        if isHorizontalSplit {
            // Row extends across width, stacked along height
            let rowHeight = totalRowArea / bounds.width
            var currentX = bounds.origin.x
            
            for area in row {
                let itemWidth = rowHeight > 0 ? (area / rowHeight) : 0
                let rect = CGRect(
                    x: currentX,
                    y: bounds.origin.y,
                    width: max(0, itemWidth),
                    height: max(0, rowHeight)
                )
                rowRects.append(rect)
                currentX += itemWidth
            }
            
            let newRemainingBounds = CGRect(
                x: bounds.origin.x,
                y: bounds.origin.y + rowHeight,
                width: bounds.width,
                height: max(0, bounds.height - rowHeight)
            )
            return (rowRects, newRemainingBounds)
        } else {
            // Row extends across height, stacked along width
            let rowWidth = totalRowArea / bounds.height
            var currentY = bounds.origin.y
            
            for area in row {
                let itemHeight = rowWidth > 0 ? (area / rowWidth) : 0
                let rect = CGRect(
                    x: bounds.origin.x,
                    y: currentY,
                    width: max(0, rowWidth),
                    height: max(0, itemHeight)
                )
                rowRects.append(rect)
                currentY += itemHeight
            }
            
            let newRemainingBounds = CGRect(
                x: bounds.origin.x + rowWidth,
                y: bounds.origin.y,
                width: max(0, bounds.width - rowWidth),
                height: bounds.height
            )
            return (rowRects, newRemainingBounds)
        }
    }
}
