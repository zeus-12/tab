# Tab

A fast, native Alt-Tab-style window switcher for macOS. Built with Swift + SwiftUI + AppKit.

## Status: MVP foundation

Working now:

- Menu-bar agent app (no Dock icon).
- Global hotkeys via Carbon: **⌥Tab** (forward) / **⌥⇧Tab** (backward).
- Hold ⌥, tap Tab to cycle, **release ⌥ to commit** — overlay never steals focus.
- Window enumeration across **all Spaces** via the Accessibility API (public, no private SkyLight calls).
- Raises/unminimizes the chosen window and activates its app (follows it to its Space).
- App-exclusion list (seeded with Parallels / VMware), persisted in `UserDefaults`.
- Non-activating floating `NSPanel` overlay with a SwiftUI card row + live selection.

## Build & run

Requires the Swift toolchain (Command Line Tools is enough — no full Xcode needed).

```sh
./scripts/build-app.sh release
open Tab.app
```

On first launch, grant **Accessibility** in
System Settings ▸ Privacy & Security ▸ Accessibility (toggle "Tab" on).
This is mandatory — without it, windows can't be enumerated or raised.

## Architecture

| Area | File |
|---|---|
| App entry / lifecycle | `Sources/Tab/main.swift`, `App/AppDelegate.swift` |
| Global hotkeys (Carbon) | `Hotkeys/HotKeyManager.swift` |
| Window enumeration (AX) | `Windows/WindowEnumerator.swift` |
| Raise / activate | `Windows/WindowActivator.swift` |
| Overlay panel | `Overlay/SwitcherPanel.swift` |
| Overlay UI (SwiftUI) | `Overlay/SwitcherView.swift` |
| Session orchestration | `Overlay/SwitcherController.swift` |
| Permissions | `Permissions/Permissions.swift` |
| Settings storage | `Settings/Preferences.swift` |

## Roadmap

- [x] **Workflows** — any number of named switcher modes, each with a unique shortcut
      and its own filters (Show-minimized, Space scope). Configured in the Workflows
      settings tab. Multi-shortcut engine matches the combo → runs that workflow.
- [ ] **Full-screen detection + real Spaces switching** — via private SkyLight APIs;
      adds per-workflow "show full-screen" and a Spaces-switching workflow.
- [ ] **Combined mode** — a workflow showing windows + Spaces together.
- [x] **Live thumbnails** via ScreenCaptureKit (AX→CGWindowID via `_AXUIElementGetWindow`), icon fallback.
- [ ] **Full-screen window toggle** — include/exclude full-screen windows per settings.
- [x] **Settings window** — liquid-glass NavigationSplitView (General / Behavior / Exclusions / About).
      Launch-at-login, include-minimized toggle, and a running-app exclusions editor — all wired to real behavior.
- [ ] **Configurable shortcuts** — let the trigger key be changed in Settings (currently fixed to ⌘Tab).
- [x] **MRU ordering** — apps ordered by real most-recently-used recency (`MRUTracker`).
- [ ] **Escape to cancel / arrow-key navigation** via a CGEventTap.
- [ ] **Launch at login** via `SMAppService`.
