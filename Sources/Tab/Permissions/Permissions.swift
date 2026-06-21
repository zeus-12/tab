import AppKit
import ApplicationServices

/// Accessibility is mandatory (enumerate + raise windows). Screen Recording is
/// only needed later for live thumbnails.
enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system prompt and adds the app to the Accessibility list in
    /// System Settings. The user must toggle it on there; the change is picked up
    /// on next enumeration.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
