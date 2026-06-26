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
/// We learn which window is focused two ways: on every app activation we read that
/// app's focused window, and just before showing the switcher we read the frontmost
/// app's focused window (which catches switches *within* an already-frontmost app,
/// where no activation fires). Our overlay is non-activating, so cycling through it
/// never changes the frontmost app; the order only updates on real focus changes.
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

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
        promoteFocusedWindow(of: pid)
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
