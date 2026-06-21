import AppKit
import SwiftUI

// MARK: - Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case workflows
    case exclusions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .workflows: "Workflows"
        case .exclusions: "Exclusions"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .workflows: "square.stack.3d.up"
        case .exclusions: "nosign"
        case .about: "info.circle"
        }
    }
}

// MARK: - Navigation state (singleton so external callers can jump to a tab)

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab? = .general
    private init() {}
}

private enum AppVersion {
    static let displayString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }()
}

// MARK: - Root

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared
    @State private var history: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    private var activeTab: SettingsTab { navigation.selectedTab ?? .general }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebarView(selectedTab: $navigation.selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(tab: activeTab)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                Button { goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
            }
        }
        .onChange(of: navigation.selectedTab) { _, _ in recordNavigation() }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < history.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = history[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = history[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation, let tab = navigation.selectedTab else { return }
        if history.last == tab { return }
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        history.append(tab)
        historyIndex = history.count - 1
    }
}

// MARK: - Sidebar

private struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab?

    var body: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            Text(AppVersion.displayString)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fontDesign(.monospaced)
                .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }
}

// MARK: - Detail routing

private struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralSettingsPane()
            case .workflows: WorkflowsSettingsPane()
            case .exclusions: ExclusionsSettingsPane()
            case .about: AboutSettingsPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
