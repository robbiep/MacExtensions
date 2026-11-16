import AppKit
import ApplicationServices
import MissionControlPlusCore

/// Resolves Mission Control window thumbnails and top Spaces bar items to owning apps and titles.
final class WindowResolver {
    private static let appAXTimeout: Float = 0.12

    private let matcher = GeometryMatcher()
    private let excludedPIDs: Set<pid_t>

    private var appWindowsCache: [pid_t: [AppWindowInfo]] = [:]
    private var shortNameCache: [pid_t: String] = [:]
    private var localizedNameCache: [pid_t: String] = [:]
    private var bundleIDCache: [pid_t: String] = [:]
    private var runningByBundleID: [String: [NSRunningApplication]] = [:]

    private(set) var lastWindows: [WindowRecord] = []

    struct AppWindowInfo {
        let title: String
        let frame: CGRect?
        let isFullScreen: Bool
        let isMinimized: Bool
    }

    struct Outcome {
        var windowOverlays: [ResolvedWindowOverlay]
        var spaceOverlays: [ResolvedSpaceOverlay]
        var stats: ResolveStats
        var thumbnailDetail: [(thumbnail: Thumbnail, result: GeometryMatcher.Result, overlay: ResolvedWindowOverlay)]
    }

    init(excludedPIDs: Set<pid_t> = []) {
        self.excludedPIDs = excludedPIDs
    }

    func invalidateSessionCaches() {
        appWindowsCache.removeAll()
        shortNameCache.removeAll()
        localizedNameCache.removeAll()
        bundleIDCache.removeAll()
        runningByBundleID.removeAll()
    }

    func resolve(
        snapshot: MissionControlSnapshot,
        hostPIDs: Set<pid_t>,
        resolveWindows: Bool,
        resolveSpaces: Bool
    ) -> Outcome {
        let start = Date()
        var stats = ResolveStats()
        stats.thumbnailCount = snapshot.thumbnails.count
        stats.spaceCount = snapshot.spaces.count

        refreshRunningAppIndex()

        var windows: [WindowRecord] = []
        var windowOverlays: [ResolvedWindowOverlay] = []
        var thumbnailDetail: [(Thumbnail, GeometryMatcher.Result, ResolvedWindowOverlay)] = []

        if resolveWindows && !snapshot.thumbnails.isEmpty {
            windows = collectOnScreenWindows(extraExcluded: hostPIDs)
            lastWindows = windows
            stats.candidateWindowCount = windows.count

            for thumb in snapshot.thumbnails {
                let (overlay, matchResult) = resolveThumbnail(thumb, in: windows, stats: &stats)
                windowOverlays.append(overlay)
                thumbnailDetail.append((thumb, matchResult, overlay))
            }
        } else {
            lastWindows = []
        }

        var spaceOverlays: [ResolvedSpaceOverlay] = []
        if resolveSpaces && !snapshot.spaces.isEmpty {
            let hasNonDesktop = snapshot.spaces.contains { !SpaceTitleResolver.isDesktopSpaceTitle($0.title) }
            if hasNonDesktop {
                let allCandidates = collectAllAppWindowCandidates()
                spaceOverlays = SpaceTitleResolver.resolve(spaces: snapshot.spaces, candidates: allCandidates)
                stats.resolvedSpaceCount = spaceOverlays.count
            }
        }

        stats.elapsed = Date().timeIntervalSince(start)
        return Outcome(
            windowOverlays: windowOverlays,
            spaceOverlays: spaceOverlays,
            stats: stats,
            thumbnailDetail: thumbnailDetail
        )
    }

    // MARK: - Thumbnail resolution

    private func resolveThumbnail(
        _ thumb: Thumbnail,
        in windows: [WindowRecord],
        stats: inout ResolveStats
    ) -> (ResolvedWindowOverlay, GeometryMatcher.Result) {
        let result = matcher.match(thumb.frame, in: windows)
        switch result {
        case .unique(let win):
            stats.uniqueMatches += 1
            let title = originalTitle(for: thumb.title, pid: win.ownerPID)
            let overlay = ResolvedWindowOverlay(
                frame: thumb.frame,
                appName: shortName(for: win.ownerPID),
                bundleID: bundleID(for: win.ownerPID),
                ownerPID: win.ownerPID,
                title: title,
                axIndex: thumb.axIndex,
                confidence: .geometry
            )
            return (overlay, result)

        case .ambiguous(let candidates):
            if let byIdentifier = resolveFromIdentifier(thumb, matchingWindows: candidates) {
                stats.identifierMatches += 1
                return (byIdentifier, result)
            }
            if let byTitle = fallbackByTitle(thumb, candidatePIDs: Set(candidates.map(\.ownerPID))) {
                stats.titleUniqueFallbacks += 1
                return (byTitle, result)
            }
            stats.unmatched += 1
            return (fallbackThumbnailOnly(thumb), result)

        case .none:
            if let byIdentifier = resolveFromIdentifier(thumb, matchingWindows: windows) {
                stats.identifierMatches += 1
                return (byIdentifier, result)
            }
            if let byTitle = fallbackByTitle(thumb, candidatePIDs: Set(windows.map(\.ownerPID))) {
                stats.titleUniqueFallbacks += 1
                return (byTitle, result)
            }
            stats.unmatched += 1
            return (fallbackThumbnailOnly(thumb), result)
        }
    }

    private func resolveFromIdentifier(_ thumb: Thumbnail, matchingWindows: [WindowRecord]) -> ResolvedWindowOverlay? {
        guard let parsedBID = thumb.parsedBundleID else { return nil }
        let matchingApps = runningByBundleID[parsedBID] ?? []
        let candidatePIDs = Set(matchingApps.map(\.processIdentifier))

        // Narrow geometry candidates to PIDs matching the parsed bundle ID.
        let pidFilteredWindows = matchingWindows.filter { candidatePIDs.contains($0.ownerPID) }
        if pidFilteredWindows.count == 1, let win = pidFilteredWindows.first {
            return ResolvedWindowOverlay(
                frame: thumb.frame,
                appName: shortName(for: win.ownerPID),
                bundleID: parsedBID,
                ownerPID: win.ownerPID,
                title: originalTitle(for: thumb.title, pid: win.ownerPID),
                axIndex: thumb.axIndex,
                confidence: .identifier
            )
        }

        // Match title within the identified app(s).
        let trimmed = thumb.title.trimmingCharacters(in: .whitespacesAndNewlines)
        for pid in candidatePIDs {
            let titles = appWindows(for: pid).map(\.title)
            if !trimmed.isEmpty, let idx = TitleMatcher.uniqueIndex(thumbnailTitle: trimmed, in: titles) {
                return ResolvedWindowOverlay(
                    frame: thumb.frame,
                    appName: shortName(for: pid),
                    bundleID: parsedBID,
                    ownerPID: pid,
                    title: titles[idx],
                    axIndex: thumb.axIndex,
                    confidence: .identifier
                )
            }
        }

        // Even if title couldn't disambiguate multiple windows of the same app, we still know the app!
        if let app = matchingApps.first {
            return ResolvedWindowOverlay(
                frame: thumb.frame,
                appName: AppNameHelper.shortName(for: app),
                bundleID: parsedBID,
                ownerPID: app.processIdentifier,
                title: trimmed.isEmpty ? nil : trimmed,
                axIndex: thumb.axIndex,
                confidence: .identifier
            )
        }

        // Last resort: use bundle URL on disk even if app process index didn't list it.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parsedBID) {
            let name = (Bundle(url: appURL)?.infoDictionary?["CFBundleName"] as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            return ResolvedWindowOverlay(
                frame: thumb.frame,
                appName: name,
                bundleID: parsedBID,
                ownerPID: nil,
                title: trimmed.isEmpty ? nil : trimmed,
                axIndex: thumb.axIndex,
                confidence: .identifier
            )
        }

        return nil
    }

    private func fallbackByTitle(_ thumb: Thumbnail, candidatePIDs: Set<pid_t>) -> ResolvedWindowOverlay? {
        let trimmed = thumb.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var all: [(pid: pid_t, title: String)] = []
        for pid in candidatePIDs {
            for win in appWindows(for: pid) where !win.title.isEmpty {
                all.append((pid, win.title))
            }
        }
        guard let idx = TitleMatcher.uniqueIndex(thumbnailTitle: trimmed, in: all.map(\.title)) else {
            return nil
        }
        let pid = all[idx].pid
        return ResolvedWindowOverlay(
            frame: thumb.frame,
            appName: shortName(for: pid),
            bundleID: bundleID(for: pid),
            ownerPID: pid,
            title: all[idx].title,
            axIndex: thumb.axIndex,
            confidence: .titleUnique
        )
    }

    private func fallbackThumbnailOnly(_ thumb: Thumbnail) -> ResolvedWindowOverlay {
        let trimmed = thumb.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ResolvedWindowOverlay(
            frame: thumb.frame,
            appName: nil,
            bundleID: thumb.parsedBundleID,
            ownerPID: nil,
            title: trimmed.isEmpty ? nil : trimmed,
            axIndex: thumb.axIndex,
            confidence: .thumbnailOnly
        )
    }

    private func originalTitle(for thumbTitle: String, pid: pid_t) -> String? {
        let trimmed = thumbTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let titles = appWindows(for: pid).map(\.title)
        if let idx = TitleMatcher.uniqueIndex(thumbnailTitle: trimmed, in: titles) {
            return titles[idx]
        }
        return trimmed
    }

    // MARK: - Window & Running App Queries

    private func refreshRunningAppIndex() {
        runningByBundleID.removeAll()
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            runningByBundleID[bid, default: []].append(app)
            let pid = app.processIdentifier
            if shortNameCache[pid] == nil {
                shortNameCache[pid] = AppNameHelper.shortName(for: app)
            }
            if localizedNameCache[pid] == nil {
                localizedNameCache[pid] = AppNameHelper.localizedName(for: app)
            }
            bundleIDCache[pid] = bid
        }
    }

    private func collectOnScreenWindows(extraExcluded: Set<pid_t>) -> [WindowRecord] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let excluded = excludedPIDs.union(extraExcluded)
        var out: [WindowRecord] = []
        out.reserveCapacity(list.count)

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, !excluded.contains(pid),
                  let wid = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"]
            else { continue }
            out.append(
                WindowRecord(
                    windowID: wid,
                    ownerPID: pid,
                    frame: CGRect(x: x, y: y, width: w, height: h),
                    layer: layer,
                    ownerName: info[kCGWindowOwnerName as String] as? String
                )
            )
        }
        return out
    }

    private func collectAllAppWindowCandidates() -> [AppWindowCandidate] {
        var candidates: [AppWindowCandidate] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard !excludedPIDs.contains(pid) else { continue }
            let short = shortName(for: pid) ?? AppNameHelper.shortName(for: app)
            let localized = localizedName(for: pid) ?? AppNameHelper.localizedName(for: app)
            let bid = app.bundleIdentifier

            for win in appWindows(for: pid) where !win.title.isEmpty {
                candidates.append(
                    AppWindowCandidate(
                        ownerPID: pid,
                        bundleID: bid,
                        shortName: short,
                        localizedName: localized,
                        title: win.title,
                        isFullScreen: win.isFullScreen,
                        isMinimized: win.isMinimized
                    )
                )
            }
        }
        return candidates
    }

    private func appWindows(for pid: pid_t) -> [AppWindowInfo] {
        if let cached = appWindowsCache[pid] { return cached }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, Self.appAXTimeout)
        let wins = AX.elements(appEl, kAXWindowsAttribute).map { win in
            AppWindowInfo(
                title: AX.string(win, kAXTitleAttribute) ?? "",
                frame: AX.frame(win),
                isFullScreen: AX.bool(win, "AXFullScreen") ?? false,
                isMinimized: AX.bool(win, kAXMinimizedAttribute) ?? false
            )
        }
        appWindowsCache[pid] = wins
        return wins
    }

    private func shortName(for pid: pid_t) -> String? {
        if let cached = shortNameCache[pid] { return cached }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let name = AppNameHelper.shortName(for: app)
        shortNameCache[pid] = name
        return name
    }

    private func localizedName(for pid: pid_t) -> String? {
        if let cached = localizedNameCache[pid] { return cached }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let name = AppNameHelper.localizedName(for: app)
        localizedNameCache[pid] = name
        return name
    }

    private func bundleID(for pid: pid_t) -> String? {
        if let cached = bundleIDCache[pid] { return cached }
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if let bid { bundleIDCache[pid] = bid }
        return bid
    }
}
