import AppKit
import CoreGraphics

/// Screen Recording permission, required for live window previews. These are
/// public CoreGraphics APIs (no ScreenCaptureKit needed just to ask).
enum ScreenRecording {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompt (only shown once) and adds the app to the
    /// Screen Recording list. Returns the current grant state.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
