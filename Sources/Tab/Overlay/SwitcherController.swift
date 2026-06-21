import AppKit
import SwiftUI
import CoreGraphics

/// Orchestrates a switch session: enumerate windows, show the overlay, cycle the
/// selection on each Command+Tab, and commit when Command is released.
///
/// All key input arrives from `KeyInterceptor`'s event tap. Command+Tab is
/// consumed (so the system switcher never appears); releasing Command commits the
/// current selection; Escape cancels.
@MainActor
final class SwitcherController {
    private let model = SwitcherModel()
    private let panel: SwitcherPanel
    private let enumerator = WindowEnumerator()
    private let mru = MRUTracker()

    private var entries: [WindowInfo] = []
    private var selected = 0
    private var visible = false
    private var thumbnailTask: Task<Void, Never>?

    init() {
        let host = NSHostingView(rootView: SwitcherView(model: model))
        panel = SwitcherPanel(content: host)
    }

    // MARK: - Input from the event tap

    /// Returns true if the key was consumed.
    func handleKeyDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let tabKey: Int64 = 48
        let escapeKey: Int64 = 53

        if keyCode == tabKey && flags.contains(.maskCommand) {
            advance(forward: !flags.contains(.maskShift))
            return true
        }
        if keyCode == escapeKey && visible {
            cancel()
            return true
        }
        return false
    }

    func handleFlagsChanged(flags: CGEventFlags) {
        // Command released while the switcher is up → the user has chosen.
        if visible && !flags.contains(.maskCommand) {
            commit()
        }
    }

    // MARK: - Session

    private func advance(forward: Bool) {
        if visible {
            move(forward: forward)
        } else {
            show(forward: forward)
        }
    }

    private func show(forward: Bool) {
        entries = enumerator.enumerateWindows(
            excludedBundleIDs: Preferences.shared.excludedBundleIDs,
            includeMinimized: Preferences.shared.includeMinimizedWindows,
            mruOrder: mru.order
        )
        Log.info("show: \(entries.count) windows")
        guard !entries.isEmpty else { return }

        let switchEntries = entries.map {
            SwitchEntry(title: $0.title, appName: $0.appName, icon: $0.icon, isMinimized: $0.isMinimized)
        }
        model.entries = switchEntries

        // Start on the second entry going forward (the previously-used window),
        // or the last entry going backward.
        selected = entries.count > 1 ? (forward ? 1 : entries.count - 1) : 0
        model.selectedIndex = selected

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first!
        panel.present(on: screen)
        visible = true

        loadThumbnails(for: entries, into: switchEntries)
    }

    private func move(forward: Bool) {
        guard !entries.isEmpty else { return }
        selected = (selected + (forward ? 1 : -1) + entries.count) % entries.count
        model.selectedIndex = selected
    }

    private func commit() {
        guard visible else { return }
        let target = entries.indices.contains(selected) ? entries[selected] : nil
        end()
        if let target {
            Log.info("commit: \(target.appName) — \(target.title)")
            WindowActivator.activate(target)
        }
    }

    private func cancel() {
        guard visible else { return }
        Log.info("cancel")
        end()
    }

    private func end() {
        visible = false
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panel.orderOut(nil)
    }

    // MARK: - Thumbnails

    /// Loads live previews asynchronously, updating each card as its capture
    /// completes. Icons are shown until (and unless) a thumbnail arrives.
    private func loadThumbnails(for infos: [WindowInfo], into entries: [SwitchEntry]) {
        guard ScreenRecording.isGranted else {
            Log.info("thumbnails skipped — Screen Recording not granted")
            return
        }
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor in
            let windows = await ThumbnailProvider.shareableWindows()
            Log.info("thumbnails: \(windows.count) shareable windows for \(infos.count) entries")
            if Task.isCancelled { return }
            await withTaskGroup(of: Void.self) { group in
                for (index, info) in infos.enumerated() {
                    guard let id = info.cgWindowID, let scWindow = windows[id] else { continue }
                    let entry = entries[index]
                    group.addTask { @MainActor in
                        if Task.isCancelled { return }
                        if let image = await ThumbnailProvider.capture(scWindow) {
                            entry.thumbnail = image
                        }
                    }
                }
            }
        }
    }
}
