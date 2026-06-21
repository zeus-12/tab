import SwiftUI
import AppKit

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

    /// Mouse callbacks, wired by the controller.
    var onHover: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?

    /// Set when a selection change came from hovering, so we don't auto-scroll a
    /// card out from under the cursor (only keyboard navigation scrolls).
    var suppressScroll = false
}

/// Layout metrics shared between the view (which draws the cards) and the
/// controller (which sizes the panel to fit the cards exactly).
enum SwitcherLayout {
    static let cardWidth: CGFloat = 160
    static let thumbHeight: CGFloat = 100
    static let cardInset: CGFloat = 10
    static let cardSpacing: CGFloat = 10
    static let outerPadding: CGFloat = 20
    static let panelHeight: CGFloat = 220

    /// The panel width needed to show `count` cards, capped at `maxWidth`.
    static func panelWidth(count: Int, maxWidth: CGFloat) -> CGFloat {
        let footprint = cardWidth + cardInset * 2
        let total = CGFloat(count) * footprint
            + CGFloat(max(0, count - 1)) * cardSpacing
            + outerPadding * 2
        return min(total, maxWidth)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        VStack(spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SwitcherLayout.cardSpacing) {
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            SwitchCard(
                                entry: entry,
                                selected: index == model.selectedIndex,
                                onHover: { model.onHover?(index) },
                                onSelect: { model.onSelect?(index) }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, SwitcherLayout.outerPadding)
                    .padding(.top, SwitcherLayout.outerPadding)
                }
                .onChange(of: model.selectedIndex) { _, newValue in
                    if model.suppressScroll {
                        model.suppressScroll = false
                        return
                    }
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
    let onHover: () -> Void
    let onSelect: () -> Void

    private let thumbWidth = SwitcherLayout.cardWidth
    private let thumbHeight = SwitcherLayout.thumbHeight

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
        .padding(SwitcherLayout.cardInset)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .overlay(CardMouseView(onHover: onHover, onClick: onSelect))
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

// MARK: - Mouse tracking (works in a non-activating panel)

/// Reports hover and click for a card. A plain AppKit view is used (rather than
/// SwiftUI `.onHover`/`.onTapGesture`) because those are unreliable when the
/// hosting window is never key: `.activeAlways` tracking makes hover fire without
/// focus, and `acceptsFirstMouse` makes the first click register without
/// activating the app.
///
/// Hover is driven by `mouseMoved`, NOT `mouseEntered`, so the cursor merely
/// being inside a card when the panel appears doesn't hijack the selection —
/// only actual movement does.
private struct CardMouseView: NSViewRepresentable {
    let onHover: () -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> CardTrackingView {
        let view = CardTrackingView()
        view.onHover = onHover
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: CardTrackingView, context: Context) {
        nsView.onHover = onHover
        nsView.onClick = onClick
    }
}

final class CardTrackingView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
