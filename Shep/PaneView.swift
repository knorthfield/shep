import SwiftUI

/// Shows a pane of a tab: one terminal, or panes side by side or one above the other.
struct PaneView: View {
    private static let dividerWidth: CGFloat = 1

    let model: AppModel
    let pane: LayoutDocument.Pane

    var body: some View {
        switch pane {
        case .terminal(_, let address):
            if let session = model.session(for: address) {
                TerminalPane(session: session)
                    .id(address)
            }
        case .unsupported:
            ContentUnavailableView(
                "Herdr Block",
                systemImage: "puzzlepiece",
                description: Text("Shep cannot show this block. It stays in the layout for Herdr.")
            )
        case .split(_, let axis, let children, let weights):
            GeometryReader { geometry in
                let length = axis == .row ? geometry.size.width : geometry.size.height
                let lengthForPanes = length - Self.dividerWidth * CGFloat(children.count - 1)
                let totalWeight = weights.reduce(0, +)
                let stack = axis == .row ? AnyLayout(HStackLayout(spacing: Self.dividerWidth)) : AnyLayout(VStackLayout(spacing: Self.dividerWidth))
                stack {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        let share = lengthForPanes * weights[index] / max(totalWeight, .leastNonzeroMagnitude)
                        PaneView(model: model, pane: child)
                            .frame(width: axis == .row ? share : nil, height: axis == .column ? share : nil)
                    }
                }
            }
            .background(.separator)
        }
    }
}
