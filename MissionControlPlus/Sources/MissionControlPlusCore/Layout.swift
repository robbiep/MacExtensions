import Foundation
import CoreGraphics

public enum LayoutStability {
    public static func isStable(_ a: MissionControlSnapshot, _ b: MissionControlSnapshot, tolerance: CGFloat = 1.0) -> Bool {
        thumbnailsEqual(a.thumbnails, b.thumbnails, tolerance: tolerance)
            && spacesEqual(a.spaces, b.spaces, tolerance: tolerance)
    }

    public static func thumbnailsEqual(_ a: [Thumbnail], _ b: [Thumbnail], tolerance: CGFloat = 1.0) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if x.title != y.title || x.identifier != y.identifier || !framesClose(x.frame, y.frame, tolerance: tolerance) {
                return false
            }
        }
        return true
    }

    public static func spacesEqual(_ a: [SpaceItem], _ b: [SpaceItem], tolerance: CGFloat = 1.0) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if x.title != y.title || !framesClose(x.frame, y.frame, tolerance: tolerance) {
                return false
            }
            switch (x.labelFrame, y.labelFrame) {
            case (nil, nil): break
            case (let lf?, let rf?): if !framesClose(lf, rf, tolerance: tolerance) { return false }
            default: return false
            }
        }
        return true
    }

    private static func framesClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}

public enum OverlaySizingPolicy {
    /// Proportional icon size inside a thumbnail, clamped safely so tiny windows aren't overflowed.
    public static func iconSize(forThumbnailSize size: CGSize, showingTitles: Bool) -> CGFloat {
        let minSide = min(size.width, size.height)
        if showingTitles {
            return min(max(18, round(minSide * 0.14)), 28)
        }
        let target = round(minSide * 0.24)
        let clamped = min(max(target, 28), 68)
        let maxFit = max(16, floor(minSide * 0.62))
        return min(clamped, maxFit)
    }

    public static func badgeSize(forIconSize iconSize: CGFloat) -> CGSize {
        let pad = max(6, round(iconSize * 0.22))
        let side = iconSize + pad * 2
        return CGSize(width: side, height: side)
    }

    public static func titleLineLimit(forThumbnailHeight height: CGFloat) -> Int {
        if height < 76 { return 0 }
        if height < 130 { return 1 }
        return 2
    }
}
