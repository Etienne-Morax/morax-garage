import Foundation
import SwiftUI
import Observation
import os

public struct UpdateInfo: Sendable, Equatable {
    public let currentVersion: String
    public let currentBuild: String
    public let latestVersion: String
    public let isUpdateAvailable: Bool
    public let releaseNotesURL: URL?
    public let lastCheckedDate: Date
    public let message: String
    
    public init(
        currentVersion: String = "1.0.0",
        currentBuild: String = "3011",
        latestVersion: String = "1.0.0",
        isUpdateAvailable: Bool = false,
        releaseNotesURL: URL? = UpdateService.defaultReleasesURL,
        lastCheckedDate: Date = .now,
        message: String = "Morax Garage est à jour (v1.0.0)."
    ) {
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.latestVersion = latestVersion
        self.isUpdateAvailable = isUpdateAvailable
        self.releaseNotesURL = releaseNotesURL
        self.lastCheckedDate = lastCheckedDate
        self.message = message
    }
}

/// Subset of the GitHub "latest release" payload we care about.
struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// Performs an HTTP request; injectable so tests never hit the network.
public typealias UpdateFetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

@Observable
@MainActor
public final class UpdateService {
    public static let shared = UpdateService()

    public nonisolated static let repository = "Etienne-Morax/morax-garage"
    public nonisolated static let defaultReleasesURL = URL(string: "https://github.com/\(repository)/releases")
    nonisolated static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    nonisolated static let requestTimeout: TimeInterval = 10

    private static let logger = Logger(subsystem: "com.morax.cockpit", category: "Updates")

    /// Compares dotted numeric versions ("1.0.10" > "1.0.9"); missing components count as 0.
    public nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = numericComponents(candidate)
        let b = numericComponents(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func normalizedVersion(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
    }

    private nonisolated static func numericComponents(_ version: String) -> [Int] {
        normalizedVersion(version).split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let fetch: UpdateFetch
    private let lastCheckKey = "morax_last_update_check_date"
    
    public var isChecking: Bool = false
    public var lastCheckInfo: UpdateInfo?
    public var errorMessage: String?
    
    public init(
        defaults: UserDefaults = .standard,
        fetch: @escaping UpdateFetch = { try await URLSession.shared.data(for: $0) }
    ) {
        self.defaults = defaults
        self.fetch = fetch
        if let savedDate = defaults.object(forKey: lastCheckKey) as? Date {
            self.lastCheckInfo = UpdateInfo(
                lastCheckedDate: savedDate,
                message: "Dernière vérification : \(Self.formatDate(savedDate))"
            )
        }
    }
    
    public func shouldAutoCheck(frequency: UpdateCheckFrequency) -> Bool {
        switch frequency {
        case .disabled:
            return false
        case .onLaunch, .silent:
            return true
        case .daily:
            guard let last = defaults.object(forKey: lastCheckKey) as? Date else { return true }
            return Date().timeIntervalSince(last) > 86400 // 24 hours
        case .weekly:
            guard let last = defaults.object(forKey: lastCheckKey) as? Date else { return true }
            return Date().timeIntervalSince(last) > 604800 // 7 days
        }
    }
    
    public func checkOnLaunchIfNeeded(frequency: UpdateCheckFrequency) {
        guard shouldAutoCheck(frequency: frequency) else { return }
        Task {
            _ = await checkForUpdates(manual: false)
        }
    }
    
    @discardableResult
    public func checkForUpdates(manual: Bool = true) async -> UpdateInfo {
        isChecking = true
        errorMessage = nil
        
        let bundleVersion: String = {
            if let id = Bundle.main.bundleIdentifier, id.contains("morax") || id.contains("garage") {
                return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            }
            return "1.0.0"
        }()
        
        let bundleBuild: String = {
            if let id = Bundle.main.bundleIdentifier, id.contains("morax") || id.contains("garage") {
                return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3011"
            }
            return "3011"
        }()
        
        let now = Date()
        let result: UpdateInfo
        do {
            let release = try await fetchLatestRelease()
            defaults.set(now, forKey: lastCheckKey)
            result = Self.makeInfo(
                release: release, currentVersion: bundleVersion,
                currentBuild: bundleBuild, checkedAt: now
            )
        } catch {
            Self.logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Impossible de vérifier les mises à jour."
            result = UpdateInfo(
                currentVersion: bundleVersion, currentBuild: bundleBuild,
                latestVersion: bundleVersion, isUpdateAvailable: false,
                releaseNotesURL: Self.defaultReleasesURL, lastCheckedDate: now,
                message: "Impossible de vérifier les mises à jour."
            )
        }

        self.lastCheckInfo = result
        self.isChecking = false
        return result
    }
    
    /// Returns nil when no release is published yet (HTTP 404).
    private func fetchLatestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: Self.latestReleaseAPIURL, timeoutInterval: Self.requestTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private static func makeInfo(
        release: GitHubRelease?, currentVersion: String, currentBuild: String, checkedAt: Date
    ) -> UpdateInfo {
        guard let release else {
            return UpdateInfo(
                currentVersion: currentVersion, currentBuild: currentBuild,
                latestVersion: currentVersion, isUpdateAvailable: false,
                releaseNotesURL: defaultReleasesURL, lastCheckedDate: checkedAt,
                message: "Aucune version publiée pour le moment. Morax Garage v\(currentVersion) est à jour."
            )
        }
        let latest = normalizedVersion(release.tagName)
        let isNewer = isVersion(latest, newerThan: currentVersion)
        return UpdateInfo(
            currentVersion: currentVersion, currentBuild: currentBuild,
            latestVersion: latest, isUpdateAvailable: isNewer,
            releaseNotesURL: release.htmlURL ?? defaultReleasesURL, lastCheckedDate: checkedAt,
            message: isNewer
                ? "La version \(latest) est disponible (actuelle : v\(currentVersion))."
                : "Morax Garage v\(currentVersion) est à jour."
        )
    }

    public nonisolated static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
}
