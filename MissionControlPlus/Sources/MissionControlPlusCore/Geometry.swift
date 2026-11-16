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

/// Computes top-left Core Graphics pill bounds for covering native Spaces bar labels.
public enum SpacePillLayout {
    public static let compactMaxHeight: CGFloat = 38
    public static let defaultExpandedLabelHeight: CGFloat = 21
    public static let neighborClearance: CGFloat = 2

    public static func pillFrame(
        for item: SpaceItem,
        displayTextWidth: CGFloat,
        nativeTextWidth: CGFloat,
        leftNeighborFrame: CGRect? = nil,
        rightNeighborFrame: CGRect? = nil
    ) -> CGRect {
        let verticalBand = verticalBounds(for: item)
        let centerX = item.labelFrame?.midX ?? item.frame.midX

        var desiredWidth: CGFloat
        if let labelFrame = item.labelFrame {
            desiredWidth = max(labelFrame.width + 12, max(nativeTextWidth + 10, displayTextWidth + 20))
        } else if item.frame.height <= compactMaxHeight {
            desiredWidth = max(item.frame.width, displayTextWidth + 20)
        } else {
            desiredWidth = max(item.frame.width + 12, max(nativeTextWidth + 12, displayTextWidth + 20))
        }

        // Prevent overflowing into neighboring Space thumbnails/labels on the same row.
        var maxHalfWidth = desiredWidth / 2
        let sameRowThreshold = max(item.frame.height, 24) * 0.75
        let maxAdjacentGap: CGFloat = 120
        if let left = leftNeighborFrame,
           abs(left.midY - item.frame.midY) <= sameRowThreshold,
           left.maxX <= item.frame.minX,
           item.frame.minX - left.maxX <= maxAdjacentGap {
            let boundary = (left.maxX + item.frame.minX) / 2 + neighborClearance
            // Guarantee at least item half-width if items sit very close, while staying <= midpoint.
            let allowed = max(item.frame.width / 2, centerX - boundary)
            maxHalfWidth = min(maxHalfWidth, allowed)
        }
        if let right = rightNeighborFrame,
           abs(right.midY - item.frame.midY) <= sameRowThreshold,
           right.minX >= item.frame.maxX,
           right.minX - item.frame.maxX <= maxAdjacentGap {
            let boundary = (item.frame.maxX + right.minX) / 2 - neighborClearance
            let allowed = max(item.frame.width / 2, boundary - centerX)
            maxHalfWidth = min(maxHalfWidth, allowed)
        }

        let width = max(24, min(desiredWidth, maxHalfWidth * 2))
        let originX = round(centerX - width / 2)

        return CGRect(
            x: originX,
            y: round(verticalBand.minY),
            width: ceil(width),
            height: ceil(verticalBand.height)
        )
    }

    private static func verticalBounds(for item: SpaceItem) -> (minY: CGFloat, height: CGFloat) {
        if let exact = item.labelFrame {
            let height = max(20, exact.height + 4)
            return (exact.midY - height / 2, height)
        }
        if item.frame.height <= compactMaxHeight {
            return (item.frame.minY, max(20, item.frame.height))
        }
        if let listFrame = item.listFrame {
            let spaceBelow = listFrame.maxY - item.frame.maxY
            if spaceBelow >= 15 {
                let height = min(23, max(19, spaceBelow))
                let offsetY = min(3, max(0, (spaceBelow - height) / 2))
                return (item.frame.maxY + offsetY, height)
            }
        }
        return (item.frame.maxY - defaultExpandedLabelHeight, defaultExpandedLabelHeight)
    }
}
