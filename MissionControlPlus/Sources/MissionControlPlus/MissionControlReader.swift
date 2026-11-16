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

        return MissionControlSnapshot(thumbnails: thumbnails, spaces: spaces)
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

    func dumpTree(_ el: AXUIElement, depth: Int = 0, into out: inout String, maxDepth: Int = 12) {
        guard depth <= maxDepth else { return }
        let pad = String(repeating: "  ", count: depth)
        let role = AX.string(el, kAXRoleAttribute) ?? "?"
        let sub = AX.string(el, kAXSubroleAttribute).map { " sub=\($0)" } ?? ""
        let id = AX.string(el, kAXIdentifierAttribute).map { " id=\"\($0)\"" } ?? ""
        let title = AX.string(el, kAXTitleAttribute).map { " title=\"\($0)\"" } ?? ""
        let desc = AX.string(el, kAXDescriptionAttribute).map { " desc=\"\($0)\"" } ?? ""
        let rd = AX.string(el, kAXRoleDescriptionAttribute).map { " roleDesc=\"\($0)\"" } ?? ""
        let fr = AX.frame(el).map {
            " frame=\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))"
        } ?? ""
        out += "\(pad)\(role)\(sub)\(id)\(title)\(desc)\(rd)\(fr)\n"
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
            let title = AX.string(el, kAXTitleAttribute) ?? AX.string(el, kAXDescriptionAttribute) ?? ""
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
        guard depth < 8 else { return }
        let identifier = AX.string(el, kAXIdentifierAttribute)
        if identifier == "mc.spaces" {
            let spacesFrame = AX.frame(el)
            extractSpacesFromContainer(el, parentFrame: spacesFrame, into: &out)
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
        guard depth < 4 else { return }
        for child in AX.children(node) {
            let id = AX.string(child, kAXIdentifierAttribute)
            if id == "mc.spaces.add" { continue }

            let role = AX.string(child, kAXRoleAttribute) ?? ""
            let isButtonLike = role == kAXButtonRole as String
                || role == kAXRadioButtonRole as String
                || (role == kAXGroupRole as String && hasSpaceText(child))

            if isButtonLike, let frame = AX.frame(child), frame.width >= 16, frame.height >= 14 {
                let title = (AX.string(child, kAXTitleAttribute)
                    ?? AX.string(child, kAXDescriptionAttribute)
                    ?? findStaticTextValue(child)
                    ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let labelFrame = findStaticTextFrame(child)
                out.append(
                    SpaceItem(
                        title: title,
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

    private func hasSpaceText(_ el: AXUIElement) -> Bool {
        if let t = AX.string(el, kAXTitleAttribute), !t.isEmpty { return true }
        if let d = AX.string(el, kAXDescriptionAttribute), !d.isEmpty { return true }
        return findStaticTextValue(el) != nil
    }

    private func findStaticTextValue(_ el: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 3 else { return nil }
        for child in AX.children(el) {
            if AX.string(child, kAXRoleAttribute) == kAXStaticTextRole as String {
                if let val = AX.string(child, kAXValueAttribute) ?? AX.string(child, kAXTitleAttribute),
                   !val.isEmpty {
                    return val
                }
            }
            if let nested = findStaticTextValue(child, depth: depth + 1) { return nested }
        }
        return nil
    }

    private func findStaticTextFrame(_ el: AXUIElement, depth: Int = 0) -> CGRect? {
        guard depth < 3 else { return nil }
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
