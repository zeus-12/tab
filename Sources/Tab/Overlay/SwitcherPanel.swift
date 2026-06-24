import AppKit

/// A non-activating floating panel that hosts the switcher UI. Because it never
/// becomes key/main, the app you're switching *from* stays frontmost until you
/// commit — which is what makes "raise the chosen window" behave correctly.
final class SwitcherPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        acceptsMouseMovedEvents = true   // so card hover tracking fires
        level = .modalPanel
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        content.frame = contentView?.bounds ?? .zero
        content.autoresizingMask = [.width, .height]
        contentView?.addSubview(content)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Centers on the given screen at the given content size and shows without
    /// stealing focus.
    func present(on screen: NSScreen, width: CGFloat, height: CGFloat) {
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}
