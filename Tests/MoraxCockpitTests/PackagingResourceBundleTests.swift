import Foundation
import Testing

@testable import MoraxCockpitKit

struct PackagingResourceBundleTests {
    @Test("The resource resolver loads a SwiftPM bundle from an app Resources directory")
    func resolverLoadsResourceFromAppResourcesDirectory() throws {
        let fileManager = FileManager.default
        let resourcesURL = fileManager.temporaryDirectory
            .appendingPathComponent("MoraxGarageResourceFixture-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: resourcesURL) }

        let bundleURL = resourcesURL.appendingPathComponent("MoraxCockpit_MoraxCockpitKit.bundle")
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let info: [String: String] = [
            "CFBundleIdentifier": "com.morax.garage.fixture",
            "CFBundleName": "MoraxCockpit_MoraxCockpitKit"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundleURL.appendingPathComponent("Info.plist"))
        let mascotURL = bundleURL.appendingPathComponent("MoraxMascot.png")
        try Data([0]).write(to: mascotURL)

        let resolvedURL = MoraxResourceBundle.url(
            in: resourcesURL,
            forResource: "MoraxMascot",
            withExtension: "png"
        )

        #expect(resolvedURL == mascotURL)
    }

    @Test("Release resource loading uses the signed app Resources directory without fatal SwiftPM accessors")
    func releaseResourcesUseTheMacOSBundleResourcesDirectory() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/build_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let mascotSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/MoraxCockpitKit/Core/DesignSystem/MoraxMascotView.swift"),
            encoding: .utf8
        )
        let menuSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/MoraxCockpitKit/Core/DesignSystem/MoraxMenuBarView.swift"),
            encoding: .utf8
        )

        #expect(script.contains("cp -R \"$bundle\" \"$MAIN_APP/Contents/Resources/\""))
        #expect(script.contains("cp -R \"$bundle\" \"$MENU_APP/Contents/Resources/\""))
        #expect(!mascotSource.contains("Bundle.module"))
        #expect(!menuSource.contains("Bundle.module"))
        #expect(mascotSource.contains("MoraxResourceBundle"))
        #expect(menuSource.contains("MoraxResourceBundle"))
    }
}
