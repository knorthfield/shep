import Testing
@testable import Shep

struct SidebarFilterTests {
    @Test func anEmptyFilterShowsEachSpace() {
        #expect(SidebarFilter.shows(spaceName: "shep", machineName: "This Computer", filter: ""))
    }

    @Test func aFilterShowsASpaceWhoseNameContainsIt() {
        #expect(SidebarFilter.shows(spaceName: "quarterdeck.courses", machineName: "box", filter: "deck"))
    }

    @Test func aFilterShowsEachSpaceOfAMachineWhoseNameContainsIt() {
        #expect(SidebarFilter.shows(spaceName: "shep", machineName: "infinite-loop", filter: "loop"))
    }

    @Test func aFilterHidesASpaceWhenNoNameContainsIt() {
        #expect(!SidebarFilter.shows(spaceName: "shep", machineName: "This Computer", filter: "deck"))
    }

    @Test func aFilterIgnoresTheCaseOfLetters() {
        #expect(SidebarFilter.shows(spaceName: "Shep", machineName: "This Computer", filter: "sHE"))
    }
}
