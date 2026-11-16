import Foundation
import CoreGraphics

/// Mission Control window thumbnail captured from WindowManager/Dock AX tree.
/// `frame` uses Core Graphics global coordinates (top-left origin on primary display, pt).
public struct Thumbnail: Equatable, Sendable {
    public var title: String
    public var frame: CGRect
    public var identifier: String?
    public var roleDescription: String?
    public var axIndex: Int

    public init(
        title: String,
        frame: CGRect,
        identifier: String? = nil,
        roleDescription: String? = nil,
        axIndex: Int = 0
    ) {
        self.title = title
        self.frame = frame
        self.identifier = identifier
        self.roleDescription = roleDescription
        self.axIndex = axIndex
    }

    /// Bundle identifier extracted from macOS 27 WindowManager AXIdentifier (`"<bundleID>.space.<id>"`).
    public var parsedBundleID: String? {
        BundleIdentifierParser.bundleID(fromThumbnailIdentifier: identifier)
    }
}

/// Extracts bundle identifiers from macOS 27 `AXIdentifier` values like `com.google.Chrome.space.1`.
public enum BundleIdentifierParser {
    public static func bundleID(fromThumbnailIdentifier identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty, !identifier.hasPrefix("mc.") else {
            return nil
        }
        guard let markerRange = identifier.range(of: ".space.", options: .backwards) else {
            return nil
        }
        let suffix = identifier[markerRange.upperBound...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else {
            return nil
        }
        let prefix = String(identifier[..<markerRange.lowerBound])
        guard !prefix.isEmpty, prefix.contains(".") else {
            return nil
        }
        return prefix
    }
}

/// Space button/item in the Mission Control top Spaces bar (`mc.spaces*`).
/// All frames use Core Graphics top-left coordinates (pt).
public struct SpaceItem: Equatable, Sendable {
    public var title: String
    public var frame: CGRect
    public var labelFrame: CGRect?
    public var listFrame: CGRect?
    public var identifier: String?
    public var roleDescription: String?
    public var axIndex: Int

    public init(
        title: String,
        frame: CGRect,
        labelFrame: CGRect? = nil,
        listFrame: CGRect? = nil,
        identifier: String? = nil,
        roleDescription: String? = nil,
        axIndex: Int = 0
    ) {
        self.title = title
        self.frame = frame
        self.labelFrame = labelFrame
        self.listFrame = listFrame
        self.identifier = identifier
        self.roleDescription = roleDescription
        self.axIndex = axIndex
    }
}

public struct MissionControlSnapshot: Equatable, Sendable {
    public var thumbnails: [Thumbnail]
    public var spaces: [SpaceItem]

    public init(thumbnails: [Thumbnail], spaces: [SpaceItem]) {
        self.thumbnails = thumbnails
        self.spaces = spaces
    }

    public var isEmpty: Bool {
        thumbnails.isEmpty && spaces.isEmpty
    }
}

/// Active feature configuration combining the master switch with individual feature toggles.
public struct FeatureConfig: Equatable, Sendable {
    public var isMasterEnabled: Bool
    public var showWindowIcons: Bool
    public var replaceSpaceNames: Bool
    public var showWindowTitles: Bool
    public var anchor: OverlayAnchor

    public init(
        isMasterEnabled: Bool = true,
        showWindowIcons: Bool = true,
        replaceSpaceNames: Bool = true,
        showWindowTitles: Bool = false,
        anchor: OverlayAnchor = .default
    ) {
        self.isMasterEnabled = isMasterEnabled
        self.showWindowIcons = showWindowIcons
        self.replaceSpaceNames = replaceSpaceNames
        self.showWindowTitles = showWindowTitles
        self.anchor = anchor
    }

    public var effectiveShowWindowIcons: Bool { isMasterEnabled && showWindowIcons }
    public var effectiveReplaceSpaceNames: Bool { isMasterEnabled && replaceSpaceNames }
    public var effectiveShowWindowTitles: Bool { effectiveShowWindowIcons && showWindowTitles }
    public var shouldRunEngine: Bool { effectiveShowWindowIcons || effectiveReplaceSpaceNames }
}

/// Window metadata from `CGWindowListCopyWindowInfo`.
public struct WindowRecord: Equatable, Sendable {
    public var windowID: UInt32
    public var ownerPID: Int32
    public var frame: CGRect
    public var layer: Int
    public var ownerName: String?

    public init(windowID: UInt32, ownerPID: Int32, frame: CGRect, layer: Int, ownerName: String? = nil) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.frame = frame
        self.layer = layer
        self.ownerName = ownerName
    }
}

/// App window metadata read via Accessibility (`kAXWindowsAttribute`) across all Spaces.
public struct AppWindowCandidate: Equatable, Sendable {
    public var ownerPID: Int32
    public var bundleID: String?
    public var shortName: String
    public var localizedName: String
    public var title: String
    public var isFullScreen: Bool
    public var isMinimized: Bool

    public init(
        ownerPID: Int32,
        bundleID: String? = nil,
        shortName: String,
        localizedName: String,
        title: String,
        isFullScreen: Bool = false,
        isMinimized: Bool = false
    ) {
        self.ownerPID = ownerPID
        self.bundleID = bundleID
        self.shortName = shortName
        self.localizedName = localizedName
        self.title = title
        self.isFullScreen = isFullScreen
        self.isMinimized = isMinimized
    }
}

public enum OverlayAnchor: String, CaseIterable, Sendable {
    case center, topLeft, topRight, bottomLeft, bottomRight

    public static let `default`: OverlayAnchor = .center

    public var displayName: String {
        switch self {
        case .center: return "Center"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    public enum Alignment: Sendable { case left, center, right }

    public var alignment: Alignment {
        switch self {
        case .center: return .center
        case .topLeft, .bottomLeft: return .left
        case .topRight, .bottomRight: return .right
        }
    }

    /// Computes AppKit (bottom-left origin) rect origin for an overlay inside `thumb`.
    public func origin(overlaySize size: CGSize, in thumb: CGRect, inset: CGFloat) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .center:
            x = thumb.midX - size.width / 2
            y = thumb.midY - size.height / 2
        case .topLeft:
            x = thumb.minX + inset
            y = thumb.maxY - inset - size.height
        case .topRight:
            x = thumb.maxX - inset - size.width
            y = thumb.maxY - inset - size.height
        case .bottomLeft:
            x = thumb.minX + inset
            y = thumb.minY + inset
        case .bottomRight:
            x = thumb.maxX - inset - size.width
            y = thumb.minY + inset
        }
        return CGPoint(x: round(x), y: round(y))
    }
}

public struct ResolvedWindowOverlay: Equatable, Sendable {
    public enum Confidence: String, Sendable {
        case geometry
        case identifier
        case titleUnique
        case thumbnailOnly
    }

    public var frame: CGRect
    public var appName: String?
    public var bundleID: String?
    public var ownerPID: Int32?
    public var title: String?
    public var axIndex: Int
    public var confidence: Confidence

    public init(
        frame: CGRect,
        appName: String?,
        bundleID: String? = nil,
        ownerPID: Int32? = nil,
        title: String?,
        axIndex: Int = 0,
        confidence: Confidence
    ) {
        self.frame = frame
        self.appName = appName
        self.bundleID = bundleID
        self.ownerPID = ownerPID
        self.title = title
        self.axIndex = axIndex
        self.confidence = confidence
    }

    public var formattedTitleLines: (primary: String?, secondary: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = (trimmed?.isEmpty == false) ? trimmed : nil
        guard let app = appName, !app.isEmpty else {
            return (cleanTitle, nil)
        }
        guard let cleanTitle, cleanTitle != app else {
            return (app, nil)
        }
        return TitleFormatter.lines(title: cleanTitle, appName: app, bundleID: bundleID)
    }
}

public struct ResolvedSpaceOverlay: Equatable, Sendable {
    public enum Confidence: String, Sendable {
        case fullScreenWindow
        case allWindowFallback
        case splitView
        case appNameDirect
    }

    public var spaceItem: SpaceItem
    public var displayName: String
    public var originalTitle: String
    public var confidence: Confidence

    public init(
        spaceItem: SpaceItem,
        displayName: String,
        originalTitle: String,
        confidence: Confidence
    ) {
        self.spaceItem = spaceItem
        self.displayName = displayName
        self.originalTitle = originalTitle
        self.confidence = confidence
    }
}

public struct ResolveStats: Equatable, Sendable {
    public var thumbnailCount = 0
    public var visibleOverlayCount = 0
    public var spaceCount = 0
    public var resolvedSpaceCount = 0
    public var candidateWindowCount = 0
    public var uniqueMatches = 0
    public var identifierMatches = 0
    public var titleUniqueFallbacks = 0
    public var unmatched = 0
    public var elapsed: TimeInterval = 0

    public init() {}
}
