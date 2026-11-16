import Foundation

/// Resolves Mission Control top Spaces bar contextual titles (e.g. `"Top 10 recipes"`,
/// `"Interview Sim...Continuation"`, Split View `"Doc & Channel"`) to short app names (`"Chrome"`, `"Slack"`).
public enum SpaceTitleResolver {
    private static let desktopPrefixes = [
        "desktop",
        "space",
        "데스크탑",
        "데스크톱",
        "桌面",
        "デスクトップ",
        "schreibtisch",
        "bureau",
        "escritorio",
        "scrivania",
        "bureaublad",
    ]

    private static let splitViewSeparators = [" & ", " + "]

    public static func isDesktopSpaceTitle(_ rawTitle: String) -> Bool {
        let t = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return true }
        for prefix in desktopPrefixes {
            if t == prefix { return true }
            if t.hasPrefix(prefix) {
                let remainder = t.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty, remainder.allSatisfy(\.isNumber) {
                    return true
                }
            }
        }
        return false
    }

    public static func resolve(
        spaces: [SpaceItem],
        candidates: [AppWindowCandidate]
    ) -> [ResolvedSpaceOverlay] {
        var result: [ResolvedSpaceOverlay] = []
        for space in spaces {
            if let resolved = resolveOne(space, candidates: candidates) {
                result.append(resolved)
            }
        }
        return result
    }

    public static func resolveOne(
        _ space: SpaceItem,
        candidates: [AppWindowCandidate]
    ) -> ResolvedSpaceOverlay? {
        let raw = space.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isDesktopSpaceTitle(raw) else { return nil }

        // First try resolving the entire title as a single window (prevents splitting titles like "Arts & Crafts").
        if let single = resolveSingleTitle(raw, candidates: candidates) {
            // Avoid redundant work only if label already equals the exact short app name?
            // No: returning it keeps pill appearance consistent, or wait—if raw == single.name,
            // wait: e.g. "Antigravity" -> "Antigravity" doesn't hurt, or skipping when identical
            // leaves the native label untouched with zero visual flash! Let's check:
            // Actually, skipping when `raw == single.name` keeps "Antigravity" clean & native!
            if raw == single.name { return nil }
            return ResolvedSpaceOverlay(
                spaceItem: space,
                displayName: single.name,
                originalTitle: raw,
                confidence: single.confidence
            )
        }

        // Next try Split View ("<Left> & <Right>" or "<Left> + <Right>").
        for sep in splitViewSeparators where raw.contains(sep) {
            let parts = raw.components(separatedBy: sep)
            guard parts.count == 2 else { continue }
            let leftRaw = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let rightRaw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !leftRaw.isEmpty, !rightRaw.isEmpty else { continue }
            guard let left = resolveSingleOrAppName(leftRaw, candidates: candidates),
                  let right = resolveSingleOrAppName(rightRaw, candidates: candidates)
            else { continue }

            let combined = (left == right) ? left : "\(left) & \(right)"
            if raw == combined { return nil }
            return ResolvedSpaceOverlay(
                spaceItem: space,
                displayName: combined,
                originalTitle: raw,
                confidence: .splitView
            )
        }

        return nil
    }

    private static func resolveSingleOrAppName(
        _ raw: String,
        candidates: [AppWindowCandidate]
    ) -> String? {
        if let single = resolveSingleTitle(raw, candidates: candidates) {
            return single.name
        }
        let matchingApps = Set(candidates.compactMap { c -> String? in
            if c.shortName == raw || c.localizedName == raw { return c.shortName }
            return nil
        })
        return matchingApps.count == 1 ? matchingApps.first : nil
    }

    private struct SingleMatch {
        let name: String
        let confidence: ResolvedSpaceOverlay.Confidence
    }

    private static func resolveSingleTitle(
        _ raw: String,
        candidates: [AppWindowCandidate]
    ) -> SingleMatch? {
        let activeCandidates = candidates.filter { !$0.isMinimized }
        let fullScreen = activeCandidates.filter(\.isFullScreen)

        // 1. Prioritize AXFullScreen windows (raw match, then stripped-suffix match, then pattern match).
        if let name = uniqueAppMatch(for: raw, in: fullScreen, allowDirectAppName: true) {
            return SingleMatch(name: name, confidence: .fullScreenWindow)
        }

        // 2. Fallback across all non-minimized app windows (handles apps that omit AXFullScreen).
        if let name = uniqueAppMatch(for: raw, in: activeCandidates, allowDirectAppName: false) {
            return SingleMatch(name: name, confidence: .allWindowFallback)
        }

        return nil
    }

    private static func uniqueAppMatch(
        for query: String,
        in candidates: [AppWindowCandidate],
        allowDirectAppName: Bool
    ) -> String? {
        guard !candidates.isEmpty else { return nil }

        // Tier A: exact match against raw window title.
        let exactRaw = Set(candidates.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == query
        }.map(\.shortName))
        if exactRaw.count == 1 { return exactRaw.first }

        // Tier B: exact match against title with app/profile suffixes stripped.
        let exactStripped = Set(candidates.filter { c in
            TitleMatcher.titleVariants(rawTitle: c.title, shortName: c.shortName, localizedName: c.localizedName)
                .contains(query)
        }.map(\.shortName))
        if exactStripped.count == 1 { return exactStripped.first }

        // Tier C: ellipsis pattern match ("Interview Sim...Continuation", "# Director of...uestions: F...")
        let patternHits = Set(candidates.filter { c in
            TitleMatcher.titleVariants(rawTitle: c.title, shortName: c.shortName, localizedName: c.localizedName)
                .contains { TitleMatcher.matchesPattern(query, candidate: $0) }
        }.map(\.shortName))
        if patternHits.count == 1 { return patternHits.first }

        // Tier D: direct app name match (only for known full-screen windows).
        if allowDirectAppName {
            let directApps = Set(candidates.compactMap { c -> String? in
                (c.shortName == query || c.localizedName == query) ? c.shortName : nil
            })
            if directApps.count == 1 { return directApps.first }
        }

        return nil
    }
}
