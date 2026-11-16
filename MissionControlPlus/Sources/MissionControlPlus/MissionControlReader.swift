import AppKit
import ApplicationServices
import MissionControlPlusCore

/// Reads Mission Control display groups, window thumbnails, and top Spaces bar items via AX.
/// Checks `com.apple.WindowManager` first (macOS 27+), falling back to `com.apple.dock` (macOS 14–26).
final class MissionControlReader {
    static let hostBundleIDs = ["com.apple.WindowManager", "com.apple.dock"]
    static let messagingTimeout: Float = 0.25

    var hostPIDs: Set<pid_t> {
        Set(
            NSWorkspace.shared.runningApplications
                .filter { Self.hostBundleIDs.contains($0.bundleIdentifier ?? "") }
                .map(\.processIdentifier)
        )
    }

    func missionControlGroups() -> [AXUIElement] {
        let hosts = Self.hostBundleIDs.compactMap(application)
        for host in hosts {
            let displays = AX.children(host).filter { AX.string($0, kAXIdentifierAttribute) == "mc.display" }
            if !displays.isEmpty { return displays }
        }
        for host in hosts {
            let children = AX.children(host)
            if let legacy = children.first(where: { AX.string($0, kAXIdentifierAttribute) == "mc" }) {
                return [legacy]
            }
            if let legacy = children.first(where: {
                AX.string($0, kAXRoleAttribute) == kAXGroupRole as String
                    && AX.string($0, kAXTitleAttribute) == "Mission Control"
            }) {
                return [legacy]
            }
        }
        return []
    }

    func snapshot(in groups: [AXUIElement], collectThumbnails: Bool, collectSpaces: Bool) -> MissionControlSnapshot {
        var thumbnails: [Thumbnail] = []
        var spaces: [SpaceItem] = []

        for group in groups {
            if collectThumbnails {
                collectThumbnailNodes(group, depth: 0, into: &thumbnails)
            }
            if collectSpaces {
                collectSpaceNodes(group, depth: 0, into: &spaces)
            }
        }

        // Fallback: if spaces weren't inside the active display groups (e.g. split across Dock & WindowManager),
        // scan both host processes for `mc.spaces` / `mc.spaces.list`.
        if collectSpaces && spaces.isEmpty {
            for bid in Self.hostBundleIDs {
                guard let host = application(bid) else { continue }
                collectSpaceNodes(host, depth: 0, into: &spaces)
                if !spaces.isEmpty { break }
            }
        }

        spaces = normalizeSpaceFrames(spaces)
        return MissionControlSnapshot(thumbnails: thumbnails, spaces: spaces)
    }

    /// macOS 27 `WindowManager` reports `kAXPositionAttribute` of `mc.spaces.list` buttons as their
    /// visual center `(midX, midY)` rather than their top-left `(minX, minY)`. Detect that invariant
    /// and normalize to standard top-left `CGRect` coordinates.
    private func normalizeSpaceFrames(_ items: [SpaceItem]) -> [SpaceItem] {
        guard !items.isEmpty else { return items }
        let needsCenterNormalization = items.contains { item in
            guard let listFrame = item.listFrame else { return false }
            return item.frame.maxY > listFrame.maxY + 6
        } || isCenteredInsideContainer(items)

        guard needsCenterNormalization else { return items }
        return items.map { item in
            var copy = item
            let raw = item.frame
            copy.rawFrame = raw
            copy.frame = CGRect(
                x: raw.origin.x - raw.width / 2,
                y: raw.origin.y - raw.height / 2,
                width: raw.width,
                height: raw.height
            )
            return copy
        }
    }

    private func isCenteredInsideContainer(_ items: [SpaceItem]) -> Bool {
        guard let listFrame = items.first?.listFrame, listFrame.width > 0 else { return false }
        let sorted = items.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard let first = sorted.first, let last = sorted.last else { return false }
        let rawMid = (first.frame.origin.x + last.frame.origin.x) / 2
        let topLeftMid = (first.frame.midX + last.frame.midX) / 2
        return abs(rawMid - listFrame.midX) + 12 < abs(topLeftMid - listFrame.midX)
    }

    func environmentReport(into out: inout String) {
        out += "AX hosts tried:\n"
        for bid in Self.hostBundleIDs {
            guard let el = application(bid) else {
                out += "  \(bid): process not running\n"
                continue
            }
            let children = AX.children(el)
            out += "  \(bid): \(children.count) top-level children\n"
            for child in children {
                let role = AX.string(child, kAXRoleAttribute) ?? "?"
                let id = AX.string(child, kAXIdentifierAttribute) ?? "-"
                let title = AX.string(child, kAXTitleAttribute) ?? "-"
                out += "    \(role) id=\"\(id)\" title=\"\(title)\" children=\(AX.children(child).count)\n"
            }
        }
    }

    func dumpAllHostMissionControlTrees(into out: inout String) {
        for bid in Self.hostBundleIDs {
            guard let host = application(bid) else { continue }
            out += "=== Host: \(bid) ===\n"
            for child in AX.children(host) {
                let id = AX.string(child, kAXIdentifierAttribute) ?? ""
                let title = AX.string(child, kAXTitleAttribute) ?? ""
                if id.hasPrefix("mc") || title == "Mission Control" {
                    dumpTree(child, into: &out, maxDepth: 12)
                }
            }
        }
    }

    func dumpTree(_ el: AXUIElement, depth: Int = 0, into out: inout String, maxDepth: Int = 12) {
        guard depth <= maxDepth else { return }
        let pad = String(repeating: "  ", count: depth)
        let role = AX.string(el, kAXRoleAttribute) ?? "?"
        let sub = AX.string(el, kAXSubroleAttribute).map { " sub=\($0)" } ?? ""
        let id = AX.string(el, kAXIdentifierAttribute).map { " id=\"\($0)\"" } ?? ""
        let title = AX.string(el, kAXTitleAttribute).map { " title=\"\($0)\"" } ?? ""
        let desc = AX.string(el, kAXDescriptionAttribute).map { " desc=\"\($0)\"" } ?? ""
        let val = AX.string(el, kAXValueAttribute).map { " val=\"\($0)\"" } ?? ""
        let rd = AX.string(el, kAXRoleDescriptionAttribute).map { " roleDesc=\"\($0)\"" } ?? ""
        let fr = AX.frame(el).map {
            " frame=\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))"
        } ?? ""
        out += "\(pad)\(role)\(sub)\(id)\(title)\(desc)\(val)\(rd)\(fr)\n"
        for child in AX.children(el) {
            dumpTree(child, depth: depth + 1, into: &out, maxDepth: maxDepth)
        }
    }

    // MARK: - Private traversal

    private func application(_ bundleID: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, Self.messagingTimeout)
        return el
    }

    private func collectThumbnailNodes(_ el: AXUIElement, depth: Int, into out: inout [Thumbnail]) {
        guard depth < 12 else { return }
        let identifier = AX.string(el, kAXIdentifierAttribute)
        if let identifier, identifier.hasPrefix("mc.spaces") { return }

        let role = AX.string(el, kAXRoleAttribute)
        if role == kAXButtonRole as String,
           let frame = AX.frame(el),
           frame.width >= 8,
           frame.height >= 8 {
            let title = AX.nonEmptyString(el, [kAXTitleAttribute, kAXDescriptionAttribute]) ?? ""
            out.append(
                Thumbnail(
                    title: title,
                    frame: frame,
                    identifier: identifier,
                    roleDescription: AX.string(el, kAXRoleDescriptionAttribute),
                    axIndex: out.count
                )
            )
            return
        }
        for child in AX.children(el) {
            collectThumbnailNodes(child, depth: depth + 1, into: &out)
        }
    }

    private func collectSpaceNodes(_ el: AXUIElement, depth: Int, into out: inout [SpaceItem]) {
        guard depth < 10 else { return }
        let identifier = AX.string(el, kAXIdentifierAttribute)
        if identifier == "mc.spaces" {
            let spacesFrame = AX.frame(el)
            extractSpacesFromContainer(el, parentFrame: spacesFrame, into: &out)
            return
        }
        if identifier == "mc.spaces.list" {
            let listFrame = AX.frame(el)
            collectSpaceButtons(in: el, listFrame: listFrame, depth: 0, into: &out)
            return
        }
        for child in AX.children(el) {
            collectSpaceNodes(child, depth: depth + 1, into: &out)
        }
    }

    private func extractSpacesFromContainer(_ container: AXUIElement, parentFrame: CGRect?, into out: inout [SpaceItem]) {
        let children = AX.children(container)
        if let list = children.first(where: { AX.string($0, kAXIdentifierAttribute) == "mc.spaces.list" })
            ?? children.first(where: { AX.string($0, kAXRoleAttribute) == kAXListRole as String }) {
            let listFrame = AX.frame(list) ?? parentFrame
            collectSpaceButtons(in: list, listFrame: listFrame, depth: 0, into: &out)
        } else {
            collectSpaceButtons(in: container, listFrame: parentFrame, depth: 0, into: &out)
        }
    }

    private func collectSpaceButtons(
        in node: AXUIElement,
        listFrame: CGRect?,
        depth: Int,
        into out: inout [SpaceItem]
    ) {
        guard depth < 5 else { return }
        for child in AX.children(node) {
            let id = AX.string(child, kAXIdentifierAttribute)
            if id == "mc.spaces.add" { continue }

            let role = AX.string(child, kAXRoleAttribute) ?? ""
            let textFromElement = AX.nonEmptyString(
                child,
                [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            )
            let textFromChild = textFromElement == nil ? findStaticTextValue(child) : nil
            let resolvedText = textFromElement ?? textFromChild

            let isButtonLike = role == kAXButtonRole as String
                || role == kAXRadioButtonRole as String
                || (role == kAXGroupRole as String && resolvedText != nil)

            if isButtonLike, let frame = AX.frame(child), frame.width >= 16, frame.height >= 14 {
                let labelFrame = findStaticTextFrame(child)
                out.append(
                    SpaceItem(
                        title: resolvedText ?? "",
                        frame: frame,
                        labelFrame: labelFrame,
                        listFrame: listFrame,
                        identifier: id,
                        roleDescription: AX.string(child, kAXRoleDescriptionAttribute),
                        axIndex: out.count
                    )
                )
            } else {
                collectSpaceButtons(in: child, listFrame: listFrame, depth: depth + 1, into: &out)
            }
        }
    }

    private func findStaticTextValue(_ el: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        for child in AX.children(el) {
            if AX.string(child, kAXRoleAttribute) == kAXStaticTextRole as String {
                if let val = AX.nonEmptyString(child, [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]) {
                    return val
                }
            }
            if let nested = findStaticTextValue(child, depth: depth + 1) { return nested }
        }
        return nil
    }

    private func findStaticTextFrame(_ el: AXUIElement, depth: Int = 0) -> CGRect? {
        guard depth < 4 else { return nil }
        for child in AX.children(el) {
            if AX.string(child, kAXRoleAttribute) == kAXStaticTextRole as String,
               let frame = AX.frame(child),
               frame.width > 2,
               frame.height > 2 {
                return frame
            }
            if let nested = findStaticTextFrame(child, depth: depth + 1) { return nested }
        }
        return nil
    }
}
