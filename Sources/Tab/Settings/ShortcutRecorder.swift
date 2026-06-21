import SwiftUI

/// Bridges the global event tap into the settings UI while recording a shortcut.
/// Because our tap intercepts keys system-wide, we can't rely on a normal in-window
/// key handler — instead the tap forwards keys here while `isRecording` is true.
@MainActor
enum ShortcutCapture {
    private(set) static var isRecording = false
    private static var onCapture: ((Int, Modifiers) -> Void)?
    private static var onCancel: (() -> Void)?

    static func begin(capture: @escaping (Int, Modifiers) -> Void, cancel: @escaping () -> Void) {
        onCapture = capture
        onCancel = cancel
        isRecording = true
    }

    static func end() {
        isRecording = false
        onCapture = nil
        onCancel = nil
    }

    /// Called by the switcher controller from the tap. Returns true (always
    /// consume while recording). Escape cancels; a key with ≥1 non-shift modifier
    /// is captured.
    static func handle(keyCode: Int, modifiers: Modifiers) {
        if keyCode == 53 { // escape
            onCancel?()
            return
        }
        let trigger = modifiers.subtracting(.shift)
        if !trigger.isEmpty {
            onCapture?(keyCode, trigger)
        }
    }
}

struct ShortcutRecorderView: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .frame(minWidth: 130)
                .monospacedDigit()
        }
        .buttonStyle(.bordered)
        .onDisappear {
            if recording { stop() }
        }
    }

    private var label: String {
        if recording { return "Press shortcut…" }
        return shortcut.isUnset ? "Click to record" : shortcut.display
    }

    private func toggle() {
        if recording {
            stop()
        } else {
            recording = true
            ShortcutCapture.begin(
                capture: { keyCode, modifiers in
                    shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
                    stop()
                },
                cancel: { stop() }
            )
        }
    }

    private func stop() {
        recording = false
        ShortcutCapture.end()
    }
}
