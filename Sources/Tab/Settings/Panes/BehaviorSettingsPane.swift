import SwiftUI

struct BehaviorSettingsPane: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Windows") {
                Toggle(isOn: $prefs.includeMinimizedWindows) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include minimized windows")
                        Text("Show windows currently minimized to the Dock. Selecting one un-minimizes it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
