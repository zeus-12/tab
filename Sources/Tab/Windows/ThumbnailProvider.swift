import AppKit
import ScreenCaptureKit

/// Captures live previews of windows with ScreenCaptureKit. Requires Screen
/// Recording permission; until it's granted (or for windows that can't be
/// captured) every call returns nil and the UI falls back to the app icon.
enum ThumbnailProvider {
    /// Snapshots of all shareable windows keyed by CGWindowID. Fetching the
    /// shareable content list is the expensive part, so we do it once per switch
    /// session and capture individual windows from the result.
    static func shareableWindows() async -> [CGWindowID: SCWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else {
            return [:]
        }
        return Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func capture(_ window: SCWindow) async -> NSImage? {
        let config = SCStreamConfiguration()
        // Cap the captured size — thumbnails don't need full Retina resolution.
        let maxWidth: CGFloat = 640
        let scale = window.frame.width > maxWidth ? maxWidth / window.frame.width : 1
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: window.frame.size)
    }
}
