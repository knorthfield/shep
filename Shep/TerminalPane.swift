import SwiftUI

/// Shows the view of one terminal session.
struct TerminalPane: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalContainerView { TerminalContainerView() }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.show(session.view)
    }
}

/// Holds the view of a terminal session. The session keeps its view when SwiftUI makes the panes again,
/// thus SwiftUI owns this container and not the terminal view.
final class TerminalContainerView: NSView {
    func show(_ terminalView: TerminalView) {
        guard terminalView.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        // This moves the view out of the container that had it before.
        addSubview(terminalView)
        terminalView.frame = bounds
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // Not an autoresizing mask: that cannot make a view larger again after its container had no size.
        subviews.first?.frame = bounds
    }
}
