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
/// We learn which window is focused several ways:
///   - The switcher tells us exactly which window it committed (`recordFocus` at
///     commit) — authoritative, no read.
///   - AX focus-change events hand us the newly focused window on *within-app*
///     focus changes (`recordFocus` via `WindowEventObserver`) — event-driven, no
///     read. Note these do NOT fire on app switches: activating an app doesn't
///     change its internal focused-window attribute.
///   - App activation (`appActivated`) reads the now-frontmost app's focused
///     window — the signal for external app switches (click, Dock, launch), which
///     emit no focus-change event. This read is skipped when the activation is the
///     switcher's own raise (`noteSwitcherRaise`): mid-raise the read returns the
///     app's *previously* focused window and would mis-promote it (which made
///     raising one window of a two-window app drag its sibling to the front) — and
///     the commit already recorded the true target anyway.
///   - Just before showing the switcher we read the frontmost app's focused window
///     (`captureFrontmostWindow`) as a final backstop.
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

    /// The app the switcher just raised, consumed by that app's next activation so
    /// the racy mid-raise focus read is skipped (see class comment). Time-bounded:
    /// a same-app commit fires no activation, and the token must not suppress a
    /// later genuine one.
    private var switcherRaise: (pid: pid_t, at: Date)?

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
            captureFocusedWindow(of: front.processIdentifier)
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
            captureFocusedWindow(of: front.processIdentifier)
        }
    }

    /// Reads `pid`'s focused window via AX and records it. Safe only at stable
    /// moments (switcher about to show, an app finished launching) — never during a
    /// raise, where the read returns the previous window (see class comment).
    func captureFocusedWindow(of pid: pid_t) {
        guard let wid = focusedWindowID(of: pid) else {
            Log.info("capture focus: pid=\(pid) — no focused window readable")
            return
        }
        Log.info("capture focus: pid=\(pid) wid=\(wid)")
        windowOrder.removeAll { $0 == wid }
        windowOrder.insert(wid, at: 0)
        pidByWindow[wid] = pid
    }

    /// Records a known-focused window as most-recent, promoting its app too. Fed by
    /// the two authoritative sources: the switcher's committed selection and AX
    /// focus-change events (both name the exact window, so no focus read is needed).
    func recordFocus(cgWindowID: CGWindowID, pid: pid_t) {
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
        windowOrder.removeAll { $0 == cgWindowID }
        windowOrder.insert(cgWindowID, at: 0)
        pidByWindow[cgWindowID] = pid
    }

    /// Call at commit, right after `recordFocus`, so the raise's own activation
    /// doesn't re-read focus mid-transition.
    func noteSwitcherRaise(pid: pid_t) {
        switcherRaise = (pid, Date())
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
        if let raise = switcherRaise, raise.pid == pid, Date().timeIntervalSince(raise.at) < 1 {
            switcherRaise = nil
            return
        }
        captureFocusedWindow(of: pid)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        appOrder.removeAll { $0 == pid }
        let gone = pidByWindow.filter { $0.value == pid }.map(\.key)
        for wid in gone { pidByWindow[wid] = nil }
        windowOrder.removeAll { gone.contains($0) }
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
