import Foundation

/// Resolves Mission Control top Spaces bar items to their owning application's short name.
/// Uses authoritative WindowServer space ownership (`ManagedSpaceDescriptor`) first,
/// falling back to full-screen `AXWindow` title matching when needed.
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
        managedSpaces: [ManagedSpaceDescriptor] = [],
        candidates: [AppWindowCandidate] = []
    ) -> [ResolvedSpaceOverlay] {
        guard !spaces.isEmpty else { return [] }

        // Sort spaces left-to-right (grouped by row/display) so indices line up with WindowServer's Spaces array.
        let sortedSpaces = spaces.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) > 40 { return a.frame.minY < b.frame.minY }
            return a.frame.minX < b.frame.minX
        }

        // 1. Primary path: 1-to-1 index mapping with SLSCopyManagedDisplaySpaces when counts match.
        if managedSpaces.count == sortedSpaces.count {
            var out: [ResolvedSpaceOverlay] = []
            for (space, desc) in zip(sortedSpaces, managedSpaces) {
                guard desc.isFullScreen else { continue }
                if let name = desc.displayName {
                    let conf: ResolvedSpaceOverlay.Confidence = desc.appShortNames.count > 1 ? .splitView : .fullScreenWindow
                    out.append(
                        ResolvedSpaceOverlay(
                            spaceItem: space,
                            displayName: name,
                            originalTitle: space.title,
                            confidence: conf
                        )
                    )
                } else if let byTitle = resolveOne(space, candidates: candidates) {
                    out.append(byTitle)
                }
            }
            return out
        }

        // 2. Secondary path: if only full-screen spaces are compared or counts differ, align full-screen spaces in order.
        let nonDesktopSpaces = sortedSpaces.filter { !isDesktopSpaceTitle($0.title) }
        let fullScreenManaged = managedSpaces.filter(\.isFullScreen)
        if !nonDesktopSpaces.isEmpty, nonDesktopSpaces.count == fullScreenManaged.count {
            var out: [ResolvedSpaceOverlay] = []
            for (space, desc) in zip(nonDesktopSpaces, fullScreenManaged) {
                if let name = desc.displayName {
                    let conf: ResolvedSpaceOverlay.Confidence = desc.appShortNames.count > 1 ? .splitView : .fullScreenWindow
                    out.append(
                        ResolvedSpaceOverlay(
                            spaceItem: space,
                            displayName: name,
                            originalTitle: space.title,
                            confidence: conf
                        )
                    )
                }
            }
            if !out.isEmpty { return out }
        }

        // 3. Fallback path: match against full-screen AXWindow candidates by title.
        var result: [ResolvedSpaceOverlay] = []
        for space in sortedSpaces {
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

        if let single = resolveSingleTitle(raw, candidates: candidates) {
            if raw == single.name { return nil }
            return ResolvedSpaceOverlay(
                spaceItem: space,
                displayName: single.name,
                originalTitle: raw,
                confidence: single.confidence
            )
        }

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
        let matchingApps = Set(candidates.filter(\.isFullScreen).compactMap { c -> String? in
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
        // Strictly restrict title matching for top-bar Spaces to full-screen windows so regular
        // windows on the Desktop (e.g. a browser tab with a similar title) never false-match a Space.
        let fullScreen = candidates.filter { !$0.isMinimized && $0.isFullScreen }
        if let name = uniqueAppMatch(for: raw, in: fullScreen, allowDirectAppName: true) {
            return SingleMatch(name: name, confidence: .fullScreenWindow)
        }
        return nil
    }

    private static func uniqueAppMatch(
        for query: String,
        in candidates: [AppWindowCandidate],
        allowDirectAppName: Bool
    ) -> String? {
        guard !candidates.isEmpty else { return nil }

        let exactRaw = Set(candidates.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == query
        }.map(\.shortName))
        if exactRaw.count == 1 { return exactRaw.first }

        let exactStripped = Set(candidates.filter { c in
            TitleMatcher.titleVariants(rawTitle: c.title, shortName: c.shortName, localizedName: c.localizedName)
                .contains(query)
        }.map(\.shortName))
        if exactStripped.count == 1 { return exactStripped.first }

        let patternHits = Set(candidates.filter { c in
            TitleMatcher.titleVariants(rawTitle: c.title, shortName: c.shortName, localizedName: c.localizedName)
                .contains { TitleMatcher.matchesPattern(query, candidate: $0) }
        }.map(\.shortName))
        if patternHits.count == 1 { return patternHits.first }

        if allowDirectAppName {
            let directApps = Set(candidates.compactMap { c -> String? in
                (c.shortName == query || c.localizedName == query) ? c.shortName : nil
            })
            if directApps.count == 1 { return directApps.first }
        }

        return nil
    }
}
