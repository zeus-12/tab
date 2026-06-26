import Foundation

/// Persists the user's workflows (JSON in UserDefaults) and is observed by both
/// the switcher engine and the settings UI. Seeds a single default workflow that
/// reproduces the original ⌘Tab behavior on first run.
@MainActor
final class WorkflowStore: ObservableObject {
    static let shared = WorkflowStore()

    @Published var workflows: [Workflow] {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let key = "workflows.v1"

    private init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Workflow].self, from: data) {
            workflows = decoded
        } else {
            workflows = [.defaultAllWindows]
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(workflows) else { return }
        defaults.set(data, forKey: key)
    }

    func add() {
        workflows.append(
            Workflow(
                name: "New Workflow",
                shortcut: Shortcut(keyCode: 48, modifiers: []),
                includeMinimized: true,
                includeHidden: true,
                spaceScope: .allSpaces,
                enabled: true
            )
        )
    }

    func delete(id: UUID) {
        workflows.removeAll { $0.id == id }
    }

    /// Finds the enabled workflow whose trigger exactly matches the given key and
    /// (non-shift) modifiers. Returns nil if none — letting the key pass through.
    func match(keyCode: Int, modifiers: Modifiers) -> Workflow? {
        let nonShift = modifiers.subtracting(.shift)
        return workflows.first { wf in
            wf.enabled && !wf.shortcut.isUnset
                && wf.shortcut.keyCode == keyCode
                && wf.shortcut.modifiers == nonShift
        }
    }
}
