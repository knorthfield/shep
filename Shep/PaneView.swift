import SwiftUI

/// Shows a pane of a tab: one terminal, or panes side by side or one above the other.
struct PaneView: View {
    private static let dividerWidth: CGFloat = 1

    let model: AppModel
    let pane: LayoutDocument.Pane

    var body: some View {
        switch pane {
        case .terminal(let paneID, let address):
            if let session = model.session(for: address) {
                VStack(spacing: 0) {
                    header(of: model.terminals.terminals[address])
                    Divider()
                    TerminalPane(session: session)
                        .id(address)
                }
                .overlay {
                    // With one pane, the focus has no other place to be.
                    if paneID == model.focusedPaneID, (model.activeTab?.terminals.count ?? 0) > 1, model.zoomedPane == nil {
                        Rectangle()
                            .strokeBorder(Color.accentColor, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
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

    /// The program in the terminal and its folder.
    private func header(of terminal: TerminalRecord?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: terminal?.statusWord != nil ? "sparkle" : "terminal")
                .foregroundStyle(terminal?.statusWord != nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            Text(terminal?.programName ?? "")
                .fontWeight(.medium)
            Text(terminal?.workingFolder ?? "")
                .foregroundStyle(.secondary)
                .truncationMode(.head)
            Spacer()
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.background)
    }
}
