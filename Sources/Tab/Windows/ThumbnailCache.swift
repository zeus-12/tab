import AppKit
import CoreGraphics

/// Remembers the last captured preview per window so repeat switches render
/// instantly instead of waiting on a fresh capture. Images are refreshed in the
/// background on every show, and pruned to windows that still exist.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [CGWindowID: NSImage] = [:]

    func image(for id: CGWindowID) -> NSImage? { images[id] }

    func store(_ image: NSImage, for id: CGWindowID) { images[id] = image }

    /// Drop cached images for windows that no longer exist.
    func retain(only liveIDs: Set<CGWindowID>) {
        images = images.filter { liveIDs.contains($0.key) }
    }
}
