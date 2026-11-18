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

    @Test func aTerminalAddressOfAMachineBecomesLocalForThatMachine() {
        #expect(LayoutDocument.localID("box/t7", machine: "box") == "t7")
        #expect(LayoutDocument.localID("t7", machine: nil) == "t7")
        #expect(LayoutDocument.localID("other/t7", machine: "box") == "other/t7")
    }
}
