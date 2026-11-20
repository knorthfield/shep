import SwiftUI

/// The tabs of the active space.
struct TabBar: View {
    let model: AppModel
    let space: LayoutDocument.Space
    @State private var tabToRename: LayoutDocument.Tab?
    @State private var newName = ""
    @State private var hoveredTabID: String?

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(space.tabs) { tab in
                        tabButton(tab)
                    }
                }
            }
            Button("New Tab", systemImage: "plus") { model.newTab() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // The panes below take all the height that they can get: the tab bar keeps its own height.
        .fixedSize(horizontal: false, vertical: true)
        .alert("Rename Tab", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let tabToRename { model.rename(tabToRename, in: space, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A tab without a name shows the name of its first terminal.")
        }
    }

    private func tabButton(_ tab: LayoutDocument.Tab) -> some View {
        let isActive = tab.id == model.activeTab?.id
        return Button {
            model.select(tab, in: space)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isAgent(tab) ? "sparkle" : "terminal")
                    .font(.caption)
                    .foregroundStyle(isAgent(tab) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Text(model.displayName(of: tab, in: space))
                    .lineLimit(1)
                    .frame(maxWidth: 180)
                // The button keeps its place when it does not show, so that the tab keeps its width.
                Button("Close Tab", systemImage: "xmark") { model.close(tab, in: space) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.bold))
                    .opacity(hoveredTabID == tab.id ? 1 : 0)
            }
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(isActive ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isInside in
            if isInside { hoveredTabID = tab.id } else if hoveredTabID == tab.id { hoveredTabID = nil }
        }
        .contextMenu {
            Button("Rename…") {
                newName = tab.name
                tabToRename = tab
            }
            Button("Close Tab", role: .destructive) { model.close(tab, in: space) }
        }
    }

    /// True if a program in the tab reports a status.
    private func isAgent(_ tab: LayoutDocument.Tab) -> Bool {
        tab.terminals.contains { model.terminals.terminals[$0]?.statusWord != nil }
    }

    private var isRenaming: Binding<Bool> {
        Binding { tabToRename != nil } set: { if !$0 { tabToRename = nil } }
    }
}
