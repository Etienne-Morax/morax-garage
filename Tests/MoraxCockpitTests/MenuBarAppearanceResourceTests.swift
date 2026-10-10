import Foundation
import Testing

struct MenuBarAppearanceResourceTests {
    @Test("The shared menu bar icon has a white variant for dark appearances")
    func whiteWrenchIconExists() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconURL = repositoryRoot
            .appendingPathComponent("Sources/MoraxCockpitKit/Resources/wrench-template-white.png")

        #expect(FileManager.default.fileExists(atPath: iconURL.path))
    }
}
