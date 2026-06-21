import SwiftUI

/// Observable state the SwiftUI overlay renders. The controller owns one instance
/// and mutates it; the view reacts.
@MainActor
final class SwitcherModel: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let title: String
        let appName: String
        let icon: NSImage?
        let isMinimized: Bool
    }

    @Published var entries: [Entry] = []
    @Published var selectedIndex = 0
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        VStack(spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            card(entry, selected: index == model.selectedIndex)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .onChange(of: model.selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            Text(selectedTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var selectedTitle: String {
        guard model.entries.indices.contains(model.selectedIndex) else { return "" }
        return model.entries[model.selectedIndex].title
    }

    @ViewBuilder
    private func card(_ entry: SwitcherModel.Entry, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if let icon = entry.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.gray.opacity(0.3))
                        .frame(width: 72, height: 72)
                }
                if entry.isMinimized {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                        .offset(x: 28, y: 28)
                }
            }
            Text(entry.appName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
    }
}
