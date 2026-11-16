import AppKit
import CoreGraphics
import Darwin
import Foundation
import MissionControlPlusCore

/// Reads authoritative Space-to-Application ownership from macOS WindowServer (`SkyLight`),
/// including Full-Screen and Split View Spaces across inactive workspaces.
enum SpaceOwnershipReader {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> CFArray?

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static let mainConnectionID: MainConnectionIDFn? = {
        guard let handle = skyLightHandle,
              let sym = dlsym(handle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnectionIDFn.self)
    }()

    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = {
        guard let handle = skyLightHandle,
              let sym = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(sym, to: CopyManagedDisplaySpacesFn.self)
    }()

    static func managedSpaces(excludedPIDs: Set<pid_t> = []) -> [ManagedSpaceDescriptor] {
        guard let mainConnectionID, let copyManagedDisplaySpaces else { return [] }
        let cid = mainConnectionID()
        guard let displays = copyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            return []
        }

        let screenUUIDs = NSScreen.screens.compactMap(displayUUID(for:))
        let orderedDisplays: [[String: Any]]
        if !screenUUIDs.isEmpty {
            orderedDisplays = displays.sorted { a, b in
                let ua = (a["Display Identifier"] as? String) ?? ""
                let ub = (b["Display Identifier"] as? String) ?? ""
                let ia = screenUUIDs.firstIndex(of: ua) ?? Int.max
                let ib = screenUUIDs.firstIndex(of: ub) ?? Int.max
                return ia < ib
            }
        } else {
            orderedDisplays = displays
        }

        var result: [ManagedSpaceDescriptor] = []
        for display in orderedDisplays {
            let displayID = display["Display Identifier"] as? String
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }

            for (idx, sp) in spaces.enumerated() {
                let spaceID = (sp["id64"] as? NSNumber)?.uint64Value
                    ?? (sp["ManagedSpaceID"] as? NSNumber)?.uint64Value
                    ?? UInt64(idx)
                let type = (sp["type"] as? NSNumber)?.intValue ?? 0
                let isFullScreen = (type != 0) || (sp["TileLayoutManager"] != nil) || (sp["pid"] != nil)

                var pids: [pid_t] = []
                if let tileMgr = sp["TileLayoutManager"] as? [String: Any],
                   let tiles = tileMgr["TileSpaces"] as? [[String: Any]],
                   !tiles.isEmpty {
                    let sortedTiles = tiles.sorted { lhs, rhs in
                        let lx = (lhs["TileRect"] as? [String: Any]).flatMap { ($0["X"] as? NSNumber)?.doubleValue } ?? 0
                        let rx = (rhs["TileRect"] as? [String: Any]).flatMap { ($0["X"] as? NSNumber)?.doubleValue } ?? 0
                        return lx < rx
                    }
                    for tile in sortedTiles {
                        if let pid = (tile["pid"] as? NSNumber)?.int32Value, pid > 0, !excludedPIDs.contains(pid) {
                            pids.append(pid)
                        }
                    }
                }
                if pids.isEmpty,
                   let pid = (sp["pid"] as? NSNumber)?.int32Value,
                   pid > 0,
                   !excludedPIDs.contains(pid) {
                    pids.append(pid)
                }

                let appNames = pids.compactMap { pid -> String? in
                    guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
                    return AppNameHelper.shortName(for: app)
                }

                result.append(
                    ManagedSpaceDescriptor(
                        displayUUID: displayID,
                        spaceIndex: idx,
                        spaceID: spaceID,
                        isFullScreen: isFullScreen,
                        appShortNames: appNames
                    )
                )
            }
        }
        return result
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let did = CGDirectDisplayID(num.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
