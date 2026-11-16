import AppKit
import MissionControlPlusCore

/// Transparent, non-activating, click-through overlay window pinned per physical display.
final class OverlayWindow: NSWindow {
    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages screen-aligned overlay windows on the main thread.
final class OverlayController {
    static let inset: CGFloat = 8

    var config: FeatureConfig

    private var windows: [OverlayWindow] = []
    private var geometry = DisplayGeometry(primaryHeight: 0, screenFrames: [])
    private let sessions: SessionCounter
    private let iconProvider = AppIconProvider()
    private(set) var isShowing = false

    init(sessions: SessionCounter, config: FeatureConfig = FeatureConfig()) {
        self.sessions = sessions
        self.config = config

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screensChanged() {
        tearDown()
    }

    private func refreshGeometry() {
        let screens = NSScreen.screens
        let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first
        geometry = DisplayGeometry(primaryHeight: primary?.frame.height ?? 0, screenFrames: screens.map(\.frame))
        if windows.count != screens.count || zip(windows, screens).contains(where: { $0.frame != $1.frame }) {
            tearDown()
            windows = screens.map { OverlayWindow(screenFrame: $0.frame) }
        }
    }

    func show(
        windowOverlays: [ResolvedWindowOverlay],
        spaceOverlays: [ResolvedSpaceOverlay],
        allSpaces: [SpaceItem],
        session: SessionToken
    ) {
        guard sessions.isCurrent(session) else { return }
        refreshGeometry()
        iconProvider.invalidateSessionCaches()

        for win in windows {
            win.contentView?.subviews.forEach { $0.removeFromSuperview() }
        }

        if config.effectiveShowWindowIcons {
            renderWindowOverlays(windowOverlays)
        }
        if config.effectiveReplaceSpaceNames {
            renderSpaceOverlays(spaceOverlays, allSpaces: allSpaces)
        }

        for win in windows {
            let hasContent = !(win.contentView?.subviews.isEmpty ?? true)
            if hasContent {
                win.orderFrontRegardless()
            } else {
                win.orderOut(nil)
            }
        }
        isShowing = true
    }

    func hide() {
        guard isShowing else { return }
        for win in windows {
            win.orderOut(nil)
            win.contentView?.subviews.forEach { $0.removeFromSuperview() }
        }
        isShowing = false
    }

    func tearDown() {
        isShowing = false
        for win in windows {
            win.orderOut(nil)
            win.close()
        }
        windows.removeAll()
    }

    // MARK: - Rendering

    private func renderWindowOverlays(_ overlays: [ResolvedWindowOverlay]) {
        let showTitles = config.effectiveShowWindowTitles
        let currentAnchor = config.anchor

        let eligible = overlays.filter { item in
            let icon = iconProvider.icon(for: item.ownerPID, bundleID: item.bundleID)
            if icon != nil { return true }
            return showTitles && (item.formattedTitleLines.primary != nil || item.formattedTitleLines.secondary != nil)
        }

        let visible = WindowOverlapFilter.selectVisibleOverlays(
            from: eligible,
            badgeSizeForOverlay: { [weak self] item in
                let hasIcon = self?.iconProvider.icon(for: item.ownerPID, bundleID: item.bundleID) != nil
                return IconOverlayView.preferredSize(
                    for: item,
                    thumbnailSize: item.frame.size,
                    showTitle: showTitles,
                    hasIcon: hasIcon
                )
            },
            badgeOriginForOverlay: { [geometry] badgeSize, item in
                let appKitThumb = geometry.appKitRect(fromTopLeft: item.frame)
                return currentAnchor.origin(overlaySize: badgeSize, in: appKitThumb, inset: Self.inset)
            }
        )

        for overlay in visible {
            let appKitRect = geometry.appKitRect(fromTopLeft: overlay.frame)
            guard let screenIdx = geometry.screenIndex(forAppKitRect: appKitRect),
                  screenIdx < windows.count else { continue }
            let window = windows[screenIdx]
            let localThumb = geometry.localRect(appKitRect, inScreen: geometry.screenFrames[screenIdx])
            let icon = iconProvider.icon(for: overlay.ownerPID, bundleID: overlay.bundleID)

            let view = IconOverlayView(
                overlay: overlay,
                icon: icon,
                thumbnailSize: localThumb.size,
                showTitle: showTitles,
                alignment: currentAnchor.alignment
            )
            let origin = currentAnchor.origin(overlaySize: view.frame.size, in: localThumb, inset: Self.inset)
            view.frame = NSRect(origin: origin, size: view.frame.size)
            window.contentView?.addSubview(view)
        }
    }

    private func renderSpaceOverlays(_ spaceOverlays: [ResolvedSpaceOverlay], allSpaces: [SpaceItem]) {
        let sortedAll = allSpaces.sorted { a, b in
            if abs(a.frame.midY - b.frame.midY) > 40 { return a.frame.midY < b.frame.midY }
            return a.frame.midX < b.frame.midX
        }

        let overlayByIndex = Dictionary(
            uniqueKeysWithValues: spaceOverlays.map { ($0.spaceItem.axIndex, $0) }
        )

        let layoutInputs: [SpacePillLayout.LayoutItem] = sortedAll.map { space in
            let resolved = overlayByIndex[space.axIndex]
            let displayText = resolved?.displayName ?? space.title
            let nativeText = resolved?.originalTitle ?? space.title
            let displayW = SpaceLabelView.measureTextWidth(displayText, font: SpaceLabelView.displayFont)
            let nativeW = SpaceLabelView.measureTextWidth(nativeText, font: SpaceLabelView.nativeEstimateFont)
            return SpacePillLayout.LayoutItem(space: space, displayTextWidth: displayW, nativeTextWidth: nativeW)
        }

        let pillRects = SpacePillLayout.pillFrames(for: layoutInputs)

        for (space, pillCG) in zip(sortedAll, pillRects) {
            guard let overlay = overlayByIndex[space.axIndex] else { continue }
            let pillAppKit = geometry.appKitRect(fromTopLeft: pillCG)
            guard let screenIdx = geometry.screenIndex(forAppKitRect: pillAppKit),
                  screenIdx < windows.count else { continue }
            let window = windows[screenIdx]
            let localPill = geometry.localRect(pillAppKit, inScreen: geometry.screenFrames[screenIdx])
            let pillView = SpaceLabelView(frame: localPill, text: overlay.displayName)
            window.contentView?.addSubview(pillView)
        }
    }
}
