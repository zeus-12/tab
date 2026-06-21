import AppKit

/// Tracks the most-recently-used order of applications by observing activation
/// events. This is what makes Command+Tab land on the *previously used* app as
/// the second entry — the classic switcher behavior. macOS has no public API for
/// this ordering, so we maintain it ourselves.
///
/// Our overlay is non-activating, so cycling through it never changes the
/// frontmost app; the order only updates when a real activation happens (launch,
/// click, or our own commit). That keeps the ordering stable mid-switch.
@MainActor
final class MRUTracker {
    /// PIDs, most-recently-active first.
    private(set) var order: [pid_t] = []

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
            order.append(front.processIdentifier)
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            if !order.contains(pid) { order.append(pid) }
        }
    }

    /// Recency rank for a pid (0 = most recent). Unknown pids sort last.
    func rank(_ pid: pid_t) -> Int {
        order.firstIndex(of: pid) ?? Int.max
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        order.removeAll { $0 == app.processIdentifier }
    }
}
