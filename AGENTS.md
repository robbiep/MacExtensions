# MacExtensions Agent Guide

Monorepo for standalone macOS utility extensions.

## Structure & Conventions
- **One extension per subfolder** (e.g., `MissionControlPlus/`), with its own `Package.swift`, unique bundle ID (`com.robbieperlstein.<Name>`), and `scripts/build-app.sh` so TCC permissions and removal stay isolated. Only create a shared local package (`SharedKit/`) when multiple apps share helpers.
- **Reversible by design:** Prefer read-only Accessibility (`AXUIElement`) + click-through `NSWindow` overlays (`ignoresMouseEvents = true`). Do not disable SIP, inject into system processes, or mutate system `defaults` (e.g., `com.apple.dock`).
- **Control UI:** Provide a Settings/Controls window + menu bar popover (`NSStatusItem`) with a master On/Off switch, per-feature toggles, and **Launch at Login** disabled by default.

## Toolchain & Signing
- If full `Xcode.app` is absent (CommandLineTools only), `XCTest` is unavailable—use Swift `Testing` (`import Testing`) and run tests with `TestingMacros` plugin path (see `MissionControlPlus/scripts/test.sh`).
- Ad-hoc builds (`codesign --sign -`) change CDHash on every rebuild. On macOS 27+, **Privacy & Security → Device Control and Data Access** (Accessibility) has no `–` delete button—provide a reset action (`tccutil reset Accessibility <bundleID>`) or sign with `SIGN_IDENTITY`.

## macOS 27 Window/Space Quirks
- Mission Control's AX tree lives under `com.apple.WindowManager` (`mc.display`, `mc.spaces`, `mc.spaces.list`), while `com.apple.dock` keeps an empty `mc` stub (still keep `Dock` as fallback for macOS 14–26).
- In `WindowManager`'s `mc.spaces.list`, `AXButton` `kAXPositionAttribute` is `(midX, midY)` rather than top-left `(minX, minY)`, and deflated (compact) mode slides the `129pt` card upward rather than shrinking `AXSize.height`.
- `kAXWindowsAttribute` only sees active-Space windows; use `SkyLight`'s `SLSCopyManagedDisplaySpaces` via `dlopen`/`dlsym` to map inactive full-screen and Split View Spaces to owning PIDs.

## Testing Rules
- Never simulate hotkeys or trigger Mission Control/UI actions on the user's active desktop. Validate pure logic via `swift test` (`*Core` module) and write diagnostics locally (`~/Library/Logs/<AppName>/`) for user-triggered live inspection.
