import Foundation
import Testing
@testable import Shep

struct MachinesTests {
    @Test func machinesAreReadAndTemporaryMachinesAreNotShown() {
        let machines = Machine.list(from: ["machines": [
            ["name": "quarterdeck", "target": "kris@quarterdeck", "state": "connected"],
            ["name": "vps", "target": "vps", "state": "needs_login", "why": "Permission denied"],
            ["name": "scratch", "state": "connected", "temporary": true],
        ]])
        #expect(machines == [
            Machine(name: "quarterdeck", target: "kris@quarterdeck", state: .connected, reason: ""),
            Machine(name: "vps", target: "vps", state: .needsLogin, reason: "Permission denied"),
        ])
    }

    @Test func aPausedMachineIsAddedAgainWithItsNameSessionAndCommand() {
        let machines = Machine.list(from: ["machines": [
            ["name": "quarterdeck", "target": "quarterdeck", "state": "connected", "session": "work"],
            ["name": "fly", "target": "fly ssh console -C", "state": "connected", "via": true],
        ]])
        #expect(machines[0].addParameters == ["name": "quarterdeck", "target": "quarterdeck", "session": "work"])
        #expect(machines[1].addParameters == ["name": "fly", "via": "fly ssh console -C"])
    }

    @Test func theTargetOfTypedTextHasNoSpacesAroundItAndNoSshCommandBeforeIt() {
        #expect(Machine.target(fromInput: "ssh ankh-morpork.exe.xyz") == "ankh-morpork.exe.xyz")
        #expect(Machine.target(fromInput: "  ssh   kris@box:2222 ") == "kris@box:2222")
        #expect(Machine.target(fromInput: "kris@box") == "kris@box")
        #expect(Machine.target(fromInput: "sshbox") == "sshbox")
        #expect(Machine.target(fromInput: "ssh") == "ssh")
        #expect(Machine.target(fromInput: "  ") == "")
    }

    @Test func theSidebarShowsEachMachineOneTimeByNameAndAPausedMachineAsPaused() {
        let machine = { Machine(name: $0, target: $0, state: .connected, reason: "") }
        let list = Machine.sidebarList(
            active: [machine("quarterdeck"), machine("infinite-loop"), machine("infinite-loop"), machine("quarterdeck")],
            paused: [machine("quarterdeck"), machine("box")]
        )
        #expect(list.map(\.machine.name) == ["box", "infinite-loop", "quarterdeck"])
        #expect(list.map(\.isPaused) == [true, false, true])
    }

    @Test func aTerminalAddressOfAMachineBecomesLocalForThatMachine() {
        #expect(LayoutDocument.localID("box/t7", machine: "box") == "t7")
        #expect(LayoutDocument.localID("t7", machine: nil) == "t7")
        #expect(LayoutDocument.localID("other/t7", machine: "box") == "other/t7")
    }
}
