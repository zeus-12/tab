import AppKit
import ApplicationServices

/// Watches every regular app through one AXObserver each, reporting two events:
/// a window was created (so an open switcher can refresh its list) and a window
/// became its app's focused window (so the MRU order tracks focus as it actually
/// changes — the event hands us the focused window element, avoiding the racy
/// "read the focused window now" query that `MRUTracker` documents).
///
/// Apps are picked up as they launch and dropped when they quit. Needs
/// Accessibility trust, so `start()` waits until the event tap (same permission)
/// is running.
@MainActor
final class WindowEventObserver {
    var onWindowCreated: (() -> Void)?
    /// The element is the newly focused window of the app with this pid.
    var onFocusChanged: ((pid_t, AXUIElement) -> Void)?
    /// A newly launched app's registration completed. Windows it created or
    /// focused before this point emitted no events, so the receiver should
    /// reconcile once.
    var onAppRegistered: ((pid_t) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var started = false

    private let notifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]

    /// A freshly launched app may not answer AX requests until it finishes
    /// starting up, so registration retries before giving up.
    private let maxAttempts = 5

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(pid: app.processIdentifier, attempt: 1, isNewLaunch: false)
        }
        Log.info("window observer: watching \(observers.count) apps")
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        observe(pid: app.processIdentifier, attempt: 1, isNewLaunch: true)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let observer = observers.removeValue(forKey: app.processIdentifier) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func observe(pid: pid_t, attempt: Int, isNewLaunch: Bool) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, windowEventCallback, &observer) == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let results = notifications.map {
            AXObserverAddNotification(observer, appElement, $0 as CFString, refcon)
        }
        guard results.allSatisfy({ $0 == .success }) else {
            // Partial registrations die with this observer; the retry starts fresh.
            guard attempt < maxAttempts else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.observe(pid: pid, attempt: attempt + 1, isNewLaunch: isNewLaunch)
            }
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        if isNewLaunch { onAppRegistered?(pid) }
    }
}

/// Delivered on the main run loop (where every observer's source is scheduled),
/// so hopping onto the main actor is safe.
private let windowEventCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let target = Unmanaged<WindowEventObserver>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        switch notification as String {
        case kAXWindowCreatedNotification:
            target.onWindowCreated?()
        case kAXFocusedWindowChangedNotification:
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            target.onFocusChanged?(pid, element)
        default:
            break
        }
    }
}
