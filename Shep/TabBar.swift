import SwiftUI

/// The tabs of the active space.
struct TabBar: View {
    let model: AppModel
    let space: LayoutDocument.Space
    @State private var tabToRename: LayoutDocument.Tab?
    @State private var newName = ""

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
            Text(model.displayName(of: tab, in: space))
                .lineLimit(1)
                .frame(maxWidth: 180)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .contextMenu {
            Button("Rename…") {
                newName = tab.name
                tabToRename = tab
            }
            Button("Close Tab", role: .destructive) { model.close(tab, in: space) }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding { tabToRename != nil } set: { if !$0 { tabToRename = nil } }
    }
}
