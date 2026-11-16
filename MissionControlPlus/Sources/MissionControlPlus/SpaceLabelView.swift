import AppKit

/// Masked frosted-dark capsule covering the native contextual Space label in the top bar
/// and replacing it with the concise Application name (`"Chrome"`, `"Slack"`, `"Chrome & Slack"`).
final class SpaceLabelView: NSView {
    static let displayFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let nativeEstimateFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let pillBackground = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 0.94)
    private static let borderColor = NSColor.white.withAlphaComponent(0.18)

    private let labelText: String

    static func measureTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: 600, height: 30),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        return ceil(rect.width)
    }

    init(frame: NSRect, text: String) {
        self.labelText = text
        super.init(frame: frame)
        wantsLayer = true

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        self.shadow = shadow

        let radius = round(frame.height / 2)

        let bg = NSView(frame: bounds)
        bg.wantsLayer = true
        bg.autoresizingMask = [.width, .height]
        bg.layer?.backgroundColor = Self.pillBackground.cgColor
        bg.layer?.cornerRadius = radius
        bg.layer?.cornerCurve = .continuous
        addSubview(bg)

        let border = HairlineBorderView(frame: bounds, cornerRadius: radius, color: Self.borderColor)
        border.autoresizingMask = [.width, .height]
        addSubview(border)

        let textLayer = PillTextView(frame: bounds.insetBy(dx: 8, dy: 0), text: text)
        textLayer.autoresizingMask = [.width, .height]
        addSubview(textLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private final class PillTextView: NSView {
        private let text: String

        init(frame: NSRect, text: String) {
            self.text = text
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            ps.lineBreakMode = .byTruncatingTail

            let attrs: [NSAttributedString.Key: Any] = [
                .font: SpaceLabelView.displayFont,
                .foregroundColor: NSColor.white,
                .paragraphStyle: ps,
            ]
            let measured = (text as NSString).size(withAttributes: attrs)
            let y = max(0, floor((bounds.height - measured.height) / 2))
            (text as NSString).draw(
                with: NSRect(x: 0, y: y, width: bounds.width, height: measured.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attrs
            )
        }
    }
}
