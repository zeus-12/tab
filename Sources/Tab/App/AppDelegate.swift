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
            rebuildMenu(active: true)
            return
        }

        Log.info("event tap not permitted yet — prompting for Accessibility")
        Permissions.promptForAccessibility()
        rebuildMenu(active: false)

        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if self.interceptor.start() {
                    timer.invalidate()
                    self.trustTimer = nil
                    Log.info("event tap active after permission grant")
                    self.rebuildMenu(active: true)
                }
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Tab")
            icon?.isTemplate = true
            button.image = icon
        }
        rebuildMenu(active: false)
    }

    private func rebuildMenu(active: Bool) {
        let menu = NSMenu()

        let status = NSMenuItem(
            title: active ? "Command+Tab — active" : "Waiting for Accessibility permission…",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if !active {
            let perm = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
            perm.target = self
            menu.addItem(perm)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Tab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
