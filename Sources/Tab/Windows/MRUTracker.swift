import AppKit
import ApplicationServices
import CoreGraphics

/// Tracks the most-recently-used order of *windows* (not just apps) by observing
/// activation events. This is what makes Command+Tab land on the previously used
/// window as the second entry — the classic switcher behavior. macOS has no public
/// API for this ordering, so we maintain it ourselves.
///
/// Recency is per window, keyed by CGWindowID: focusing one window of an app
/// promotes only that window, so an app's other windows keep their own places in
/// the order (a two-window app no longer drags both windows to the front when you
/// raise one of them).
///
/// We learn which window is focused two ways: the switcher tells us exactly which
/// window it committed (`recordSelection`), and just before showing the switcher we
/// read the frontmost app's focused window (`captureFrontmostWindow`), which catches
/// focus changes made outside the switcher — clicking a window, native ⌘Tab, or
/// switching windows within an app.
///
/// We deliberately do NOT read the focused window on the app-activation notification:
/// during our own cross-Space raise that notification fires before focus settles, so
/// it reads the app's *previously* focused window and mis-promotes it (which made
/// raising one window of a two-window app drag its sibling to the front). Activation
/// still updates the per-app order, which needs no AX read.
@MainActor
final class MRUTracker {
    /// PIDs, most-recently-active first. Secondary key: orders windows we've never
    /// seen focused (e.g. an app's background windows) by how recent their app is.
    private(set) var appOrder: [pid_t] = []

    /// CGWindowIDs, most-recently-focused first.
    private(set) var windowOrder: [CGWindowID] = []

    /// Owning pid per tracked window, so we can drop a window's entries when its
    /// app quits.
    private var pidByWindow: [CGWindowID: pid_t] = [:]

    init() {
        seed()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    private func seed() {
        if let front = NSWorkspace.shared.frontmostApplication {
            appOrder.append(front.processIdentifier)
            promoteFocusedWindow(of: front.processIdentifier)
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            if !appOrder.contains(pid) { appOrder.append(pid) }
        }
    }

    /// Records the frontmost app's focused window as most-recent. Call right before
    /// reading `windowOrder` to enumerate, so within-app window switches (which fire
    /// no activation notification) are reflected.
    func captureFrontmostWindow() {
        if let front = NSWorkspace.shared.frontmostApplication {
            promoteFocusedWindow(of: front.processIdentifier)
        }
    }

    /// Records the window the switcher just committed to as most-recent. Authoritative
    /// — we know exactly which window was chosen, so this avoids the focus-read race on
    /// app activation.
    func recordSelection(cgWindowID: CGWindowID, pid: pid_t) {
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
        windowOrder.removeAll { $0 == cgWindowID }
        windowOrder.insert(cgWindowID, at: 0)
        pidByWindow[cgWindowID] = pid
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        appOrder.removeAll { $0 == pid }
        let gone = pidByWindow.filter { $0.value == pid }.map(\.key)
        for wid in gone { pidByWindow[wid] = nil }
        windowOrder.removeAll { gone.contains($0) }
    }

    /// Moves the app's currently focused window to the front of `windowOrder`.
    private func promoteFocusedWindow(of pid: pid_t) {
        guard let wid = focusedWindowID(of: pid) else { return }
        windowOrder.removeAll { $0 == wid }
        windowOrder.insert(wid, at: 0)
        pidByWindow[wid] = pid
    }

    /// The CGWindowID of an app's focused window, or nil if AX can't tell us.
    private func focusedWindowID(of pid: pid_t) -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return cgWindowID(of: value as! AXUIElement)
    }
}
