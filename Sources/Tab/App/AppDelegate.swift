import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let interceptor = KeyInterceptor()
    private var switcher: SwitcherController!
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("launched (accessibility trusted: \(Permissions.isAccessibilityTrusted))")
        switcher = SwitcherController()
        setupStatusItem()
        wireInterceptor()
        startInterceptorWhenReady()
    }

    // MARK: - Event tap

    private func wireInterceptor() {
        interceptor.onKeyDown = { [weak self] keyCode, flags in
            self?.switcher.handleKeyDown(keyCode: keyCode, flags: flags) ?? false
        }
        interceptor.onFlagsChanged = { [weak self] flags in
            self?.switcher.handleFlagsChanged(flags: flags)
        }
    }

    /// The event tap can only be created once Accessibility is granted. We don't
    /// trust `AXIsProcessTrusted()` (stale in a running process); instead we poll
    /// by attempting to create the tap — success is the definitive signal, and no
    /// relaunch is needed after the user flips the toggle.
    private func startInterceptorWhenReady() {
        if interceptor.start() {
            Log.info("event tap active — Command+Tab is intercepted")
            requestScreenRecordingIfNeeded()
            return
        }

        Log.info("event tap not permitted yet — prompting for Accessibility")
        Permissions.promptForAccessibility()

        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if self.interceptor.start() {
                    timer.invalidate()
                    self.trustTimer = nil
                    Log.info("event tap active after permission grant")
                    self.requestScreenRecordingIfNeeded()
                }
            }
        }
    }

    /// Window previews need Screen Recording. Prompt once (the system only shows
    /// the dialog the first time); until granted, the switcher shows app icons.
    private func requestScreenRecordingIfNeeded() {
        if ScreenRecording.isGranted {
            Log.info("screen recording granted — window previews enabled")
        } else {
            Log.info("requesting Screen Recording for window previews")
            ScreenRecording.request()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            if let icon = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Tab") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "⇥"  // fallback so the item is never zero-width/invisible
            }
        }
        Log.info("status item created (button: \(statusItem.button != nil), visible: \(statusItem.isVisible))")

        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Tab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
