import Foundation
import CoreGraphics

/// Keyboard modifiers, normalized so they can be compared regardless of whether
/// they came from an NSEvent (settings recorder) or a CGEvent (the tap). Shift is
/// reserved as the "reverse direction" modifier and is never part of a trigger.
struct Modifiers: OptionSet, Codable, Hashable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let command = Modifiers(rawValue: 1 << 0)
    static let option  = Modifiers(rawValue: 1 << 1)
    static let control = Modifiers(rawValue: 1 << 2)
    static let shift   = Modifiers(rawValue: 1 << 3)

    init(cgFlags: CGEventFlags) {
        var result: Modifiers = []
        if cgFlags.contains(.maskCommand) { result.insert(.command) }
        if cgFlags.contains(.maskAlternate) { result.insert(.option) }
        if cgFlags.contains(.maskControl) { result.insert(.control) }
        if cgFlags.contains(.maskShift) { result.insert(.shift) }
        self = result
    }

    /// Symbols in canonical macOS order: ⌃⌥⇧⌘
    var display: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A trigger: a key plus its (non-shift) modifiers. Empty modifiers means "unset"
/// — such a shortcut never matches, so a freshly-added workflow does nothing until
/// the user records one.
struct Shortcut: Codable, Hashable {
    var keyCode: Int
    var modifiers: Modifiers

    var isUnset: Bool { modifiers.isEmpty }

    var display: String {
        modifiers.display + Shortcut.keyLabel(keyCode)
    }

    static func keyLabel(_ code: Int) -> String {
        if let special = specials[code] { return special }
        if let ansi = ansiKeys[code] { return ansi }
        return "key\(code)"
    }

    private static let specials: [Int: String] = [
        48: "⇥", 49: "Space", 36: "↩", 53: "⎋", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑", 116: "⇞", 121: "⇟", 115: "↖", 119: "↘",
    ]

    private static let ansiKeys: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\",
    ]
}

/// How a workflow treats virtual desktops.
enum SpaceScope: String, Codable, CaseIterable, Identifiable {
    case allSpaces
    case currentSpace
    var id: Self { self }
    var title: String {
        switch self {
        case .allSpaces: "All Spaces"
        case .currentSpace: "Current Space"
        }
    }
}

/// A named switcher mode bound to a shortcut, with its own filters.
struct Workflow: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var shortcut: Shortcut
    var includeMinimized: Bool
    var includeHidden: Bool
    var spaceScope: SpaceScope
    var enabled: Bool

    /// The default migrated from the original hard-coded ⌘Tab behavior.
    static var defaultAllWindows: Workflow {
        Workflow(
            name: "All Windows",
            shortcut: Shortcut(keyCode: 48, modifiers: [.command]),
            includeMinimized: true,
            includeHidden: true,
            spaceScope: .allSpaces,
            enabled: true
        )
    }
}
