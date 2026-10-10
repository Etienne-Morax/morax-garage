import Testing
@testable import MoraxCockpitKit

@MainActor
private final class OpenerProbe {
    var activations = 0
    var newWindows = 0
    var hasExistingWindow = false
    var broughtToFront = 0
}

@MainActor
private func makeOpener(_ probe: OpenerProbe) -> MainWindowOpener {
    MainWindowOpener(
        activateApp: { probe.activations += 1 },
        bringExistingWindowToFront: {
            guard probe.hasExistingWindow else { return false }
            probe.broughtToFront += 1
            return true
        }
    )
}

@Suite("Main window opener")
@MainActor
struct MainWindowOpenerTests {
    @Test("with the main window closed, open creates a new one through the registered action")
    func closedWindowIsRecreated() {
        let probe = OpenerProbe()
        let opener = makeOpener(probe)
        opener.register { probe.newWindows += 1 }

        let handled = opener.open()

        #expect(handled)
        #expect(probe.newWindows == 1)
        #expect(probe.activations == 1)
    }

    @Test("an existing main window is brought forward instead of opening a duplicate")
    func existingWindowIsReused() {
        let probe = OpenerProbe()
        probe.hasExistingWindow = true
        let opener = makeOpener(probe)
        opener.register { probe.newWindows += 1 }

        #expect(opener.open())
        #expect(probe.broughtToFront == 1)
        #expect(probe.newWindows == 0)
    }

    @Test("without a registered action or a window, open reports it could not help")
    func unregisteredOpenerFallsBack() {
        let probe = OpenerProbe()
        let opener = makeOpener(probe)

        #expect(opener.open() == false)
    }
}
