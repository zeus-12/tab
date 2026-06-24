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
        // Float above the menu bar and another app's full-screen window so the
        // overlay is visible wherever you are, not just on a normal desktop.
        level = .popUpMenu
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = false
        // Appear on whichever Space / full-screen app is active when summoned —
        // not only the Space the panel was created on. `.canJoinAllSpaces` moves
        // it to the active Space; `.fullScreenAuxiliary` lets it sit over a
        // full-screen window. Crucially NOT `.stationary`: that pins a window to
        // its origin Space, which was the bug — the overlay only showed on the
        // Space Tab launched on while the switch itself still worked everywhere.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
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
