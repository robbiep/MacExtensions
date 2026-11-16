# MacExtensions

Standalone, reversible macOS utility extensions built with Swift and read-only Accessibility / click-through overlays (no SIP changes, no system process injection).

## Extensions

| Extension | Description | README |
|---|---|---|
| `MissionControlPlus` | Shows app icons over Mission Control window thumbnails and replaces contextual full-screen Space names in the top Spaces bar with short app names (`Chrome`, `Slack`, etc.), with master & per-feature toggle switches. | [MissionControlPlus/README.md](MissionControlPlus/README.md) |

## Quick Start

```sh
cd MissionControlPlus
./scripts/test.sh
./scripts/build-app.sh release
open build/MissionControlPlus.app
```

Each extension lives in its own subfolder with an independent Swift package, bundle ID, and `.app` bundle so permissions (**Privacy & Security → Device Control and Data Access**) and removal stay isolated. See [AGENTS.md](AGENTS.md) for conventions and macOS 27 development notes.
