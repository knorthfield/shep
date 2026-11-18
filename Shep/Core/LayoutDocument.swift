import Foundation

/// The layout of one machine: its spaces, tabs and panes. Herdr and Shep share it as the core document `herdr-app`.
///
/// The JSON is the source of truth. Shep reads a simple view of it and changes it in place,
/// so that the fields that Herdr writes and Shep does not know stay as they are.
struct LayoutDocument: Equatable {
    static let name = "herdr-app"

    enum Axis: String {
        /// Panes side by side.
        case row
        /// Panes one above the other.
        case column
    }

    struct Space: Identifiable, Equatable {
        var id: String
        var name: String
        var folder: String
        var machine: String?
        var tabs: [Tab]
    }

    struct Tab: Identifiable, Equatable {
        var id: String
        var name: String
        var root: Pane

        /// The addresses of the terminals in this tab, in the order of the panes.
        var terminals: [String] { root.terminals }
    }

    indirect enum Pane: Identifiable, Equatable {
        /// Panes along an axis. Each pane has a weight: its part of the space.
        case split(id: String, axis: Axis, children: [Pane], weights: [Double])
        case terminal(id: String, address: String)
        /// A block that Herdr can show and Shep cannot, for example a mod.
        case unsupported(id: String)

        var id: String {
            switch self {
            case .split(let id, _, _, _), .terminal(let id, _), .unsupported(let id): id
            }
        }

        var terminals: [String] {
            switch self {
            case .split(_, _, let children, _): children.flatMap(\.terminals)
            case .terminal(_, let address): [address]
            case .unsupported: []
            }
        }

        /// The ids of the terminal panes, in order.
        var terminalPaneIDs: [String] {
            switch self {
            case .split(_, _, let children, _): children.flatMap(\.terminalPaneIDs)
            case .terminal(let id, _): [id]
            case .unsupported: []
            }
        }

        func address(ofPane paneID: String) -> String? {
            switch self {
            case .split(_, _, let children, _): children.lazy.compactMap { $0.address(ofPane: paneID) }.first
            case .terminal(let id, let address): id == paneID ? address : nil
            case .unsupported: nil
            }
        }
    }

    /// The document as the core has it. The ids in it are local to the machine.
    private(set) var value: JSONValue
    /// The machine that owns the document. Nil: the machine of the local core.
    let machine: String?

    init(value: JSONValue, machine: String? = nil) {
        // A document that was never written is null.
        self.value = value.object == nil ? ["spaces": []] : value
        if self.value["spaces"].array == nil { self.value["spaces"] = [] }
        self.machine = machine
    }

    /// A new id as Herdr makes it: a prefix and 32 hexadecimal digits.
    static func newID(_ prefix: String) -> String {
        prefix + String(format: "%016llx%016llx", UInt64.random(in: .min ... .max), UInt64.random(in: .min ... .max))
    }

    // MARK: Read

    /// The spaces, with ids and terminal addresses that include the machine (`box/t7`).
    var spaces: [Space] {
        spaceValues.map { space in
            Space(
                id: qualified(space["id"].string ?? ""),
                name: space["name"].string ?? "",
                folder: space["folder"].string ?? "",
                machine: machine,
                tabs: (space["tabs"].array ?? []).map { tab in
                    Tab(id: qualified(tab["id"].string ?? ""), name: tab["name"].string ?? "", root: pane(from: tab["root"]))
                }
            )
        }
    }

    private func pane(from node: JSONValue) -> Pane {
        let id = qualified(node["id"].string ?? "")
        switch node["type"].string {
        case "row", "column":
            let visible = (node["children"].array ?? []).filter { $0["hidden"].bool != true }
            return .split(
                id: id,
                axis: node["type"].string == "row" ? .row : .column,
                children: visible.map(pane(from:)),
                weights: visible.map { Self.weight(of: $0) ?? 1 }
            )
        case "stack":
            // A stack shows one child: the active one, or the first.
            let visible = (node["children"].array ?? []).filter { $0["hidden"].bool != true }
            let active = visible.first { $0["id"] == node["active"] } ?? visible.first
            return active.map(pane(from:)) ?? .unsupported(id: id)
        default:
            if let terminal = node["content"]["terminal"].string { return .terminal(id: id, address: qualified(terminal)) }
            return .unsupported(id: id)
        }
    }

    // MARK: Change

    /// Adds a space with one tab that has one terminal pane.
    mutating func addSpace(id: String, name: String, folder: String, tabID: String, paneID: String, terminal: String) {
        let space: JSONValue = [
            "id": .string(local(id)), "name": .string(name), "folder": .string(folder),
            "tabs": [Self.tab(id: local(tabID), paneID: local(paneID), terminal: local(terminal))],
        ]
        spaceValues.append(space)
    }

    /// Adds a tab with one terminal pane, after a tab of the space or at the end.
    mutating func addTab(id: String, toSpace spaceID: String, after tabID: String?, paneID: String, terminal: String) {
        let previous = tabID.map(local)
        let tab = Self.tab(id: local(id), paneID: local(paneID), terminal: local(terminal))
        changeSpace(spaceID) { space in
            var tabs = space["tabs"].array ?? []
            let index = tabs.firstIndex { $0["id"].string == previous }.map { $0 + 1 } ?? tabs.count
            tabs.insert(tab, at: index)
            space["tabs"] = .array(tabs)
        }
    }

    /// Puts a new terminal pane after a pane, along an axis. The new pane gets half of the space of the old pane.
    /// - Parameter containerID: The id of the new container, used if the old pane is not in a container of this axis.
    mutating func splitPane(_ paneID: String, axis: Axis, newPaneID: String, containerID: String, terminal: String) {
        let new = Self.terminalPane(id: local(newPaneID), terminal: local(terminal))
        let (target, container) = (local(paneID), local(containerID))
        changeTabRoots { root in
            _ = Self.split(&root, target: target, axis: axis, new: new, containerID: container)
        }
    }

    /// Removes a pane. A tab that has no more panes goes, and a space that has no more tabs goes.
    mutating func removePane(_ paneID: String) {
        let target = local(paneID)
        changeTabRoots { root in
            if Self.remove(target, from: &root) { Self.collapse(&root) }
        }
        spaceValues = spaceValues.compactMap { space in
            var space = space
            space["tabs"] = .array((space["tabs"].array ?? []).filter { !Self.terminalBlocks(in: $0["root"]).isEmpty || Self.hasOtherBlocks($0["root"]) })
            return space["tabs"].array?.isEmpty == true ? nil : space
        }
    }

    mutating func removeTab(_ tabID: String) {
        let target = local(tabID)
        spaceValues = spaceValues.compactMap { space in
            var space = space
            space["tabs"] = .array((space["tabs"].array ?? []).filter { $0["id"].string != target })
            return space["tabs"].array?.isEmpty == true ? nil : space
        }
    }

    mutating func removeSpace(_ spaceID: String) {
        let target = local(spaceID)
        spaceValues.removeAll { $0["id"].string == target }
    }

    mutating func renameSpace(_ spaceID: String, to name: String) {
        changeSpace(spaceID) { $0["name"] = .string(name) }
    }

    mutating func renameTab(_ tabID: String, to name: String) {
        let target = local(tabID)
        var spaces = spaceValues
        for spaceIndex in spaces.indices {
            var tabs = spaces[spaceIndex]["tabs"].array ?? []
            guard let index = tabs.firstIndex(where: { $0["id"].string == target }) else { continue }
            tabs[index]["name"] = .string(name)
            spaces[spaceIndex]["tabs"] = .array(tabs)
        }
        spaceValues = spaces
    }

    // MARK: The JSON tree

    private var spaceValues: [JSONValue] {
        get { value["spaces"].array ?? [] }
        set { value["spaces"] = .array(newValue) }
    }

    private mutating func changeSpace(_ spaceID: String, _ change: (inout JSONValue) -> Void) {
        let target = local(spaceID)
        guard let index = spaceValues.firstIndex(where: { $0["id"].string == target }) else { return }
        var spaces = spaceValues
        change(&spaces[index])
        spaceValues = spaces
    }

    private mutating func changeTabRoots(_ change: (inout JSONValue) -> Void) {
        spaceValues = spaceValues.map { space in
            var space = space
            space["tabs"] = .array((space["tabs"].array ?? []).map { tab in
                var tab = tab
                change(&tab["root"])
                return tab
            })
            return space
        }
    }

    private static func tab(id: String, paneID: String, terminal: String) -> JSONValue {
        // The root of a tab is a row that has the id of the tab, as Herdr makes it.
        ["id": .string(id), "name": "", "root": ["id": .string(id), "type": "row", "children": [terminalPane(id: paneID, terminal: terminal)]]]
    }

    private static func terminalPane(id: String, terminal: String) -> JSONValue {
        ["id": .string(id), "type": "block", "content": ["terminal": .string(terminal)]]
    }

    /// The weight of a node in its container. Nil: the node has a size in points, not a weight.
    private static func weight(of node: JSONValue) -> Double? {
        let size = node["size"]
        if size.isNull { return 1 }
        if case .double(let weight) = size["weight"] { return weight }
        if case .int(let weight) = size["weight"] { return Double(weight) }
        return nil
    }

    private static func isContainer(_ node: JSONValue) -> Bool {
        node["type"].string == "row" || node["type"].string == "column"
    }

    /// The rule of Herdr's `Node::split`: use the parent again if it has this axis, if not put the target in a new container.
    private static func split(_ node: inout JSONValue, target: String, axis: Axis, new: JSONValue, containerID: String) -> Bool {
        guard var children = node["children"].array else { return false }
        if let index = children.firstIndex(where: { $0["id"].string == target }) {
            var new = new
            if node["type"].string == axis.rawValue {
                let share = weight(of: children[index]) ?? 1
                if weight(of: children[index]) != nil { children[index]["size"] = ["weight": .double(share / 2)] }
                new["size"] = ["weight": .double(share / 2)]
                children.insert(new, at: index + 1)
            } else {
                var old = children[index]
                let size = old["size"]
                old["size"] = .null
                var container: JSONValue = ["id": .string(containerID), "type": .string(axis.rawValue), "children": [old, new]]
                if !size.isNull { container["size"] = size }
                children[index] = container
            }
            node["children"] = .array(children)
            return true
        }
        for index in children.indices where split(&children[index], target: target, axis: axis, new: new, containerID: containerID) {
            node["children"] = .array(children)
            return true
        }
        return false
    }

    /// The rule of Herdr's `remove_inner`: the space of the removed node goes to the node before it, or to the next one.
    private static func remove(_ id: String, from node: inout JSONValue) -> Bool {
        guard var children = node["children"].array else { return false }
        if let index = children.firstIndex(where: { $0["id"].string == id }) {
            let removed = children.remove(at: index)
            if isContainer(node), let gone = weight(of: removed), !children.isEmpty {
                let neighbour = max(index - 1, 0)
                if let weight = weight(of: children[neighbour]) { children[neighbour]["size"] = ["weight": .double(weight + gone)] }
            }
            if node["type"].string == "stack", node["active"].string == id {
                let next = index < children.count ? children[index] : children.last
                node["active"] = next?["id"] ?? .null
            }
            node["children"] = .array(children)
            return true
        }
        for index in children.indices where remove(id, from: &children[index]) {
            node["children"] = .array(children)
            return true
        }
        return false
    }

    /// The rule of Herdr's `collapse`: an empty row or column goes, and one with one child gives its place to that child.
    /// The children of a stack and the root stay.
    private static func collapse(_ node: inout JSONValue) {
        guard var children = node["children"].array else { return }
        for index in children.indices { collapse(&children[index]) }
        if node["type"].string != "stack" {
            children.removeAll { isContainer($0) && ($0["children"].array ?? []).isEmpty }
            for index in children.indices where isContainer(children[index]) && children[index]["children"].array?.count == 1 {
                var only = children[index]["children"].array![0]
                only["size"] = children[index]["size"]
                children[index] = only
            }
        }
        node["children"] = .array(children)
    }

    private static func terminalBlocks(in node: JSONValue) -> [String] {
        if let terminal = node["content"]["terminal"].string { return [terminal] }
        return (node["children"].array ?? []).flatMap(terminalBlocks(in:))
    }

    /// True if the node has a block that is not a terminal, for example a mod of Herdr.
    private static func hasOtherBlocks(_ node: JSONValue) -> Bool {
        if node["type"].string == "block" { return node["content"]["terminal"].string == nil }
        return (node["children"].array ?? []).contains(where: hasOtherBlocks)
    }

    // MARK: Ids of other machines

    /// An id of this document as Shep uses it: with the machine in front, if the document is of another machine.
    private func qualified(_ id: String) -> String {
        machine.map { "\($0)/\(id)" } ?? id
    }

    /// An id as the document has it: without the machine.
    private func local(_ id: String) -> String {
        Self.localID(id, machine: machine)
    }

    /// An id or a terminal address without the machine in front, as the core of that machine knows it.
    static func localID(_ id: String, machine: String?) -> String {
        guard let machine, id.hasPrefix("\(machine)/") else { return id }
        return String(id.dropFirst(machine.count + 1))
    }
}
