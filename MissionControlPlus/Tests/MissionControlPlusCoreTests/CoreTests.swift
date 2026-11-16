import CoreGraphics
import Testing
@testable import MissionControlPlusCore

@Suite("Geometry, Bundle ID, and Space Pill Layout")
struct GeometryAndBundleTests {
    @Test func featureConfigMasterSwitchPreservesFeatureToggles() {
        var config = FeatureConfig(
            isMasterEnabled: true,
            showWindowIcons: true,
            replaceSpaceNames: false,
            showWindowTitles: true,
            anchor: .topLeft
        )
        #expect(config.effectiveShowWindowIcons)
        #expect(!config.effectiveReplaceSpaceNames)
        #expect(config.effectiveShowWindowTitles)
        #expect(config.shouldRunEngine)

        config.isMasterEnabled = false
        #expect(!config.effectiveShowWindowIcons)
        #expect(!config.effectiveReplaceSpaceNames)
        #expect(!config.effectiveShowWindowTitles)
        #expect(!config.shouldRunEngine)
        // Individual preferences remain preserved while master is off.
        #expect(config.showWindowIcons)
        #expect(config.showWindowTitles)

        config.isMasterEnabled = true
        config.showWindowIcons = false
        #expect(!config.shouldRunEngine)
    }

    @Test func bundleIdentifierParser() {
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: "com.google.Chrome.space.1") == "com.google.Chrome")
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: "com.mitchellh.ghostty.space.42") == "com.mitchellh.ghostty")
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: "mc.spaces.add") == nil)
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: "mc.display") == nil)
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: "com.apple.Safari") == nil)
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: "com.example.space.abc") == nil)
        #expect(BundleIdentifierParser.bundleID(fromThumbnailIdentifier: nil) == nil)
    }

    @Test func displayGeometryConversionAndScreenLookup() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let geo = DisplayGeometry(primaryHeight: primary.height, screenFrames: [primary, external])

        let topLeft = CGRect(x: 100, y: 80, width: 400, height: 300)
        let appKit = geo.appKitRect(fromTopLeft: topLeft)
        #expect(appKit == CGRect(x: 100, y: 982 - 380, width: 400, height: 300))
        #expect(geo.topLeftRect(fromAppKit: appKit) == topLeft)
        #expect(geo.screenIndex(forAppKitRect: appKit) == 0)

        let extTopLeft = CGRect(x: 1700, y: 100, width: 600, height: 400)
        let extAppKit = geo.appKitRect(fromTopLeft: extTopLeft)
        #expect(geo.screenIndex(forAppKitRect: extAppKit) == 1)
    }

    @Test func spacePillLayoutModesAndNeighborClamping() {
        // 1. Explicit AXStaticText labelFrame
        let explicitItem = SpaceItem(
            title: "Top 10 recipes",
            frame: CGRect(x: 200, y: 20, width: 120, height: 75),
            labelFrame: CGRect(x: 215, y: 98, width: 90, height: 16),
            listFrame: CGRect(x: 50, y: 12, width: 900, height: 110)
        )
        let explicitPill = SpacePillLayout.pillFrame(for: explicitItem, displayTextWidth: 46, nativeTextWidth: 96)
        #expect(abs(explicitPill.midY - 106) <= 1.5)
        #expect(explicitPill.width >= 106)

        // 2. Compact collapsed text strip
        let compactItem = SpaceItem(
            title: "Top 10 recipes",
            frame: CGRect(x: 200, y: 18, width: 130, height: 26)
        )
        let compactPill = SpacePillLayout.pillFrame(for: compactItem, displayTextWidth: 46, nativeTextWidth: 110)
        #expect(compactPill.minY == 18)
        #expect(compactPill.height == 26)
        #expect(compactPill.width == 130)

        // 3. Expanded thumbnail cards normalized from WindowManager center-origin (e.g. 473,125 168x129 -> 389,60.5 168x129)
        let expandedItems = [
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Desktop", frame: CGRect(x: 389, y: 60.5, width: 168, height: 129), axIndex: 0),
                displayTextWidth: 50,
                nativeTextWidth: 50
            ),
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Logseq", frame: CGRect(x: 560, y: 60.5, width: 168, height: 129), axIndex: 1),
                displayTextWidth: 46,
                nativeTextWidth: 46
            ),
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Custom Mission Control ma...", frame: CGRect(x: 730, y: 60.5, width: 168, height: 129), axIndex: 2),
                displayTextWidth: 74,
                nativeTextWidth: 150
            ),
        ]
        #expect(SpacePillLayout.detectMode(for: expandedItems.map(\.space)) == .expanded)
        let expandedRects = SpacePillLayout.pillFrames(for: expandedItems)
        #expect(expandedRects.count == 3)
        // Label sits inside bottom band of card (y ~ 168.5..189.5), centered on each card's midX.
        #expect(abs(expandedRects[1].midX - 644) <= 1.0)
        #expect(abs(expandedRects[1].midY - 179) <= 1.5)
        // Adjacent pills must never overlap.
        #expect(expandedRects[1].maxX + SpacePillLayout.minInterPillGap <= expandedRects[2].minX + 1.0)

        // 4. Compact mode with variable X spacing when WindowManager keeps 129pt card height slid upward
        let compactRow = [
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Desktop", frame: CGRect(x: 65 - 84, y: 14 - 64.5, width: 168, height: 129), axIndex: 0),
                displayTextWidth: 50,
                nativeTextWidth: 58
            ),
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Logseq", frame: CGRect(x: 147 - 84, y: 14 - 64.5, width: 168, height: 129), axIndex: 1),
                displayTextWidth: 46,
                nativeTextWidth: 50
            ),
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Hub - Action", frame: CGRect(x: 245 - 84, y: 14 - 64.5, width: 168, height: 129), axIndex: 2),
                displayTextWidth: 46,
                nativeTextWidth: 88
            ),
            SpacePillLayout.LayoutItem(
                space: SpaceItem(title: "Custom Mission Control ma...", frame: CGRect(x: 421 - 84, y: 14 - 64.5, width: 168, height: 129), axIndex: 3),
                displayTextWidth: 74,
                nativeTextWidth: 208
            ),
        ]
        #expect(SpacePillLayout.detectMode(for: compactRow.map(\.space)) == .compact)
        let compactRects = SpacePillLayout.pillFrames(for: compactRow)
        for pair in zip(compactRects, compactRects.dropFirst()) {
            #expect(pair.0.maxX <= pair.1.minX)
        }
        // Bottom label band of slid-up 129pt card (maxY = 78.5 -> pill midY ~ 70.5)
        #expect(abs(compactRects[1].midY - 70.5) <= 1.0)
        #expect(abs(compactRects[3].midX - 421) <= 1.0)
    }

    @Test func overlayAnchorAndSizingPolicy() {
        let thumb = CGRect(x: 100, y: 100, width: 200, height: 150)
        let badge = CGSize(width: 48, height: 48)
        #expect(OverlayAnchor.center.origin(overlaySize: badge, in: thumb, inset: 8) == CGPoint(x: 176, y: 151))
        #expect(OverlayAnchor.topLeft.origin(overlaySize: badge, in: thumb, inset: 8) == CGPoint(x: 108, y: 194))
        #expect(OverlayAnchor.bottomRight.origin(overlaySize: badge, in: thumb, inset: 8) == CGPoint(x: 244, y: 108))

        let tinyIcon = OverlaySizingPolicy.iconSize(forThumbnailSize: CGSize(width: 40, height: 32), showingTitles: false)
        #expect(tinyIcon <= 20)
        let largeIcon = OverlaySizingPolicy.iconSize(forThumbnailSize: CGSize(width: 600, height: 400), showingTitles: false)
        #expect(largeIcon == 68)
    }
}

@Suite("Geometry, Title, and Formatter Matching")
struct MatcherTests {
    private func win(_ id: UInt32, _ pid: Int32, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> WindowRecord {
        WindowRecord(windowID: id, ownerPID: pid, frame: CGRect(x: x, y: y, width: w, height: h), layer: 0)
    }

    @Test func asymmetricCardInsetMatchesOnMacOS27() {
        let m = GeometryMatcher()
        let wins = [win(1, 10, 471, 110, 527, 331)]
        #expect(m.match(CGRect(x: 477, y: 111, width: 509, height: 319), in: wins) == .unique(wins[0]))
    }

    @Test func tooSmallPreviewRejected() {
        let m = GeometryMatcher()
        let wins = [win(1, 10, 471, 110, 527, 331)]
        #expect(m.match(CGRect(x: 490, y: 120, width: 420, height: 260), in: wins) == .none)
    }

    @Test func multiEllipsisAndSuffixTitleMatching() {
        #expect(TitleMatcher.matchesPattern("Interview Sim...Continuation", candidate: "Interview Simulation Continuation"))
        #expect(TitleMatcher.matchesPattern("Inline: Digital...(VST, Plugins)", candidate: "Inline: Digital Audio Workstations (VST, Plugins)"))
        #expect(TitleMatcher.matchesPattern("# Director of...uestions: F...", candidate: "# Director of Engineering Questions: Follow-up"))
        #expect(!TitleMatcher.matchesPattern("# Director of...uestions: F...", candidate: "# General Chat"))

        let variants = TitleMatcher.titleVariants(
            rawTitle: "Top 10 recipes - Audio playing - Google Chrome - Personal",
            shortName: "Chrome",
            localizedName: "Google Chrome"
        )
        #expect(variants.contains("Top 10 recipes - Audio playing"))
        #expect(variants.contains("Top 10 recipes"))

        let slackVariants = TitleMatcher.titleVariants(
            rawTitle: "# Director of Engineering Questions: Follow-up - Acme Corp - Slack",
            shortName: "Slack",
            localizedName: "Slack"
        )
        #expect(slackVariants.contains("# Director of Engineering Questions: Follow-up - Acme Corp"))
        #expect(slackVariants.contains("# Director of Engineering Questions: Follow-up"))

        let slackPipeVariants = TitleMatcher.titleVariants(
            rawTitle: "Slack | # Director of Engineering Questions: Follow-up | Acme Corp",
            shortName: "Slack",
            localizedName: "Slack"
        )
        #expect(slackPipeVariants.contains("# Director of Engineering Questions: Follow-up | Acme Corp"))
        #expect(slackPipeVariants.contains("# Director of Engineering Questions: Follow-up"))
    }

    @Test func titleFormatterVSCodeWorkspace() {
        let formatted = TitleFormatter.lines(
            title: "Engine.swift \u{2014} MissionControlPlus \u{2014} Visual Studio Code",
            appName: "Code",
            bundleID: "com.microsoft.VSCode"
        )
        #expect(formatted.primary == "MissionControlPlus")
        #expect(formatted.secondary == "Engine.swift \u{00B7} Code")
    }
}

@Suite("Grouped and Ungrouped Window Overlap Filtering")
struct OverlapFilterTests {
    private func badgeSize(_ overlay: ResolvedWindowOverlay) -> CGSize {
        let icon = OverlaySizingPolicy.iconSize(forThumbnailSize: overlay.frame.size, showingTitles: false)
        return OverlaySizingPolicy.badgeSize(forIconSize: icon)
    }

    private func badgeOrigin(_ size: CGSize, _ overlay: ResolvedWindowOverlay) -> CGPoint {
        OverlayAnchor.center.origin(overlaySize: size, in: overlay.frame, inset: 8)
    }

    @Test func ungroupedGridKeepsAllOverlays() {
        let overlays = [
            ResolvedWindowOverlay(frame: CGRect(x: 40, y: 120, width: 320, height: 220), appName: "Chrome", bundleID: "com.google.Chrome", ownerPID: 10, title: "Tab 1", axIndex: 0, confidence: .geometry),
            ResolvedWindowOverlay(frame: CGRect(x: 400, y: 120, width: 320, height: 220), appName: "Chrome", bundleID: "com.google.Chrome", ownerPID: 10, title: "Tab 2", axIndex: 1, confidence: .geometry),
            ResolvedWindowOverlay(frame: CGRect(x: 760, y: 120, width: 320, height: 220), appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", ownerPID: 20, title: "Slack", axIndex: 2, confidence: .geometry),
        ]
        let visible = WindowOverlapFilter.selectVisibleOverlays(
            from: overlays,
            badgeSizeForOverlay: badgeSize,
            badgeOriginForOverlay: badgeOrigin
        )
        #expect(visible.count == 3)
    }

    @Test func groupedStackedWindowsKeepOnlyFrontmostIcon() {
        let rear1 = ResolvedWindowOverlay(frame: CGRect(x: 110, y: 140, width: 300, height: 200), appName: "Chrome", bundleID: "com.google.Chrome", ownerPID: 10, title: "Old Tab", axIndex: 0, confidence: .identifier)
        let rear2 = ResolvedWindowOverlay(frame: CGRect(x: 105, y: 160, width: 310, height: 208), appName: "Chrome", bundleID: "com.google.Chrome", ownerPID: 10, title: "Mid Tab", axIndex: 1, confidence: .identifier)
        let front = ResolvedWindowOverlay(frame: CGRect(x: 100, y: 185, width: 325, height: 220), appName: "Chrome", bundleID: "com.google.Chrome", ownerPID: 10, title: "Front Tab", axIndex: 2, confidence: .geometry)
        let other = ResolvedWindowOverlay(frame: CGRect(x: 500, y: 185, width: 325, height: 220), appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", ownerPID: 20, title: "General", axIndex: 3, confidence: .geometry)

        let visible = WindowOverlapFilter.selectVisibleOverlays(
            from: [rear1, rear2, front, other],
            badgeSizeForOverlay: badgeSize,
            badgeOriginForOverlay: badgeOrigin
        )
        #expect(visible.count == 2)
        #expect(visible.map(\.title) == ["Front Tab", "General"])
    }
}

@Suite("Top Spaces Bar App Name Resolution")
struct SpaceTitleResolverTests {
    private let candidates: [AppWindowCandidate] = [
        AppWindowCandidate(
            ownerPID: 100,
            bundleID: "com.google.Chrome",
            shortName: "Chrome",
            localizedName: "Google Chrome",
            title: "Top 10 recipes - Google Chrome",
            isFullScreen: true
        ),
        AppWindowCandidate(
            ownerPID: 100,
            bundleID: "com.google.Chrome",
            shortName: "Chrome",
            localizedName: "Google Chrome",
            title: "Interview Simulation Continuation - Google Chrome - Personal",
            isFullScreen: true
        ),
        AppWindowCandidate(
            ownerPID: 100,
            bundleID: "com.google.Chrome",
            shortName: "Chrome",
            localizedName: "Google Chrome",
            title: "Arts & Crafts - Google Chrome",
            isFullScreen: true
        ),
        AppWindowCandidate(
            ownerPID: 200,
            bundleID: "com.tinyspeck.slackmacgap",
            shortName: "Slack",
            localizedName: "Slack",
            title: "# Director of Engineering Questions: Follow-up - Acme - Slack",
            isFullScreen: true
        ),
        AppWindowCandidate(
            ownerPID: 300,
            bundleID: "com.google.antigravity",
            shortName: "Antigravity",
            localizedName: "Antigravity",
            title: "Antigravity",
            isFullScreen: true
        ),
        AppWindowCandidate(
            ownerPID: 400,
            bundleID: "com.apple.Safari",
            shortName: "Safari",
            localizedName: "Safari",
            title: "Duplicate Title",
            isFullScreen: true
        ),
        AppWindowCandidate(
            ownerPID: 500,
            bundleID: "org.mozilla.firefox",
            shortName: "Firefox",
            localizedName: "Firefox",
            title: "Duplicate Title",
            isFullScreen: true
        ),
    ]

    @Test func resolvesFullScreenTitlesAndLeavesDesktopAndAmbiguousUntouched() {
        let spaces = [
            SpaceItem(title: "Desktop", frame: CGRect(x: 40, y: 20, width: 120, height: 70)),
            SpaceItem(title: "Desktop 2", frame: CGRect(x: 180, y: 20, width: 120, height: 70)),
            SpaceItem(title: "데스크탑 1", frame: CGRect(x: 240, y: 20, width: 120, height: 70)),
            SpaceItem(title: "Top 10 recipes", frame: CGRect(x: 320, y: 20, width: 120, height: 70)),
            SpaceItem(title: "Interview Sim...Continuation", frame: CGRect(x: 460, y: 20, width: 120, height: 70)),
            SpaceItem(title: "# Director of...uestions: F...", frame: CGRect(x: 600, y: 20, width: 120, height: 70)),
            SpaceItem(title: "Antigravity", frame: CGRect(x: 740, y: 20, width: 120, height: 70)),
            SpaceItem(title: "Duplicate Title", frame: CGRect(x: 880, y: 20, width: 120, height: 70)),
            SpaceItem(title: "Unknown Window", frame: CGRect(x: 1020, y: 20, width: 120, height: 70)),
        ]

        let resolved = SpaceTitleResolver.resolve(spaces: spaces, candidates: candidates)
        #expect(resolved.count == 3)
        #expect(resolved[0].displayName == "Chrome")
        #expect(resolved[1].displayName == "Chrome")
        #expect(resolved[2].displayName == "Slack")
    }

    @Test func splitViewAndAmpersandSingleTitle() {
        let artsSpace = SpaceItem(title: "Arts & Crafts", frame: CGRect(x: 40, y: 20, width: 120, height: 70))
        let artsResolved = SpaceTitleResolver.resolveOne(artsSpace, candidates: candidates)
        #expect(artsResolved?.displayName == "Chrome")
        #expect(artsResolved?.confidence == .fullScreenWindow)

        let splitSpace = SpaceItem(
            title: "Top 10 recipes & # Director of...uestions: F...",
            frame: CGRect(x: 180, y: 20, width: 120, height: 70)
        )
        let splitResolved = SpaceTitleResolver.resolveOne(splitSpace, candidates: candidates)
        #expect(splitResolved?.displayName == "Chrome & Slack")
        #expect(splitResolved?.confidence == .splitView)
    }

    @Test func managedSpaceDescriptorsResolveAuthoritativelyIncludingInactiveSpaces() {
        let spaces = [
            SpaceItem(title: "Desktop", frame: CGRect(x: 40, y: 20, width: 120, height: 80)),
            SpaceItem(title: "More researc...[[@Zhaklin...", frame: CGRect(x: 180, y: 20, width: 120, height: 80)),
            SpaceItem(title: "Hub - Action", frame: CGRect(x: 320, y: 20, width: 120, height: 80)),
            SpaceItem(title: "Change Missi...ontrol Labels", frame: CGRect(x: 460, y: 20, width: 120, height: 80)),
            SpaceItem(title: "Split Workspace", frame: CGRect(x: 600, y: 20, width: 120, height: 80)),
        ]
        let managed = [
            ManagedSpaceDescriptor(spaceIndex: 0, spaceID: 4, isFullScreen: false, appShortNames: []),
            ManagedSpaceDescriptor(spaceIndex: 1, spaceID: 892, isFullScreen: true, appShortNames: ["Logseq"]),
            ManagedSpaceDescriptor(spaceIndex: 2, spaceID: 489, isFullScreen: true, appShortNames: ["Notion"]),
            ManagedSpaceDescriptor(spaceIndex: 3, spaceID: 1777, isFullScreen: true, appShortNames: ["Antigravity"]),
            ManagedSpaceDescriptor(spaceIndex: 4, spaceID: 1900, isFullScreen: true, appShortNames: ["Chrome", "Slack"]),
        ]
        // Even if a non-fullscreen Chrome window on the Desktop has a matching title,
        // managedSpaces maps each Space to its true full-screen owner.
        let desktopChromeCandidate = [
            AppWindowCandidate(
                ownerPID: 44205,
                bundleID: "com.google.Chrome",
                shortName: "Chrome",
                localizedName: "Google Chrome",
                title: "Change Mission Control Labels - Google Chrome",
                isFullScreen: false
            ),
        ]

        let resolved = SpaceTitleResolver.resolve(
            spaces: spaces,
            managedSpaces: managed,
            candidates: desktopChromeCandidate
        )
        #expect(resolved.count == 4)
        #expect(resolved.map(\.displayName) == ["Logseq", "Notion", "Antigravity", "Chrome & Slack"])

        // Without managedSpaces, non-fullscreen Desktop windows still must never false-match a Space.
        let fallbackOnly = SpaceTitleResolver.resolve(
            spaces: spaces,
            managedSpaces: [],
            candidates: desktopChromeCandidate
        )
        #expect(fallbackOnly.isEmpty)
    }

    @Test func sameAppSplitViewCollapsesToSingleAppName() {
        let sameSplit = SpaceItem(
            title: "Top 10 recipes & Interview Sim...Continuation",
            frame: CGRect(x: 180, y: 20, width: 120, height: 70)
        )
        let resolved = SpaceTitleResolver.resolveOne(sameSplit, candidates: candidates)
        #expect(resolved?.displayName == "Chrome")
        #expect(resolved?.confidence == .splitView)
    }
}

@Suite("Layout Stability Detection")
struct LayoutStabilityTests {
    @Test func detectsSpaceChangeWhenThumbnailsStayIdentical() {
        let thumbs = [Thumbnail(title: "Window", frame: CGRect(x: 100, y: 200, width: 300, height: 200))]
        let s1 = MissionControlSnapshot(
            thumbnails: thumbs,
            spaces: [SpaceItem(title: "Top 10 recipes", frame: CGRect(x: 100, y: 15, width: 110, height: 26))]
        )
        let s2 = MissionControlSnapshot(
            thumbnails: thumbs,
            spaces: [SpaceItem(title: "Top 10 recipes", frame: CGRect(x: 100, y: 20, width: 125, height: 78))]
        )
        #expect(!LayoutStability.isStable(s1, s2))
        #expect(LayoutStability.isStable(s1, s1))
    }
}
