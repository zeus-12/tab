import SwiftUI
import AppKit

/// Editor for the app-exclusion list. Excluded apps never appear in the switcher
/// (useful for special-casing apps like Parallels). Writes straight to `Preferences`.
struct ExclusionsSettingsPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var runningApps: [AppItem] = []

    struct AppItem: Identifiable, Hashable {
        let id: String   // bundle identifier
        let name: String
    }

    var body: some View {
        Form {
            Section {
                Text("Excluded apps never appear in the switcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded") {
                if prefs.excludedBundleIDs.isEmpty {
                    Text("No apps excluded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(excludedItems) { item in
                        row(item, actionTitle: "Remove") {
                            prefs.excludedBundleIDs.remove(item.id)
                        }
                    }
                }
            }

            Section("Running Apps") {
                let candidates = runningApps.filter { !prefs.excludedBundleIDs.contains($0.id) }
                if candidates.isEmpty {
                    Text("No other apps running.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { item in
                        row(item, actionTitle: "Exclude") {
                            prefs.excludedBundleIDs.insert(item.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .toolbar {
            ToolbarItem {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh running apps")
            }
        }
        .onAppear(perform: refresh)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ item: AppItem, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            icon(for: item.id)
                .resizable()
                .frame(width: 18, height: 18)
            Text(item.name)
            Spacer()
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
    }

    private func icon(for bundleID: String) -> Image {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let nsImage = app.icon {
            return Image(nsImage: nsImage)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app.dashed")
    }

    // MARK: - Data

    /// Excluded entries, resolving a friendly name from the running app or the
    /// installed bundle, falling back to the raw bundle id.
    private var excludedItems: [AppItem] {
        prefs.excludedBundleIDs.sorted().map { id in
            AppItem(id: id, name: displayName(for: id) ?? id)
        }
    }

    private func displayName(for bundleID: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return nil
    }

    private func refresh() {
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppItem? in
                guard let id = app.bundleIdentifier else { return nil }
                return AppItem(id: id, name: app.localizedName ?? id)
            }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
