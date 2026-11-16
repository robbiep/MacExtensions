import Foundation
import CoreGraphics

/// Converts between AX/CoreGraphics (top-left origin) and AppKit (bottom-left origin) coordinates.
public struct DisplayGeometry: Equatable, Sendable {
    public var primaryHeight: CGFloat
    public var screenFrames: [CGRect]

    public init(primaryHeight: CGFloat, screenFrames: [CGRect]) {
        self.primaryHeight = primaryHeight
        self.screenFrames = screenFrames
    }

    public func appKitRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public func topLeftRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public func localRect(_ rect: CGRect, inScreen screenFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    /// Returns index of the screen with greatest intersection area, or nil if none intersect.
    public func screenIndex(forAppKitRect rect: CGRect) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (i, frame) in screenFrames.enumerated() {
            let inter = frame.intersection(rect)
            guard !inter.isNull, inter.width > 0, inter.height > 0 else { continue }
            let area = inter.width * inter.height
            if best == nil || area > best!.area {
                best = (i, area)
            }
        }
        return best?.index
    }
}

/// Computes top-left Core Graphics pill bounds for covering native Spaces bar labels
/// in both compact text-strip mode and expanded thumbnail mode without neighbor overlap.
public enum SpacePillLayout {
    public static let compactMaxHeight: CGFloat = 42
    public static let defaultExpandedLabelHeight: CGFloat = 21
    public static let defaultCompactLabelHeight: CGFloat = 22
    public static let pillHorizontalPadding: CGFloat = 20
    public static let nativeMaskPadding: CGFloat = 12
    public static let minInterPillGap: CGFloat = 6

    public struct LayoutItem: Equatable, Sendable {
        public var space: SpaceItem
        public var displayTextWidth: CGFloat
        public var nativeTextWidth: CGFloat

        public init(space: SpaceItem, displayTextWidth: CGFloat, nativeTextWidth: CGFloat) {
            self.space = space
            self.displayTextWidth = displayTextWidth
            self.nativeTextWidth = nativeTextWidth
        }
    }

    public enum BarMode: Equatable, Sendable {
        case compact
        case expanded
    }

    /// Detects whether a row of Space items is visually in compact text-strip mode or expanded thumbnail mode.
    public static func detectMode(for rowItems: [SpaceItem]) -> BarMode {
        guard let first = rowItems.first else { return .expanded }
        if first.frame.height <= compactMaxHeight { return .compact }
        if first.frame.midY < 90 { return .compact }

        // In compact mode on macOS 27 WindowManager, AXSize may remain 168x129 while AXPosition.x
        // follows variable text-width spacing (non-uniform gaps between centers).
        if rowItems.count >= 3 {
            let strides = zip(rowItems, rowItems.dropFirst()).map { $1.frame.midX - $0.frame.midX }
            if let minStride = strides.min(), let maxStride = strides.max(), (maxStride - minStride) > 14 {
                return .compact
            }
        }
        return .expanded
    }

    /// Computes non-overlapping top-left CG rects for every item in `items` (matched 1-to-1 by index).
    public static func pillFrames(for items: [LayoutItem]) -> [CGRect] {
        guard !items.isEmpty else { return [] }

        // Group into horizontal rows (supports multi-display Spaces bars).
        let sortedIndices = items.indices.sorted { a, b in
            let fa = items[a].space.frame
            let fb = items[b].space.frame
            if abs(fa.midY - fb.midY) > 40 { return fa.midY < fb.midY }
            return fa.midX < fb.midX
        }

        var rows: [[Int]] = []
        for idx in sortedIndices {
            if let lastRow = rows.last,
               let firstInRow = lastRow.first,
               abs(items[idx].space.frame.midY - items[firstInRow].space.frame.midY) <= 40,
               items[idx].space.frame.minX - items[lastRow.last!].space.frame.maxX <= 160 {
                rows[rows.count - 1].append(idx)
            } else {
                rows.append([idx])
            }
        }

        var results = Array(repeating: CGRect.zero, count: items.count)
        for row in rows {
            let rowSpaces = row.map { items[$0].space }
            let mode = detectMode(for: rowSpaces)
            let rowRects = layoutRow(row.map { items[$0] }, mode: mode)
            for (localIdx, origIdx) in row.enumerated() {
                results[origIdx] = rowRects[localIdx]
            }
        }
        return results
    }

    /// Single-item convenience wrapper preserving backward compatibility.
    public static func pillFrame(
        for item: SpaceItem,
        displayTextWidth: CGFloat,
        nativeTextWidth: CGFloat,
        leftNeighborFrame: CGRect? = nil,
        rightNeighborFrame: CGRect? = nil
    ) -> CGRect {
        var row: [LayoutItem] = []
        var targetIndex = 0
        if let left = leftNeighborFrame,
           abs(left.midY - item.frame.midY) <= 40,
           item.frame.minX - left.maxX <= 160 {
            row.append(LayoutItem(space: SpaceItem(title: "", frame: left), displayTextWidth: 40, nativeTextWidth: 40))
            targetIndex = 1
        }
        row.append(LayoutItem(space: item, displayTextWidth: displayTextWidth, nativeTextWidth: nativeTextWidth))
        if let right = rightNeighborFrame,
           abs(right.midY - item.frame.midY) <= 40,
           right.minX - item.frame.maxX <= 160 {
            row.append(LayoutItem(space: SpaceItem(title: "", frame: right), displayTextWidth: 40, nativeTextWidth: 40))
        }
        let mode = detectMode(for: row.map(\.space))
        return layoutRow(row, mode: mode)[targetIndex]
    }

    private static func layoutRow(_ items: [LayoutItem], mode: BarMode) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let halfGap = minInterPillGap / 2

        return items.indices.map { i in
            let current = items[i]
            let space = current.space
            let centerX = space.labelFrame?.midX ?? space.frame.midX
            let vBand = verticalBounds(for: space, mode: mode)

            let desiredWidth: CGFloat
            if let lf = space.labelFrame {
                desiredWidth = max(
                    lf.width + nativeMaskPadding,
                    max(current.nativeTextWidth + nativeMaskPadding, current.displayTextWidth + pillHorizontalPadding)
                )
            } else if mode == .compact && space.frame.height <= compactMaxHeight {
                desiredWidth = max(
                    space.frame.width,
                    max(current.nativeTextWidth + nativeMaskPadding, current.displayTextWidth + pillHorizontalPadding)
                )
            } else {
                desiredWidth = max(
                    current.nativeTextWidth + nativeMaskPadding,
                    current.displayTextWidth + pillHorizontalPadding
                )
            }

            // Clamp against adjacent items using midpoint between centers (or thumbnail spacing in expanded mode)
            // so neighboring pills ALWAYS stay separated by at least `minInterPillGap`.
            var maxLeftReach = desiredWidth / 2
            var maxRightReach = desiredWidth / 2

            if i > 0 {
                let left = items[i - 1]
                let leftCenterX = left.space.labelFrame?.midX ?? left.space.frame.midX
                let leftDesired = max(left.nativeTextWidth + nativeMaskPadding, left.displayTextWidth + pillHorizontalPadding)
                let dist = centerX - leftCenterX
                if dist > 0 {
                    // Allocate boundary proportionally if one label is much wider, else midpoint.
                    let sumDesired = (desiredWidth + leftDesired) / 2
                    let boundaryX: CGFloat
                    if sumDesired > 0 && sumDesired <= dist - minInterPillGap {
                        boundaryX = leftCenterX + leftDesired / 2 + halfGap
                    } else {
                        boundaryX = (leftCenterX + centerX) / 2 + halfGap
                    }
                    maxLeftReach = min(maxLeftReach, max(16, centerX - boundaryX))
                }
            }

            if i + 1 < items.count {
                let right = items[i + 1]
                let rightCenterX = right.space.labelFrame?.midX ?? right.space.frame.midX
                let rightDesired = max(right.nativeTextWidth + nativeMaskPadding, right.displayTextWidth + pillHorizontalPadding)
                let dist = rightCenterX - centerX
                if dist > 0 {
                    let sumDesired = (desiredWidth + rightDesired) / 2
                    let boundaryX: CGFloat
                    if sumDesired > 0 && sumDesired <= dist - minInterPillGap {
                        boundaryX = rightCenterX - rightDesired / 2 - halfGap
                    } else {
                        boundaryX = (centerX + rightCenterX) / 2 - halfGap
                    }
                    maxRightReach = min(maxRightReach, max(16, boundaryX - centerX))
                }
            }

            // Keep pill centered on `centerX` by taking symmetric reach, unless clamped asymmetrically.
            let symmetricHalf = min(maxLeftReach, maxRightReach)
            let width = max(28, symmetricHalf * 2)
            let originX = round(centerX - width / 2)

            return CGRect(
                x: originX,
                y: round(vBand.minY),
                width: ceil(width),
                height: ceil(vBand.height)
            )
        }
    }

    private static func verticalBounds(for item: SpaceItem, mode: BarMode) -> (minY: CGFloat, height: CGFloat) {
        if let exact = item.labelFrame {
            let height = max(20, exact.height + 4)
            return (exact.midY - height / 2, height)
        }
        switch mode {
        case .compact:
            if item.frame.height <= compactMaxHeight {
                let height = max(defaultCompactLabelHeight, item.frame.height)
                return (item.frame.midY - height / 2, height)
            }
            // macOS 27 WindowManager keeps the 129pt Space card size when deflated, sliding it
            // upward so only the bottom label band remains inside the compact Spaces bar.
            return (item.frame.maxY - 19, defaultCompactLabelHeight)
        case .expanded:
            let aspect = item.frame.height > 0 ? (item.frame.width / item.frame.height) : 1.0
            if aspect >= 1.40 {
                // Button wraps thumbnail preview only; label sits directly underneath.
                return (item.frame.maxY + 3, defaultExpandedLabelHeight)
            }
            // Button wraps thumbnail + label together; label band sits at the bottom ~21pt of the card.
            return (item.frame.maxY - defaultExpandedLabelHeight, defaultExpandedLabelHeight)
        }
    }
}
