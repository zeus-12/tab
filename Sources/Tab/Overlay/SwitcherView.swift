import SwiftUI

/// One entry in the switcher. A reference type so an async-loaded thumbnail can
/// update just its own card instead of rebuilding the whole row.
@MainActor
final class SwitchEntry: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let appName: String
    let icon: NSImage?
    let isMinimized: Bool
    @Published var thumbnail: NSImage?

    init(title: String, appName: String, icon: NSImage?, isMinimized: Bool) {
        self.title = title
        self.appName = appName
        self.icon = icon
        self.isMinimized = isMinimized
    }
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var entries: [SwitchEntry] = []
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
                            SwitchCard(entry: entry, selected: index == model.selectedIndex)
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
}

private struct SwitchCard: View {
    @ObservedObject var entry: SwitchEntry
    let selected: Bool

    private let thumbWidth: CGFloat = 160
    private let thumbHeight: CGFloat = 100

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let thumbnail = entry.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: thumbWidth, maxHeight: thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    // Fallback: app icon centered in the same footprint.
                    placeholderIcon
                        .frame(width: thumbWidth, height: thumbHeight)
                }

                if entry.isMinimized {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                        .offset(x: thumbWidth / 2 - 12, y: thumbHeight / 2 - 12)
                }
            }
            .frame(width: thumbWidth, height: thumbHeight)

            HStack(spacing: 5) {
                if let icon = entry.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(entry.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: thumbWidth)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
    }

    @ViewBuilder
    private var placeholderIcon: some View {
        if let icon = entry.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.25))
        }
    }
}
