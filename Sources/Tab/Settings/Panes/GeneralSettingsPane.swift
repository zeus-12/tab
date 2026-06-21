import SwiftUI

struct GeneralSettingsPane: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: launchBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Tab at login")
                        Text("Start automatically when you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Shortcuts") {
                LabeledContent("Switch windows", value: "⌘ Tab")
                LabeledContent("Reverse direction", value: "⌘ ⇧ Tab")
                LabeledContent("Cancel", value: "esc")
                Text("While Tab is running it replaces the built-in macOS app switcher. Quit Tab from the menu bar to restore it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    /// Drives the toggle from the *real* SMAppService status: after attempting to
    /// change it, we read back the actual state rather than assume success.
    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                if let error = LoginItem.setEnabled(newValue) {
                    loginError = error.localizedDescription
                } else {
                    loginError = nil
                }
                launchAtLogin = LoginItem.isEnabled
            }
        )
    }
}
