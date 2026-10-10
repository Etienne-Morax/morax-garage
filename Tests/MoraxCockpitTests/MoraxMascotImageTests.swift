import AppKit
import Foundation
import Testing
@testable import MoraxCockpitKit

struct MoraxMascotImageTests {
    private var mascotURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MoraxCockpitKit/Resources/MoraxMascot.png")
    }

    @Test("the 1024 px mascot is decoded at display size, not full resolution")
    func mascotIsDownsampled() throws {
        let image = try #require(
            MoraxMascotImage.downsampledImage(at: mascotURL, maxPixelSize: MoraxMascotImage.maxPixelSize)
        )
        let bitmap = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        #expect(max(bitmap.width, bitmap.height) == MoraxMascotImage.maxPixelSize)
        #expect(image.size.width == image.size.height)
    }

    @Test("the downsampled mascot still covers the largest on-screen size at @2x")
    func downsampledSizeCoversLargestMascot() {
        let largestMascotPoints = 72
        #expect(MoraxMascotImage.maxPixelSize >= largestMascotPoints * 2)
    }

    @Test("a missing file yields no image instead of trapping")
    func missingFileYieldsNil() {
        let missing = URL(fileURLWithPath: "/nonexistent/MoraxMascot.png")
        #expect(MoraxMascotImage.downsampledImage(at: missing, maxPixelSize: 64) == nil)
    }

    @Test("the mascot is loaded once and shared by every view")
    @MainActor
    func mascotIsLoadedOnce() {
        let first = MoraxMascotImage.shared
        let second = MoraxMascotImage.shared
        #expect(first === second)
        if let first {
            #expect(max(first.size.width, first.size.height) <= CGFloat(MoraxMascotImage.maxPixelSize))
        }
    }
}
