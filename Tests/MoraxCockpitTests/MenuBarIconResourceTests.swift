import Foundation
import Testing

@testable import MoraxCockpitKit

struct MenuBarIconResourceTests {
    @Test("The menu bar wrench icon is bundled with all relevant targets")
    func wrenchIconResourceExists() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        
        let kitIconURL = repositoryRoot
            .appendingPathComponent("Sources/MoraxCockpitKit/Resources/wrench-template-black.png")
        let mainIconURL = repositoryRoot
            .appendingPathComponent("Sources/MoraxCockpit/Resources/wrench-template-black.png")
        let menuIconURL = repositoryRoot
            .appendingPathComponent("Sources/MoraxCockpitMenu/Resources/wrench-template-black.png")

        #expect(FileManager.default.fileExists(atPath: kitIconURL.path))
        #expect(FileManager.default.fileExists(atPath: mainIconURL.path))
        #expect(FileManager.default.fileExists(atPath: menuIconURL.path))
    }
}
