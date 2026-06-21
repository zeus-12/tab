import AppKit

// Tab — a fast Alt-Tab-style window switcher for macOS.
//
// Built as a plain NSApplication (not the SwiftUI App lifecycle) because we need
// an agent app (.accessory: no Dock icon) with fine control over a non-activating
// overlay panel and global hotkeys — none of which the SwiftUI `App` scene model
// exposes cleanly when built outside Xcode.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // `delegate` is held alive for the process lifetime by this scope while
    // `run()` blocks (NSApplication.delegate is a weak reference).
    app.run()
}
