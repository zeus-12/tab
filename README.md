> [!IMPORTANT]
> **Tab has moved into [Ral](https://github.com/zeus-12/ral).**
>
> The window switcher grew up. It's now part of Ral, a free, open-source Raycast
> alternative for macOS (and more). You get the same ⌘Tab switching with live previews, plus a launcher,
> clipboard history, snippets, window layouts, on-device dictation, an AI assistant and
> Raycast Store extensions, all in one app.
>
> This repo is archived and won't get updates. Head over to Ral for everything new.

# Tab

A fast window switcher for macOS. Switch between all your windows —
across every Space, with live previews — and build your own switching workflows,
each with its own keyboard shortcut.

## Install

1. Download the latest **Tab.zip** from the [Releases page](https://github.com/zeus-12/tab/releases).
2. Unzip it and move **Tab.app** into your **Applications** folder.
3. Open the Terminal app and run this once, so macOS will let the app open:
   ```
   xattr -dr com.apple.quarantine /Applications/Tab.app
   ```
4. Open **Tab**. When prompted, allow **Accessibility** and **Screen Recording** —
   these let Tab list your windows and show live previews.

Tab lives in your menu bar (no Dock icon).

## Using Tab

- **⌘Tab** — switch windows. Hold ⌘, tap Tab to move through them, release to switch.
  Add **⇧** to go backwards. Press **Esc** to cancel.
- Click the menu-bar icon ▸ **Settings ▸ Workflows** to create your own switchers.
  Each workflow has its own shortcut and filters — show minimized windows or not,
  the current Space only or all Spaces, and more.

To quit, click the menu-bar icon ▸ **Quit Tab**.

---

Building from source or cutting a release? See [DEVELOPMENT.md](DEVELOPMENT.md)
(it's a Swift project — plain `bash` scripts, no Node/pnpm).
