import AppKit
import MissionControlPlusCore

/// Renders either a clean centered/corner app icon squircle or an icon+title glass card.
final class IconOverlayView: NSView {
    private static let cardBackground = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 0.78)
    private static let titleCardBackground = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 0.88)
    private static let borderColor = NSColor.white.withAlphaComponent(0.22)
    private static let titleFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    private static let subtitleFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)

    /// Computes exact view frame size before instantiating the view (used for overlap/anchor layout).
    static func preferredSize(
        for overlay: ResolvedWindowOverlay,
        thumbnailSize: CGSize,
        showTitle: Bool,
        hasIcon: Bool
    ) -> CGSize {
        let iconSide = OverlaySizingPolicy.iconSize(forThumbnailSize: thumbnailSize, showingTitles: showTitle)
        if !showTitle {
            return OverlaySizingPolicy.badgeSize(forIconSize: iconSide)
        }

        let maxWidth = min(340, max(96, thumbnailSize.width - 16))
        let padH: CGFloat = 12
        let padV: CGFloat = 9
        let iconReserve: CGFloat = hasIcon ? (iconSide + 10) : 0
        let textMaxW = max(24, maxWidth - padH * 2 - iconReserve)
        let lineLimit = max(1, OverlaySizingPolicy.titleLineLimit(forThumbnailHeight: thumbnailSize.height))
        let lines = overlay.formattedTitleLines

        var textW: CGFloat = 0
        var textH: CGFloat = 0
        if let primary = lines.primary {
            let r = measureText(primary, width: textMaxW, font: titleFont, maxLines: lineLimit)
            textW = max(textW, r.width)
            textH += r.height
        }
        if let secondary = lines.secondary, OverlaySizingPolicy.titleLineLimit(forThumbnailHeight: thumbnailSize.height) > 0 {
            let r = measureText(secondary, width: textMaxW, font: subtitleFont, maxLines: 1)
            textW = max(textW, r.width)
            textH += (textH > 0 ? 2 : 0) + r.height
        }

        if textH == 0 {
            return OverlaySizingPolicy.badgeSize(forIconSize: iconSide)
        }

        let width = min(maxWidth, ceil(padH * 2 + iconReserve + textW))
        let height = ceil(padV * 2 + max(hasIcon ? iconSide : 0, textH))
        return CGSize(width: width, height: height)
    }

    init(
        overlay: ResolvedWindowOverlay,
        icon: NSImage?,
        thumbnailSize: CGSize,
        showTitle: Bool,
        alignment: OverlayAnchor.Alignment
    ) {
        let size = Self.preferredSize(
            for: overlay,
            thumbnailSize: thumbnailSize,
            showTitle: showTitle,
            hasIcon: icon != nil
        )
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true

        let iconSide = OverlaySizingPolicy.iconSize(forThumbnailSize: thumbnailSize, showingTitles: showTitle)
        let cornerRadius: CGFloat = showTitle ? 13 : round(min(size.width, size.height) * 0.24)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        self.shadow = shadow

        let bg = NSView(frame: bounds)
        bg.wantsLayer = true
        bg.autoresizingMask = [.width, .height]
        bg.layer?.backgroundColor = (showTitle ? Self.titleCardBackground : Self.cardBackground).cgColor
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.cornerCurve = .continuous
        addSubview(bg)

        let border = HairlineBorderView(frame: bounds, cornerRadius: cornerRadius, color: Self.borderColor)
        border.autoresizingMask = [.width, .height]
        addSubview(border)

        if !showTitle || (overlay.formattedTitleLines.primary == nil && overlay.formattedTitleLines.secondary == nil) {
            if let icon {
                let imageView = makeIconView(
                    icon: icon,
                    frame: NSRect(
                        x: round((bounds.width - iconSide) / 2),
                        y: round((bounds.height - iconSide) / 2),
                        width: iconSide,
                        height: iconSide
                    )
                )
                addSubview(imageView)
            }
            return
        }

        let padH: CGFloat = 12
        let padV: CGFloat = 9
        let iconGap: CGFloat = 10
        var textX = padH
        if let icon {
            let iconView = makeIconView(
                icon: icon,
                frame: NSRect(
                    x: padH,
                    y: round((bounds.height - iconSide) / 2),
                    width: iconSide,
                    height: iconSide
                )
            )
            addSubview(iconView)
            textX += iconSide + iconGap
        }

        let textRect = NSRect(
            x: textX,
            y: padV,
            width: max(10, bounds.width - textX - padH),
            height: max(10, bounds.height - padV * 2)
        )
        let lines = overlay.formattedTitleLines
        let lineLimit = max(1, OverlaySizingPolicy.titleLineLimit(forThumbnailHeight: thumbnailSize.height))
        let textView = TitleStackView(
            frame: textRect,
            primary: lines.primary,
            secondary: OverlaySizingPolicy.titleLineLimit(forThumbnailHeight: thumbnailSize.height) > 0 ? lines.secondary : nil,
            lineLimit: lineLimit,
            alignment: icon != nil ? .left : alignment.nsAlignment
        )
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func makeIconView(icon: NSImage, frame: NSRect) -> NSImageView {
        let view = NSImageView(frame: frame)
        view.image = icon
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    private static func measureText(_ text: String, width: CGFloat, font: NSFont, maxLines: Int) -> CGSize {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        let lineH = ceil(font.ascender - font.descender + font.leading)
        let maxH = lineH * CGFloat(max(1, maxLines))
        let r = (text as NSString).boundingRect(
            with: NSSize(width: width, height: maxH),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .paragraphStyle: ps]
        )
        return CGSize(width: min(width, ceil(r.width)), height: min(maxH, ceil(r.height)))
    }

    private final class TitleStackView: NSView {
        private let primary: String?
        private let secondary: String?
        private let lineLimit: Int
        private let alignment: NSTextAlignment

        init(frame: NSRect, primary: String?, secondary: String?, lineLimit: Int, alignment: NSTextAlignment) {
            self.primary = primary
            self.secondary = secondary
            self.lineLimit = lineLimit
            self.alignment = alignment
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            let pSize = primary.map { IconOverlayView.measureText($0, width: bounds.width, font: IconOverlayView.titleFont, maxLines: lineLimit) } ?? .zero
            let sSize = secondary.map { IconOverlayView.measureText($0, width: bounds.width, font: IconOverlayView.subtitleFont, maxLines: 1) } ?? .zero
            let gap: CGFloat = (primary != nil && secondary != nil) ? 2 : 0
            let totalH = pSize.height + gap + sSize.height
            var y = max(0, floor((bounds.height - totalH) / 2))

            if let primary {
                drawString(primary, y: y, height: pSize.height, font: IconOverlayView.titleFont, color: .white)
                y += pSize.height + gap
            }
            if let secondary {
                drawString(
                    secondary,
                    y: y,
                    height: sSize.height,
                    font: IconOverlayView.subtitleFont,
                    color: NSColor.white.withAlphaComponent(0.76)
                )
            }
        }

        private func drawString(_ text: String, y: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
            let ps = NSMutableParagraphStyle()
            ps.lineBreakMode = .byWordWrapping
            ps.alignment = alignment
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: ps,
            ]
            (text as NSString).draw(
                with: NSRect(x: 0, y: y, width: bounds.width, height: height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attrs
            )
        }
    }
}

final class HairlineBorderView: NSView {
    private let cornerRadius: CGFloat
    private let color: NSColor

    init(frame: NSRect, cornerRadius: CGFloat, color: NSColor) {
        self.cornerRadius = cornerRadius
        self.color = color
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2
        let strokeW = 1 / scale
        let rect = bounds.insetBy(dx: strokeW / 2, dy: strokeW / 2)
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        color.setStroke()
        path.lineWidth = strokeW
        path.stroke()
    }
}

private extension OverlayAnchor.Alignment {
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
