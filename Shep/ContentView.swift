import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
        }
        .onChange(of: model.activeTab?.id) {
            // The views of the new tab are in the window after SwiftUI drew it.
            Task { model.focusActivePane() }
            model.markVisibleAgentsSeen()
        }
        .sheet(isPresented: $model.isPaletteVisible) {
            CommandPalette(model: model)
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            model.isSidebarVisible ? .all : .detailOnly
        } set: {
            model.isSidebarVisible = $0 != .detailOnly
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.connectionState {
        case .connecting:
            ProgressView("Connecting to herdr-core…")
        case .hcNotFound:
            ContentUnavailableView {
                Label("herdr-core Is Not Installed", systemImage: "terminal")
            } description: {
                Text("Run this command in Terminal. Shep connects when the installation is complete.")
                Text(HcBinary.installCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        case .failed(let message):
            ContentUnavailableView("No Connection to herdr-core", systemImage: "bolt.horizontal.circle", description: Text(message))
        case .connected:
            if let space = model.activeSpace, let tab = model.activeTab {
                VStack(spacing: 0) {
                    TabBar(model: model, space: space)
                    Divider()
                    PaneView(model: model, pane: model.zoomedPane ?? tab.root)
                }
            } else {
                ContentUnavailableView {
                    Label("No Spaces", systemImage: "rectangle.split.2x1")
                } description: {
                    Text("A space has tabs of terminals for one project.")
                } actions: {
                    Button("New Space") { model.newSpace() }
                    Button("New Space in Folder…") { model.newSpaceInFolder() }
                }
            }
        }
    }
}
