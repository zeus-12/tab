import SwiftUI

/// Create and configure any number of workflows, each with its own shortcut and
/// filters. The single global "include minimized" toggle now lives per-workflow.
struct WorkflowsSettingsPane: View {
    @ObservedObject private var store = WorkflowStore.shared

    var body: some View {
        Form {
            Section {
                Text("Each workflow has its own shortcut and filters. Hold the trigger to cycle, release to switch; add ⇧ to reverse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    store.add()
                } label: {
                    Label("Add Workflow", systemImage: "plus")
                }
            }

            ForEach($store.workflows) { $workflow in
                Section(workflow.name.isEmpty ? "Untitled" : workflow.name) {
                    TextField("Name", text: $workflow.name)

                    LabeledContent("Shortcut") {
                        ShortcutRecorderView(shortcut: $workflow.shortcut)
                    }
                    if duplicateShortcut(workflow) {
                        Text("This shortcut is also used by another workflow.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Toggle(isOn: $workflow.includeMinimized) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show minimized windows")
                            Text("Include windows minimized to the Dock.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Picker("Windows from", selection: $workflow.spaceScope) {
                        ForEach(SpaceScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }

                    Toggle("Enabled", isOn: $workflow.enabled)
                        .toggleStyle(.switch)

                    Button(role: .destructive) {
                        store.delete(id: workflow.id)
                    } label: {
                        Label("Delete Workflow", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private func duplicateShortcut(_ workflow: Workflow) -> Bool {
        guard !workflow.shortcut.isUnset else { return false }
        return store.workflows.contains {
            $0.id != workflow.id && !$0.shortcut.isUnset && $0.shortcut == workflow.shortcut
        }
    }
}
