import Foundation
import Testing
@testable import Shep

struct LayoutDocumentTests {
    /// The document of this Mac's core, with fields that Shep does not know at each level.
    private let herdrDocument = JSONValue(json: Data(#"""
    {"future": 1, "spaces": [{"id": "sp1", "name": "", "folder": "/src/web", "color": "red", "tabs": [
      {"id": "tb1", "name": "main", "pinned": true, "root": {"id": "tb1", "type": "row", "gap": 4, "children": [
        {"id": "pd1", "type": "block", "content": {"terminal": "t16"}, "title": "agent", "size": {"weight": 0.7}},
        {"id": "pd2", "type": "block", "content": {"terminal": "t17"}, "size": {"weight": 0.3}}
      ]}}
    ]}]}
    """#.utf8))!

    private func terminal(_ id: String, _ address: String) -> LayoutDocument.Pane { .terminal(id: id, address: address) }

    @Test func aDocumentThatWasNeverWrittenHasNoSpaces() {
        #expect(LayoutDocument(value: .null).spaces.isEmpty)
        #expect(LayoutDocument(value: .null).value == ["spaces": []])
    }

    @Test func spacesTabsAndPanesAreRead() {
        let spaces = LayoutDocument(value: herdrDocument).spaces
        #expect(spaces.count == 1)
        #expect(spaces[0].folder == "/src/web")
        #expect(spaces[0].tabs[0].name == "main")
        #expect(spaces[0].tabs[0].root == .split(id: "tb1", axis: .row, children: [terminal("pd1", "t16"), terminal("pd2", "t17")], weights: [0.7, 0.3]))
        #expect(spaces[0].tabs[0].terminals == ["t16", "t17"])
    }

    @Test func idsOfAnotherMachineGetTheMachineInFront() {
        let space = LayoutDocument(value: herdrDocument, machine: "box").spaces[0]
        #expect(space.id == "box/sp1")
        #expect(space.machine == "box")
        #expect(space.tabs[0].id == "box/tb1")
        #expect(space.tabs[0].terminals == ["box/t16", "box/t17"])
        #expect(space.tabs[0].root.address(ofPane: "box/pd2") == "box/t17")
    }

    @Test func aStackShowsItsActiveChildAndOtherBlocksAreNotSupported() throws {
        let document = LayoutDocument(value: ["spaces": [["id": "sp1", "tabs": [["id": "tb1", "root": [
            "id": "tb1", "type": "row", "children": [
                ["id": "st", "type": "stack", "active": "b", "children": [
                    ["id": "a", "type": "block", "content": ["terminal": "t1"]],
                    ["id": "b", "type": "block", "content": ["terminal": "t2"]],
                ]],
                ["id": "m", "type": "block", "content": ["mod": "files"]],
                ["id": "h", "type": "block", "hidden": true, "content": ["terminal": "t3"]],
            ],
        ]]]]]])
        #expect(document.spaces[0].tabs[0].root == .split(id: "tb1", axis: .row, children: [terminal("b", "t2"), .unsupported(id: "m")], weights: [1, 1]))
    }

    @Test func aChangeKeepsTheFieldsThatShepDoesNotKnow() {
        var document = LayoutDocument(value: herdrDocument)
        document.renameSpace("sp1", to: "Web")
        document.renameTab("tb1", to: "agents")
        document.splitPane("pd2", axis: .column, newPaneID: "pd3", containerID: "c1", terminal: "t18")
        let space = document.value["spaces"].array![0]
        #expect(document.value["future"] == 1)
        #expect(space["color"] == "red")
        #expect(space["name"] == "Web")
        #expect(space["tabs"].array![0]["pinned"] == true)
        #expect(space["tabs"].array![0]["name"] == "agents")
        #expect(space["tabs"].array![0]["root"]["gap"] == 4)
        #expect(space["tabs"].array![0]["root"]["children"].array![0]["title"] == "agent")
    }

    @Test func aNewSpaceHasOneTabWithOnePaneAsHerdrMakesIt() {
        var document = LayoutDocument(value: .null)
        document.addSpace(id: "sp9", name: "", folder: "/src", tabID: "tb9", paneID: "pd9", terminal: "t1")
        #expect(document.value == ["spaces": [["id": "sp9", "name": "", "folder": "/src", "tabs": [
            ["id": "tb9", "name": "", "root": ["id": "tb9", "type": "row", "children": [["id": "pd9", "type": "block", "content": ["terminal": "t1"]]]]],
        ]]]])
    }

    @Test func aNewTabGoesAfterTheGivenTabOrAtTheEnd() {
        var document = LayoutDocument(value: herdrDocument)
        document.addTab(id: "tb3", toSpace: "sp1", after: nil, paneID: "p3", terminal: "t3")
        document.addTab(id: "tb2", toSpace: "sp1", after: "tb1", paneID: "p2", terminal: "t2")
        #expect(document.spaces[0].tabs.map(\.id) == ["tb1", "tb2", "tb3"])
    }

    @Test func aChangeOnAnotherMachineWritesLocalIds() {
        var document = LayoutDocument(value: herdrDocument, machine: "box")
        document.addTab(id: "box/tb2", toSpace: "box/sp1", after: "box/tb1", paneID: "box/p2", terminal: "box/t2")
        let tab = document.value["spaces"].array![0]["tabs"].array![1]
        #expect(tab["id"] == "tb2")
        #expect(tab["root"]["children"].array![0]["content"]["terminal"] == "t2")
    }

    // The rules and the cases of Herdr's layout.rs.

    @Test func aSplitUsesAParentOfTheSameAxisAgainAndWrapsThePaneIfNot() {
        var document = LayoutDocument(value: .null)
        document.addSpace(id: "sp", name: "", folder: "", tabID: "tab", paneID: "a", terminal: "t1")
        document.splitPane("a", axis: .row, newPaneID: "b", containerID: "unused", terminal: "t2")
        document.splitPane("b", axis: .row, newPaneID: "c", containerID: "unused", terminal: "t3")
        document.splitPane("c", axis: .column, newPaneID: "d", containerID: "c1", terminal: "t4")
        #expect(document.spaces[0].tabs[0].root == .split(id: "tab", axis: .row, children: [
            terminal("a", "t1"), terminal("b", "t2"),
            .split(id: "c1", axis: .column, children: [terminal("c", "t3"), terminal("d", "t4")], weights: [1, 1]),
        ], weights: [0.5, 0.25, 0.25]))
    }

    @Test func closingASplitGivesItsShareBackToThePaneItCameFrom() {
        var document = LayoutDocument(value: herdrDocument)
        document.splitPane("pd2", axis: .row, newPaneID: "c", containerID: "unused", terminal: "t3")
        document.removePane("c")
        #expect(document.spaces[0].tabs[0].root == .split(id: "tb1", axis: .row, children: [terminal("pd1", "t16"), terminal("pd2", "t17")], weights: [0.7, 0.3]))
        // Closing the first pane gives its share to the next one.
        document.splitPane("pd1", axis: .row, newPaneID: "d", containerID: "unused", terminal: "t4")
        document.removePane("pd1")
        #expect(document.spaces[0].tabs[0].root == .split(id: "tb1", axis: .row, children: [terminal("d", "t4"), terminal("pd2", "t17")], weights: [0.7, 0.3]))
    }

    @Test func aContainerWithOnePaneGivesItsPlaceToThatPaneButTheRootStays() {
        var document = LayoutDocument(value: herdrDocument)
        document.splitPane("pd2", axis: .column, newPaneID: "c", containerID: "c1", terminal: "t3")
        document.removePane("c")
        #expect(document.spaces[0].tabs[0].root == .split(id: "tb1", axis: .row, children: [terminal("pd1", "t16"), terminal("pd2", "t17")], weights: [0.7, 0.3]))
        document.removePane("pd2")
        #expect(document.spaces[0].tabs[0].root == .split(id: "tb1", axis: .row, children: [terminal("pd1", "t16")], weights: [1]))
    }

    @Test func theLastPaneClosesTheTabAndTheLastTabClosesTheSpace() {
        var document = LayoutDocument(value: herdrDocument)
        document.addTab(id: "tb2", toSpace: "sp1", after: nil, paneID: "p2", terminal: "t2")
        document.removePane("p2")
        #expect(document.spaces[0].tabs.map(\.id) == ["tb1"])
        document.removePane("pd1")
        document.removePane("pd2")
        #expect(document.spaces.isEmpty)
    }

    @Test func removingATabOrASpaceRemovesIt() {
        var document = LayoutDocument(value: herdrDocument)
        document.addTab(id: "tb2", toSpace: "sp1", after: nil, paneID: "p2", terminal: "t2")
        document.removeTab("tb1")
        #expect(document.spaces[0].tabs.map(\.id) == ["tb2"])
        document.removeSpace("sp1")
        #expect(document.spaces.isEmpty)
    }

    @Test func newIdsHaveThePrefixAnd32HexDigits() {
        let id = LayoutDocument.newID("sp")
        #expect(id.count == 34)
        #expect(id.hasPrefix("sp"))
        #expect(id != LayoutDocument.newID("sp"))
    }
}
