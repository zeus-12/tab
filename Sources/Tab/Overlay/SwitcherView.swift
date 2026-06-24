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
    @Published var columns = 1

    var onHover: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var suppressScroll = false
}

/// Layout metrics shared between the view (which draws the grid) and the
/// controller (which sizes the panel to fit it). The switcher wraps into a grid:
/// at most `maxColumns` per row, at most `maxVisibleRows` rows visible, and
/// scrolls vertically beyond that so no window is ever hidden.
enum SwitcherLayout {
    static let cardWidth: CGFloat = 160
    static let thumbHeight: CGFloat = 100
    static let cardInset: CGFloat = 10
    static let cardSpacing: CGFloat = 10
    static let outerPadding: CGFloat = 20
    static let titleAreaHeight: CGFloat = 40
    static let vstackSpacing: CGFloat = 14
    static let maxColumns = 6
    static let maxVisibleRows = 3

    static var cardFootprintWidth: CGFloat { cardWidth + cardInset * 2 }
    static var cardFootprintHeight: CGFloat { thumbHeight + 6 + 18 + cardInset * 2 }

    struct Metrics {
        let columns: Int
        let width: CGFloat
        let height: CGFloat
    }

    static func metrics(count: Int, maxWidth: CGFloat) -> Metrics {
        let fit = Int((maxWidth - outerPadding * 2 + cardSpacing) / (cardFootprintWidth + cardSpacing))
        let columns = max(1, min(min(count, maxColumns), max(1, fit)))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let visibleRows = min(rows, maxVisibleRows)

        let width = outerPadding * 2
            + CGFloat(columns) * cardFootprintWidth
            + CGFloat(columns - 1) * cardSpacing
        let gridHeight = CGFloat(visibleRows) * cardFootprintHeight
            + CGFloat(visibleRows - 1) * cardSpacing
        let height = outerPadding + gridHeight + vstackSpacing + titleAreaHeight
        return Metrics(columns: columns, width: width, height: height)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(SwitcherLayout.cardFootprintWidth), spacing: SwitcherLayout.cardSpacing),
            count: max(1, model.columns)
        )
    }

    var body: some View {
        VStack(spacing: SwitcherLayout.vstackSpacing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: SwitcherLayout.cardSpacing) {
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            SwitchCard(
                                model: model,
                                index: index,
                                entry: entry,
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
    @ObservedObject var model: SwitcherModel
    let index: Int
    @ObservedObject var entry: SwitchEntry
    let onHover: () -> Void
    let onSelect: () -> Void

    private var selected: Bool { index == model.selectedIndex }
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

/// Reports hover and click for a card via a plain AppKit view, because SwiftUI
/// `.onHover`/`.onTapGesture` are unreliable when the hosting window is never key.
/// Hover is driven by `mouseMoved` (not `mouseEntered`) so the cursor merely being
/// inside a card when the panel appears doesn't hijack the selection.
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
