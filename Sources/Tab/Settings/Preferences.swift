import Foundation

/// The single source of truth for user settings. Observable so SwiftUI settings
/// panes bind to it directly, and read synchronously by the enumerator. Every
/// property is persisted to `UserDefaults` on change.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let excluded = "excludedBundleIDs"
    }

    /// Apps known to misbehave in switchers (virtual machines that publish
    /// phantom windows, etc.). Seeds the list on first run.
    static let defaultExclusions: [String] = [
        "com.parallels.desktop.console",
        "com.vmware.fusion",
    ]

    @Published var excludedBundleIDs: Set<String> {
        didSet { defaults.set(Array(excludedBundleIDs).sorted(), forKey: Key.excluded) }
    }

    private init() {
        if let stored = defaults.stringArray(forKey: Key.excluded) {
            excludedBundleIDs = Set(stored)
        } else {
            excludedBundleIDs = Set(Self.defaultExclusions)
        }
    }
}
