import Foundation

enum MoraxResourceBundle {
    private static let bundleName = "MoraxCockpit_MoraxCockpitKit.bundle"

    private static let resourceDirectories = [
        Bundle.main.resourceURL,
        Bundle(for: BundleFinder.self).resourceURL
    ].compactMap { $0 }

    static func url(forResource name: String, withExtension fileExtension: String) -> URL? {
        resourceDirectories.lazy.compactMap {
            url(in: $0, forResource: name, withExtension: fileExtension)
        }.first
    }

    static func url(
        in resourcesDirectory: URL,
        forResource name: String,
        withExtension fileExtension: String
    ) -> URL? {
        Bundle(url: resourcesDirectory.appendingPathComponent(bundleName))?
            .url(forResource: name, withExtension: fileExtension)
    }
}

private final class BundleFinder {}
