# MissionControlPlus

A native macOS app with a Control Panel window and menu bar popover providing:
- A **master On/Off toggle switch** to enable or pause all Mission Control enhancements at any time
- **Independent feature toggle switches** for:
  1. **App Icons on Windows:** Displays crisp app icons over Mission Control window thumbnails (supporting both grouped `expose-group-apps = 1` stacks and ungrouped grids cleanly, plus toggles for **Show Window Titles** and **Icon Position**).
  2. **App Names in Top Spaces Bar:** Replaces contextual full-screen Space names in the Mission Control top Spaces bar (e.g. `"Top 10 recipes"`, `"Interview Sim...Continuation"`, `"# Director of..."`) with the owning application's short name (`"Chrome"`, `"Slack"`, `"Code"`), handling both compact and expanded bar states plus Split View (`"App1 & App2"`).

Uses only Accessibility permissions (no SIP changes, no Screen Recording, no Dock injection).

## Build & Run

```sh
cd MissionControlPlus
./scripts/test.sh
./scripts/build-app.sh release
open build/MissionControlPlus.app
```

Launching opens the **MissionControlPlus** controls window with toggle switches (closing the window keeps it running in the menu bar popover). On first launch, allow `MissionControlPlus` under **System Settings → Privacy & Security → Device Control and Data Access** (Accessibility).

> Note: If built with ad-hoc signing (`-`), click **Reset Stale Entry** in the app (or run `tccutil reset Accessibility com.robbieperlstein.MissionControlPlus`) and re-enable the toggle after rebuilding.

## Undo / Remove Completely

1. Quit `MissionControlPlus` (turn off **Launch at Login** first if enabled).
2. Remove `MissionControlPlus` from **System Settings → Privacy & Security → Accessibility** (or run `tccutil reset Accessibility com.robbieperlstein.MissionControlPlus`).
3. Clear preferences (`defaults delete com.robbieperlstein.MissionControlPlus`) and delete `MissionControlPlus/`.
