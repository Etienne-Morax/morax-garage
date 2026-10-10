import XCTest
import Foundation
@testable import MoraxCockpitKit

/// "Quick Look Preview" must only preview (or reveal) a file, never open or launch it.
@MainActor
final class QuickLookPreviewerTests: XCTestCase {
    func testPreviewPresentsPanelForTheItemWithoutRevealing() {
        let url = URL(fileURLWithPath: "/tmp/run-me.command")
        var presentedURL: URL? = nil
        var revealed: [URL] = []
        let previewer = QuickLookPreviewer(
            presentPanel: { previewer in
                presentedURL = previewer.previewURL
                return true
            },
            revealInFinder: { revealed.append($0) }
        )

        previewer.preview(url)

        XCTAssertEqual(presentedURL, url)
        XCTAssertTrue(revealed.isEmpty)
    }

    func testPreviewFallsBackToRevealInFinderWhenPanelUnavailable() {
        let url = URL(fileURLWithPath: "/tmp/installer.pkg")
        var revealed: [URL] = []
        let previewer = QuickLookPreviewer(
            presentPanel: { _ in false },
            revealInFinder: { revealed.append($0) }
        )

        previewer.preview(url)

        XCTAssertEqual(revealed, [url])
    }
}
