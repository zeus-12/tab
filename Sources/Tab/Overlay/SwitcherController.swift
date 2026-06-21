import AppKit
import SwiftUI
import CoreGraphics

/// Orchestrates a switch session for whichever *workflow* matched the pressed
/// shortcut: enumerate windows with that workflow's filters, show the overlay,
/// cycle on each repeat press, and commit when the trigger modifiers are released.
///
/// All key input arrives from `KeyInterceptor`'s event tap. While the settings UI
/// is recording a shortcut, keys are forwarded to `ShortcutCapture` instead.
@MainActor
final class SwitcherController {
    private let model = SwitcherModel()
    private let panel: SwitcherPanel
    private let enumerator = WindowEnumerator()
    private let mru = MRUTracker()

    private var entries: [WindowInfo] = []
    private var selected = 0
    private var visible = false
    private var activeWorkflowID: UUID?
    private var activeModifiers: Modifiers = []
    private var thumbnailTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?

    init() {
        let host = NSHostingView(rootView: SwitcherView(model: model))
        panel = SwitcherPanel(content: host)
        model.onHover = { [weak self] index in self?.hoverSelect(index) }
        model.onSelect = { [weak self] index in self?.mouseCommit(index) }
    }

    // MARK: - Mouse

    private func hoverSelect(_ index: Int) {
        guard visible, entries.indices.contains(index) else { return }
        selected = index
        model.suppressScroll = true   // card is already under the cursor
        model.selectedIndex = index
    }

    private func mouseCommit(_ index: Int) {
        guard visible, entries.indices.contains(index) else { return }
        selected = index
        commit()
    }

    // MARK: - Input from the event tap

    /// Returns true if the key was consumed.
    func handleKeyDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let modifiers = Modifiers(cgFlags: flags)

        // Recording a shortcut in Settings: swallow keys and forward them.
        if ShortcutCapture.isRecording {
            ShortcutCapture.handle(keyCode: Int(keyCode), modifiers: modifiers)
            return true
        }

        if keyCode == 53 && visible { // escape
            cancel()
            return true
        }

        guard let workflow = WorkflowStore.shared.match(keyCode: Int(keyCode), modifiers: modifiers) else {
            return false
        }

        let backward = modifiers.contains(.shift)
        if visible {
            if workflow.id == activeWorkflowID {
                move(forward: !backward)
            }
        } else {
            show(workflow: workflow, forward: !backward)
        }
        return true
    }

    func handleFlagsChanged(flags: CGEventFlags) {
        guard visible else { return }
        // Commit once the workflow's trigger modifiers are no longer all held.
        let held = Modifiers(cgFlags: flags)
        if !held.isSuperset(of: activeModifiers) {
            commit()
        }
    }

    // MARK: - Session

    private func show(workflow: Workflow, forward: Bool) {
        activeWorkflowID = workflow.id
        activeModifiers = workflow.shortcut.modifiers

        entries = enumerator.enumerateWindows(
            excludedBundleIDs: Preferences.shared.excludedBundleIDs,
            includeMinimized: workflow.includeMinimized,
            currentSpaceOnly: workflow.spaceScope == .currentSpace,
            mruOrder: mru.order
        )
        Log.info("show [\(workflow.name)]: \(entries.count) windows")
        guard !entries.isEmpty else { return }

        let switchEntries = entries.map {
            SwitchEntry(title: $0.title, appName: $0.appName, icon: $0.icon, isMinimized: $0.isMinimized)
        }
        // Show the last captured preview immediately; the background pass refreshes.
        for (index, info) in entries.enumerated() {
            if let id = info.cgWindowID, let cached = ThumbnailCache.shared.image(for: id) {
                switchEntries[index].thumbnail = cached
            }
        }
        model.entries = switchEntries
        selected = entries.count > 1 ? (forward ? 1 : entries.count - 1) : 0
        model.selectedIndex = selected

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first!
        let width = SwitcherLayout.panelWidth(count: entries.count, maxWidth: screen.visibleFrame.width * 0.92)
        panel.present(on: screen, width: width)
        visible = true
        startOutsideClickMonitor()

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
        activeWorkflowID = nil
        activeModifiers = []
        thumbnailTask?.cancel()
        thumbnailTask = nil
        stopOutsideClickMonitor()
        panel.orderOut(nil)
    }

    // MARK: - Click outside to cancel

    /// A click anywhere outside our panel (i.e. in another app) cancels, mirroring
    /// Escape. Clicks on the panel itself are local events and never reach this
    /// global monitor, so they go to the cards instead.
    private func startOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
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
            ThumbnailCache.shared.retain(only: Set(windows.keys))
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
                            ThumbnailCache.shared.store(image, for: id)
                        }
                    }
                }
            }
        }
    }
}
