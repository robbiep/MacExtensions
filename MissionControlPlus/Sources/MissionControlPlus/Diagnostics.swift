import AppKit
import ApplicationServices
import MissionControlPlusCore

/// Captures Mission Control AX trees (including `mc.spaces*`) into local files under
/// `~/Library/Logs/MissionControlPlus` when explicitly triggered by the user.
final class Diagnostics {
    static let notFoundTimeout: TimeInterval = 15

    private let lock = NSLock()
    private var armed = false
    private var armedAt: Date?

    var isArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return armed
    }

    var armedSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let armedAt else { return -1 }
        return Date().timeIntervalSince(armedAt)
    }

    func arm() {
        lock.lock()
        armed = true
        armedAt = Date()
        lock.unlock()
    }

    func disarm() {
        lock.lock()
        armed = false
        armedAt = nil
        lock.unlock()
    }

    static var logDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/MissionControlPlus", isDirectory: true)
    }

    func write(
        reader: MissionControlReader,
        groups: [AXUIElement],
        snapshot: MissionControlSnapshot,
        outcome: WindowResolver.Outcome?,
        windows: [WindowRecord],
        appCandidates: [AppWindowCandidate] = [],
        managedSpaces: [ManagedSpaceDescriptor] = [],
        fixedFilename: String? = nil
    ) -> URL? {
        var s = header()
        reader.environmentReport(into: &s)
        s += "\n## Host Mission Control Trees\n"
        reader.dumpAllHostMissionControlTrees(into: &s)

        s += "\n## Thumbnails (\(snapshot.thumbnails.count))\n"
        for (i, t) in snapshot.thumbnails.enumerated() {
            s += "[\(i)] frame=\(fmt(t.frame)) id=\(t.identifier ?? "-") parsedBID=\(t.parsedBundleID ?? "-") title=\"\(t.title)\"\n"
        }

        s += "\n## Spaces (\(snapshot.spaces.count))\n"
        for (i, sp) in snapshot.spaces.enumerated() {
            let lf = sp.labelFrame.map(fmt) ?? "-"
            let listF = sp.listFrame.map(fmt) ?? "-"
            let rawF = sp.rawFrame.map(fmt) ?? "-"
            s += "[\(i)] frame=\(fmt(sp.frame)) raw=\(rawF) labelFrame=\(lf) listFrame=\(listF) id=\(sp.identifier ?? "-") title=\"\(sp.title)\"\n"
        }

        s += "\n## Managed Spaces from SkyLight (\(managedSpaces.count))\n"
        for (i, ms) in managedSpaces.enumerated() {
            s += "[\(i)] id=\(ms.spaceID) idx=\(ms.spaceIndex) fs=\(ms.isFullScreen) apps=\(ms.appShortNames) display=\(ms.displayUUID ?? "-")\n"
        }

        s += "\n## App AX Windows Across Spaces (\(appCandidates.count))\n"
        for c in appCandidates {
            s += "pid=\(c.ownerPID) short=\"\(c.shortName)\" local=\"\(c.localizedName)\" fs=\(c.isFullScreen) min=\(c.isMinimized) title=\"\(c.title)\"\n"
        }

        s += "\n## On-screen CG Windows (\(windows.count))\n"
        for w in windows {
            s += "wid=\(w.windowID) pid=\(w.ownerPID) owner=\(w.ownerName ?? "-") frame=\(fmt(w.frame))\n"
        }

        if let outcome {
            s += "\n## Thumbnail Matching\n"
            for (i, d) in outcome.thumbnailDetail.enumerated() {
                let r: String
                switch d.result {
                case .unique(let w): r = "unique wid=\(w.windowID) pid=\(w.ownerPID)"
                case .ambiguous(let ws): r = "ambiguous wids=\(ws.map(\.windowID))"
                case .none: r = "none"
                }
                s += "[\(i)] \(r) -> app=\"\(d.overlay.appName ?? "-")\" bid=\"\(d.overlay.bundleID ?? "-")\" title=\"\(d.overlay.title ?? "-")\" conf=\(d.overlay.confidence.rawValue)\n"
            }

            s += "\n## Spaces Resolution (\(outcome.spaceOverlays.count))\n"
            for (i, sp) in outcome.spaceOverlays.enumerated() {
                s += "[\(i)] \"\(sp.originalTitle)\" -> \"\(sp.displayName)\" conf=\(sp.confidence.rawValue)\n"
            }

            let st = outcome.stats
            s += "\n## Stats\nthumbnails=\(st.thumbnailCount) spaces=\(st.spaceCount) resolvedSpaces=\(st.resolvedSpaceCount) candidates=\(st.candidateWindowCount) unique=\(st.uniqueMatches) id=\(st.identifierMatches) fallback=\(st.titleUniqueFallbacks) unmatched=\(st.unmatched) elapsed=\(String(format: "%.1f", st.elapsed * 1000))ms\n"
        }

        return save(s, prefix: "diagnostic", fixedFilename: fixedFilename)
    }

    func writeNotFound(reader: MissionControlReader) -> URL? {
        var s = header()
        s += "\n## Status: Mission Control group not found within \(Int(Self.notFoundTimeout))s\n\n"
        reader.environmentReport(into: &s)
        return save(s, prefix: "not-found", fixedFilename: nil)
    }

    private func header() -> String {
        let f = ISO8601DateFormatter()
        var s = "# MissionControlPlus diagnostic \(f.string(from: Date()))\n"
        s += "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        s += "screens:\n"
        for sc in NSScreen.screens {
            s += "  frame=\(sc.frame) scale=\(sc.backingScaleFactor) name=\(sc.localizedName)\n"
        }
        return s
    }

    private func save(_ contents: String, prefix: String, fixedFilename: String?) -> URL? {
        let dir = Self.logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url: URL
        if let fixedFilename {
            url = dir.appendingPathComponent(fixedFilename)
        } else {
            let f = ISO8601DateFormatter()
            let stamp = f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            url = dir.appendingPathComponent("\(prefix)-\(stamp).txt")
        }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
    }
}
