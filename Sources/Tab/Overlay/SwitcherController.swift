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
    private let windowObserver = WindowEventObserver()

    private var entries: [WindowInfo] = []
    private var selected = 0
    private var visible = false
    private var activeWorkflow: Workflow?
    private var activeScreen: NSScreen?
    private var activeModifiers: Modifiers = []
    private var thumbnailTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?

    init() {
        let host = NSHostingView(rootView: SwitcherView(model: model))
        panel = SwitcherPanel(content: host)
        model.onHover = { [weak self] index in self?.hoverSelect(index) }
        model.onSelect = { [weak self] index in self?.mouseCommit(index) }
        windowObserver.onWindowCreated = { [weak self] in self?.scheduleRefresh() }
        windowObserver.onFocusChanged = { [weak self] pid, window in self?.windowFocused(pid: pid, window: window) }
        windowObserver.onAppRegistered = { [weak self] pid in self?.appRegistered(pid) }
    }

    /// Keeps the MRU order tracking real focus changes (clicks, ⌘`, new windows
    /// taking focus) instead of only what the switcher itself commits.
    private func windowFocused(pid: pid_t, window: AXUIElement) {
        // Some apps (Photoshop-style) focus a window *after* their app went
        // background; recording that would promote a background window over what
        // the user actually switched to.
        let app = NSRunningApplication(processIdentifier: pid)
        let wid = cgWindowID(of: window)
        Log.info("focus event: \(app?.localizedName ?? "pid \(pid)") wid=\(wid.map(String.init) ?? "nil") active=\(app?.isActive == true)")
        guard app?.isActive == true, let wid else { return }
        mru.recordFocus(cgWindowID: wid, pid: pid)
    }

    /// A just-launched app became observable. Its first window may have been
    /// created and focused before registration finished, so reconcile both the
    /// MRU (it's a stable moment — no raise in flight) and any open switcher.
    private func appRegistered(_ pid: pid_t) {
        Log.info("app registered: \(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)") active=\(NSRunningApplication(processIdentifier: pid)?.isActive == true)")
        if NSRunningApplication(processIdentifier: pid)?.isActive == true {
            mru.captureFocusedWindow(of: pid)
        }
        scheduleRefresh()
    }


    /// Call once Accessibility is granted (AX observers need the same trust as
    /// the event tap).
    func startWindowObservation() {
        windowObserver.start()
    }

    // MARK: - Mouse

    private func hoverSelect(_ index: Int) {
        guard visible, entries.indices.contains(index), selected != index else { return }
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
            if workflow.id == activeWorkflow?.id {
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
        activeWorkflow = workflow
        activeModifiers = workflow.shortcut.modifiers

        // Record the window the user is on now (catches within-app switches) so it
        // ranks as most-recent and the default selection lands on the previous one.
        mru.captureFrontmostWindow()
        entries = enumerate(workflow)
        let head = entries.prefix(4).map { "\($0.appName)#\($0.cgWindowID.map(String.init) ?? "nil")" }
        Log.info("show [\(workflow.name)]: \(entries.count) windows; head=\(head.joined(separator: ", ")); mruWindows=\(Array(mru.windowOrder.prefix(4)))")
        guard !entries.isEmpty else { return }

        let switchEntries = entries.map(makeSwitchEntry)
        model.entries = switchEntries
        selected = entries.count > 1 ? (forward ? 1 : entries.count - 1) : 0
        model.selectedIndex = selected

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first!
        activeScreen = screen
        layoutAndPresent(on: screen)
        visible = true
        startOutsideClickMonitor()

        loadThumbnails(for: entries, into: switchEntries)
    }

    private func enumerate(_ workflow: Workflow) -> [WindowInfo] {
        enumerator.enumerateWindows(
            excludedBundleIDs: Preferences.shared.excludedBundleIDs,
            includeMinimized: workflow.includeMinimized,
            includeHidden: workflow.includeHidden,
            currentSpaceOnly: workflow.spaceScope == .currentSpace,
            appOrder: mru.appOrder,
            windowOrder: mru.windowOrder
        )
    }

    /// Seeds the card with the last captured preview; the background pass refreshes.
    private func makeSwitchEntry(for info: WindowInfo) -> SwitchEntry {
        let entry = SwitchEntry(title: info.title, appName: info.appName, icon: info.icon, isMinimized: info.isMinimized)
        if let id = info.cgWindowID, let cached = ThumbnailCache.shared.image(for: id) {
            entry.thumbnail = cached
        }
        return entry
    }

    private func layoutAndPresent(on screen: NSScreen) {
        let metrics = SwitcherLayout.metrics(count: entries.count, maxWidth: screen.visibleFrame.width * 0.92)
        model.columns = metrics.columns
        panel.present(on: screen, width: metrics.width, height: metrics.height)
    }

    // MARK: - Live refresh

    /// A window was created somewhere while the switcher is up. Coalesce bursts
    /// (an app opening can create several windows back to back) into one refresh.
    private func scheduleRefresh() {
        guard visible else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self.refresh()
        }
    }

    /// Re-enumerates and merges into the open switcher: existing windows keep
    /// their positions (no mid-session reshuffle), closed ones drop out, and new
    /// ones append at the end. The selection follows the selected window.
    private func refresh() {
        guard visible, let workflow = activeWorkflow else { return }
        let fresh = enumerate(workflow)
        let freshByKey = Dictionary(fresh.map { (identity(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let selectedKey = entries.indices.contains(selected) ? identity(of: entries[selected]) : nil

        var keptInfos: [WindowInfo] = []
        var keptEntries: [SwitchEntry] = []
        var keptKeys = Set<String>()
        for (index, info) in entries.enumerated() {
            let key = identity(of: info)
            guard let updated = freshByKey[key] else { continue }
            keptKeys.insert(key)
            keptInfos.append(updated)
            keptEntries.append(model.entries[index])
        }

        let addedInfos = fresh.filter { !keptKeys.contains(identity(of: $0)) }
        guard !addedInfos.isEmpty || keptInfos.count != entries.count else { return }
        Log.info("refresh [\(workflow.name)]: +\(addedInfos.count) −\(entries.count - keptInfos.count) windows")

        let addedEntries = addedInfos.map(makeSwitchEntry)
        entries = keptInfos + addedInfos
        model.entries = keptEntries + addedEntries
        guard !entries.isEmpty else {
            cancel()
            return
        }

        selected = selectedKey.flatMap { key in entries.firstIndex { identity(of: $0) == key } }
            ?? min(selected, entries.count - 1)
        model.selectedIndex = selected

        layoutAndPresent(on: activeScreen ?? NSScreen.main ?? NSScreen.screens.first!)
        loadThumbnails(for: addedInfos, into: addedEntries)
    }

    /// Stable identity across enumerations: the CGWindowID when we have one, else
    /// the same (pid, title) key the enumerator dedupes by.
    private func identity(of info: WindowInfo) -> String {
        if let wid = info.cgWindowID { return "w\(wid)" }
        return "t\(info.pid)\u{1}\(info.title)"
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
            // Record the choice as most-recent before raising it, so the per-window MRU
            // reflects exactly what the user picked (not whatever the racy app-activation
            // focus read would have guessed).
            if let wid = target.cgWindowID {
                mru.recordFocus(cgWindowID: wid, pid: target.pid)
                mru.noteSwitcherRaise(pid: target.pid)
            }
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
        activeWorkflow = nil
        activeScreen = nil
        activeModifiers = []
        refreshTask?.cancel()
        refreshTask = nil
        thumbnailTasks.forEach { $0.cancel() }
        thumbnailTasks = []
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
    /// Passes for different batches (initial show, refresh additions) run
    /// concurrently; all are cancelled when the session ends.
    private func loadThumbnails(for infos: [WindowInfo], into entries: [SwitchEntry]) {
        guard ScreenRecording.isGranted else {
            Log.info("thumbnails skipped — Screen Recording not granted")
            return
        }
        thumbnailTasks.append(Task { @MainActor in
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
        })
    }
}
