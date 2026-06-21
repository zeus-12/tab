import AppKit

/// Tab runs as a menu-bar-only agent (`.accessory`, no Dock icon). When a real
/// window like Settings opens, the app must temporarily become `.regular` so the
/// window can take focus and show in the Dock; it reverts when the last such
/// window closes. Reference-counted to handle multiple windows.
@MainActor
enum AppActivationPolicy {
    private static var count = 0

    static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
