import SwiftUI
import AppKit
import MoraxCockpitKit

/// Chrome colours of the treemap, resolved once instead of per tile per frame.
private enum TreemapPalette {
    static let darkBackground = Color(hex: "#0B0C1E")
    static let lightBackground = Color(hex: "#F8FAFC")

    static let darkContainerFill = Color(hex: "#13122B").opacity(0.85)
    static let lightContainerFill = Color(hex: "#F1F5F9").opacity(0.9)

    static let darkContainerBorder = Color(hex: "#2B2857")
    static let lightContainerBorder = Color(hex: "#CBD5E1")

    static let darkHeaderText = Color(hex: "#CBD5E1")
    static let lightHeaderText = Color(hex: "#334155")

    static let darkTileBorder = Color.black.opacity(0.4)
    static let lightTileBorder = Color.black.opacity(0.15)

    static func selectionBorder(isDark: Bool) -> Color {
        isDark ? Color.white : Color(hex: "#0F172A")
    }
    static func tileHoverBorder(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.9) : Color(hex: "#0F172A").opacity(0.85)
    }
    static func containerHoverBorder(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.85) : Color(hex: "#0F172A").opacity(0.75)
    }
}

public struct TreemapCanvasView: View {
    public let renderItems: [TreemapRenderItem]
    public let selectedNode: StorageNode?
    public let onSelectNode: (StorageNode) -> Void
    public let onDoubleClickNode: (StorageNode) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredItem: TreemapRenderItem? = nil
    @State private var hoverLocation: CGPoint = .zero

    public init(
        renderItems: [TreemapRenderItem],
        selectedNode: StorageNode?,
        onSelectNode: @escaping (StorageNode) -> Void,
        onDoubleClickNode: @escaping (StorageNode) -> Void
    ) {
        self.renderItems = renderItems
        self.selectedNode = selectedNode
        self.onSelectNode = onSelectNode
        self.onDoubleClickNode = onDoubleClickNode
    }

    public var body: some View {
        GeometryReader { geometry in
            let isDark = colorScheme == .dark
            ZStack(alignment: .topLeading) {
                // Base layer. It deliberately does not read `hoveredItem`: doing so
                // redrew every tile on each mouse move.
                Canvas { context, size in
                    drawBackground(in: &context, size: size, isDark: isDark)
                    drawContainers(in: &context, isDark: isDark)
                    drawLeaves(in: &context, isDark: isDark)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location
                        let hit = itemAt(point: location)
                        if hit?.id != hoveredItem?.id {
                            hoveredItem = hit
                        }
                    case .ended:
                        hoveredItem = nil
                    }
                }
                .gesture(
                    TapGesture(count: 2).onEnded {
                        if let hit = itemAt(point: hoverLocation) {
                            onDoubleClickNode(hit.node)
                        }
                    }
                    .exclusively(
                        before: TapGesture(count: 1).onEnded {
                            if let hit = itemAt(point: hoverLocation) {
                                onSelectNode(hit.node)
                            }
                        }
                    )
                )

                // Hover layer. Only this canvas is invalidated as the pointer moves.
                Canvas { context, _ in
                    guard let hovered = hoveredItem else { return }
                    drawHoverHighlight(for: hovered, in: &context, isDark: isDark)
                }
                .allowsHitTesting(false)

                // Floating Hover Tooltip
                if let hovered = hoveredItem {
                    hoverTooltip(item: hovered)
                        .position(tooltipPosition(for: hoverLocation, in: geometry.size))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Base layer

    private func drawBackground(in context: inout GraphicsContext, size: CGSize, isDark: Bool) {
        let bgRect = CGRect(origin: .zero, size: size)
        let background = isDark ? TreemapPalette.darkBackground : TreemapPalette.lightBackground
        context.fill(Path(bgRect), with: .color(background))
    }

    /// Depth 0, 1 and 2 containers that have visible children.
    private func drawContainers(in context: inout GraphicsContext, isDark: Bool) {
        let containerFill = isDark ? TreemapPalette.darkContainerFill : TreemapPalette.lightContainerFill
        let idleBorder = isDark ? TreemapPalette.darkContainerBorder : TreemapPalette.lightContainerBorder
        let headerColor = isDark ? TreemapPalette.darkHeaderText : TreemapPalette.lightHeaderText

        for item in renderItems where item.hasVisibleChildren {
            let rect = item.rect
            guard rect.width > 0 && rect.height > 0 else { continue }

            let isSelected = (selectedNode?.id == item.node.id)

            context.fill(Path(rect), with: .color(containerFill))
            context.stroke(
                Path(rect),
                with: .color(isSelected ? TreemapPalette.selectionBorder(isDark: isDark) : idleBorder),
                lineWidth: isSelected ? 2.5 : 1.0
            )

            guard rect.width >= 70 && rect.height >= 38 else { continue }
            let headerRect = CGRect(
                x: rect.origin.x + 4,
                y: rect.origin.y + 2,
                width: rect.width - 8,
                height: 13
            )
            let title = "\(item.node.name) (\(item.node.formattedAllocatedSize))"
            let headerText = Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(headerColor)
            context.draw(headerText, in: headerRect)
        }
    }

    /// Files, and deep folders drawn without sub-render.
    private func drawLeaves(in context: inout GraphicsContext, isDark: Bool) {
        let idleBorder = isDark ? TreemapPalette.darkTileBorder : TreemapPalette.lightTileBorder

        for item in renderItems where !item.hasVisibleChildren {
            let rect = item.rect
            guard rect.width > 0 && rect.height > 0 else { continue }

            let isSelected = (selectedNode?.id == item.node.id)
            let path = Path(rect)

            context.fill(path, with: .color(Self.tileFill(for: item, isDark: isDark, isSelected: isSelected, isHovered: false)))
            context.stroke(
                path,
                with: .color(isSelected ? TreemapPalette.selectionBorder(isDark: isDark) : idleBorder),
                lineWidth: isSelected ? 2.5 : 0.5
            )

            drawTileLabels(for: item, in: &context)
        }
    }

    private func drawTileLabels(for item: TreemapRenderItem, in context: inout GraphicsContext) {
        let rect = item.rect
        guard rect.width >= 40 && rect.height >= 20 else { return }

        let padding: CGFloat = 3.0
        let labelRect = CGRect(
            x: rect.origin.x + padding,
            y: rect.origin.y + padding,
            width: rect.width - (padding * 2),
            height: min(14, rect.height - (padding * 2))
        )

        let nameText = Text(item.node.name)
            .font(.system(size: min(10, max(7.5, rect.height / 3.5)), weight: .bold))
            .foregroundStyle(Color.white)
        context.draw(nameText, in: labelRect)

        guard rect.height >= 34 && rect.width >= 55 else { return }
        let sizeRect = CGRect(
            x: rect.origin.x + padding,
            y: rect.origin.y + padding + 12,
            width: rect.width - (padding * 2),
            height: 12
        )
        let sizeText = Text(item.node.formattedAllocatedSize)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))
        context.draw(sizeText, in: sizeRect)
    }

    // MARK: - Hover layer

    private func drawHoverHighlight(
        for item: TreemapRenderItem,
        in context: inout GraphicsContext,
        isDark: Bool
    ) {
        let rect = item.rect
        guard rect.width > 0 && rect.height > 0 else { return }

        // A selected tile already draws its own, stronger, treatment.
        guard selectedNode?.id != item.node.id else { return }

        let path = Path(rect)

        if item.hasVisibleChildren {
            context.stroke(path, with: .color(TreemapPalette.containerHoverBorder(isDark: isDark)), lineWidth: 1.5)
            return
        }

        // Repaint the tile at its hovered opacity, then its brighter border.
        context.fill(path, with: .color(Self.tileFill(for: item, isDark: isDark, isSelected: false, isHovered: true)))
        context.stroke(path, with: .color(TreemapPalette.tileHoverBorder(isDark: isDark)), lineWidth: 1.5)
        drawTileLabels(for: item, in: &context)
    }

    private static func tileFill(
        for item: TreemapRenderItem,
        isDark: Bool,
        isSelected: Bool,
        isHovered: Bool
    ) -> Color {
        let opacity: Double
        if isDark {
            opacity = isSelected ? 1.0 : (isHovered ? 0.95 : 0.82)
        } else {
            opacity = isSelected ? 0.98 : (isHovered ? 0.92 : 0.78)
        }
        return item.categoryColor.opacity(opacity)
    }

    // MARK: - Hit testing and tooltip

    private func itemAt(point: CGPoint) -> TreemapRenderItem? {
        // Find the deepest matching item that contains point
        var bestMatch: TreemapRenderItem? = nil
        var maxDepth = -1

        for item in renderItems {
            if item.rect.contains(point) {
                // If it's a leaf item (no visible children), give it priority
                let depthScore = item.depth * 2 + (item.hasVisibleChildren ? 0 : 1)
                if depthScore >= maxDepth {
                    maxDepth = depthScore
                    bestMatch = item
                }
            }
        }
        return bestMatch
    }

    private func tooltipPosition(for point: CGPoint, in size: CGSize) -> CGPoint {
        var x = point.x + 95
        var y = point.y - 45

        if x + 160 > size.width {
            x = point.x - 110
        }
        if y - 35 < 0 {
            y = point.y + 45
        }
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func hoverTooltip(item: TreemapRenderItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.category.iconName)
                    .foregroundStyle(item.categoryColor)
                    .font(.system(size: 11, weight: .bold))

                Text(item.node.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(item.node.formattedAllocatedSize)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textPrimary)

                Text(item.category.rawValue)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(item.categoryColor)
            }

            if item.node.isDirectory {
                Text("\(item.node.itemCount) items in folder")
                    .font(.system(size: 9.5))
                    .foregroundStyle(MoraxTheme.textMuted)
            }

            if let parentName = item.node.parent?.name, !parentName.isEmpty {
                Text("in \(parentName)")
                    .font(.system(size: 9))
                    .foregroundStyle(MoraxTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MoraxTheme.surface)
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MoraxTheme.border, lineWidth: 1)
                )
        )
    }
}
