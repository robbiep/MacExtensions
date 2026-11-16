import Foundation
import CoreGraphics

/// Matches Mission Control thumbnail coordinates against CG windows using asymmetric tolerances
/// (macOS 27 draws previews inset inside card borders, making thumbnails smaller than real windows).
public struct GeometryMatcher: Sendable {
    public struct Config: Sendable {
        public var centerTolerance: CGFloat
        public var thumbOversizeTolerance: CGFloat
        public var windowOversizeTolerance: CGFloat

        public init(
            centerTolerance: CGFloat = 24,
            thumbOversizeTolerance: CGFloat = 6,
            windowOversizeTolerance: CGFloat = 40
        ) {
            self.centerTolerance = centerTolerance
            self.thumbOversizeTolerance = thumbOversizeTolerance
            self.windowOversizeTolerance = windowOversizeTolerance
        }
    }

    public enum Result: Equatable, Sendable {
        case unique(WindowRecord)
        case ambiguous([WindowRecord])
        case none
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func candidates(for thumb: CGRect, in windows: [WindowRecord]) -> [WindowRecord] {
        windows.filter { window in
            let f = window.frame
            let dx = abs(f.midX - thumb.midX)
            let dy = abs(f.midY - thumb.midY)
            return hypot(dx, dy) <= config.centerTolerance
                && thumb.width - f.width <= config.thumbOversizeTolerance
                && thumb.height - f.height <= config.thumbOversizeTolerance
                && f.width - thumb.width <= config.windowOversizeTolerance
                && f.height - thumb.height <= config.windowOversizeTolerance
        }
    }

    public func match(_ thumb: CGRect, in windows: [WindowRecord]) -> Result {
        let matches = candidates(for: thumb, in: windows)
        switch matches.count {
        case 0: return .none
        case 1: return .unique(matches[0])
        default: return .ambiguous(matches)
        }
    }
}

/// Normalizes and matches truncated or app-suffixed window titles.
public enum TitleMatcher {
    private static let ellipsisTokens = ["...", "\u{2026}"]
    private static let titleSeparators = [" - ", " \u{2014} ", " \u{2013} ", " | "]

    /// Matches a potentially truncated Dock/WindowManager title against candidate raw titles.
    /// Returns unique matching index, or nil if 0 or >= 2 distinct indices match.
    public static func uniqueIndex(thumbnailTitle raw: String, in candidates: [String]) -> Int? {
        let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        let exact = candidates.indices.filter { candidates[$0].trimmingCharacters(in: .whitespacesAndNewlines) == target }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 { return nil }

        let hits = candidates.indices.filter { matchesPattern(target, candidate: candidates[$0]) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Checks whether `pattern` (possibly containing one or more `...` / `…`) matches `candidate`.
    public static func matchesPattern(_ patternRaw: String, candidate candidateRaw: String) -> Bool {
        let pattern = patternRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = candidateRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, !candidate.isEmpty else { return false }

        if pattern == candidate { return true }

        let segments = splitEllipsisSegments(pattern)
        guard segments.count >= 2 else { return false }
        guard segments.contains(where: { !$0.isEmpty }) else { return false }

        var searchStart = candidate.startIndex
        for (idx, segment) in segments.enumerated() {
            if segment.isEmpty { continue }
            if idx == 0 {
                guard candidate.hasPrefix(segment) else { return false }
                searchStart = candidate.index(candidate.startIndex, offsetBy: segment.count)
            } else if idx == segments.count - 1 {
                guard candidate.hasSuffix(segment) else { return false }
                let suffixStart = candidate.index(candidate.endIndex, offsetBy: -segment.count)
                guard suffixStart >= searchStart else { return false }
                searchStart = candidate.endIndex
            } else {
                guard let found = candidate.range(of: segment, range: searchStart..<candidate.endIndex) else {
                    return false
                }
                searchStart = found.upperBound
            }
        }
        return true
    }

    /// Produces candidate title variants with trailing app name / profile suffixes stripped.
    /// For example `"Top 10 recipes - Google Chrome - Personal"` yields:
    /// `["Top 10 recipes - Google Chrome - Personal", "Top 10 recipes - Google Chrome", "Top 10 recipes"]`.
    public static func titleVariants(
        rawTitle: String,
        shortName: String,
        localizedName: String
    ) -> [String] {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var variants: [String] = [trimmed]
        let appNames = Array(Set([localizedName, shortName].filter { !$0.isEmpty }))

        for appName in appNames {
            for sep in titleSeparators {
                // Leading "<AppName><sep><Rest>" (e.g. "Slack | #channel | Workspace")
                let prefix = appName + sep
                if trimmed.hasPrefix(prefix) {
                    let stripped = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stripped.isEmpty {
                        variants.append(stripped)
                        for innerSep in titleSeparators {
                            if let range = stripped.range(of: innerSep, options: .backwards) {
                                let head = String(stripped[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !head.isEmpty { variants.append(head) }
                            }
                        }
                    }
                }
                // Exact trailing "<sep><AppName>"
                let suffix = sep + appName
                if trimmed.hasSuffix(suffix) {
                    let stripped = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stripped.isEmpty {
                        variants.append(stripped)
                        // Also allow stripping one trailing workspace/account segment (e.g. Slack "<channel> - <workspace> - Slack")
                        for innerSep in titleSeparators {
                            if let range = stripped.range(of: innerSep, options: .backwards) {
                                let head = String(stripped[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !head.isEmpty { variants.append(head) }
                            }
                        }
                    }
                }
                // Trailing "<sep><AppName><sep><Profile>" (Chrome profile suffix)
                let infix = sep + appName + sep
                if let range = trimmed.range(of: infix, options: .backwards) {
                    let stripped = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stripped.isEmpty { variants.append(stripped) }
                }
            }
        }

        // Deduplicate while preserving priority order.
        var seen = Set<String>()
        return variants.filter { seen.insert($0).inserted }
    }

    private static func splitEllipsisSegments(_ s: String) -> [String] {
        var normalized = s
        for token in ellipsisTokens where token != "\u{2026}" {
            normalized = normalized.replacingOccurrences(of: token, with: "\u{2026}")
        }
        return normalized.components(separatedBy: "\u{2026}")
    }
}

/// Filters grouped/overlapping Mission Control thumbnails so stacked windows of the same app
/// receive one clean icon on the frontmost card rather than colliding overlapping badges.
public enum WindowOverlapFilter {
    /// Minimum fraction of the smaller thumbnail covered to treat two same-app thumbnails as stacked.
    public static let stackOverlapThreshold: CGFloat = 0.30

    public static func selectVisibleOverlays(
        from overlays: [ResolvedWindowOverlay],
        badgeSizeForOverlay: (ResolvedWindowOverlay) -> CGSize,
        badgeOriginForOverlay: (CGSize, ResolvedWindowOverlay) -> CGPoint,
        badgePadding: CGFloat = 6
    ) -> [ResolvedWindowOverlay] {
        guard overlays.count > 1 else { return overlays }

        // Sort highest visual priority first (largest area -> frontmost bottom-most maxY -> latest AX index).
        let sorted = overlays.sorted { a, b in
            let areaA = a.frame.width * a.frame.height
            let areaB = b.frame.width * b.frame.height
            if abs(areaA - areaB) > 4 { return areaA > areaB }
            if abs(a.frame.maxY - b.frame.maxY) > 2 { return a.frame.maxY > b.frame.maxY }
            return a.axIndex > b.axIndex
        }

        var accepted: [ResolvedWindowOverlay] = []
        var acceptedBadgeRects: [CGRect] = []

        for candidate in sorted {
            let size = badgeSizeForOverlay(candidate)
            let origin = badgeOriginForOverlay(size, candidate)
            let badgeRect = CGRect(origin: origin, size: size)

            let sameAppStacked = accepted.contains { existing in
                isSameApp(existing, candidate) && overlapRatio(existing.frame, candidate.frame) >= stackOverlapThreshold
            }
            if sameAppStacked { continue }

            let collidesWithBadge = acceptedBadgeRects.contains { existingRect in
                existingRect.insetBy(dx: -badgePadding, dy: -badgePadding).intersects(badgeRect)
            }
            if collidesWithBadge { continue }

            accepted.append(candidate)
            acceptedBadgeRects.append(badgeRect)
        }

        return accepted.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) > 2 { return a.frame.minY < b.frame.minY }
            return a.frame.minX < b.frame.minX
        }
    }

    private static func isSameApp(_ a: ResolvedWindowOverlay, _ b: ResolvedWindowOverlay) -> Bool {
        if let pa = a.ownerPID, let pb = b.ownerPID { return pa == pb }
        if let ba = a.bundleID, let bb = b.bundleID { return ba == bb }
        if let na = a.appName, let nb = b.appName { return na == nb }
        return false
    }

    private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let minArea = min(a.width * a.height, b.width * b.height)
        guard minArea > 0 else { return 0 }
        return (inter.width * inter.height) / minArea
    }
}

/// Formats optional window titles consistently with VS Code-family workspace extraction.
public enum TitleFormatter {
    public static let vsCodeFamily: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
    ]

    private static let separators = [" \u{2014} ", " - "]

    public static func lines(title: String, appName: String, bundleID: String?) -> (primary: String?, secondary: String?) {
        if let bundleID, vsCodeFamily.contains(bundleID), let parsed = parseVSCode(title: title, appName: appName) {
            return (parsed.workspace, "\(parsed.file) \u{00B7} \(appName)")
        }
        return (title, appName)
    }

    static func parseVSCode(title: String, appName: String) -> (workspace: String, file: String)? {
        var parts: [String] = []
        for sep in separators where title.contains(sep) {
            parts = title.components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            break
        }
        if let last = parts.last, last == appName || last == "Visual Studio Code" {
            parts.removeLast()
        }
        guard parts.count >= 2 else { return nil }
        let workspace = parts[parts.count - 1]
        let file = parts[0..<(parts.count - 1)].joined(separator: " \u{00B7} ")
        return (workspace, file)
    }
}
