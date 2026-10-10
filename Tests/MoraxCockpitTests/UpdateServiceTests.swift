import XCTest
@testable import MoraxCockpitKit

final class UpdateServiceTests: XCTestCase {
    private var mockDefaults: UserDefaults!
    private let suiteName = "com.morax.cockpit.tests.updates"
    
    override func setUp() {
        super.setUp()
        mockDefaults = UserDefaults(suiteName: suiteName)!
        mockDefaults.removePersistentDomain(forName: suiteName)
    }
    
    override func tearDown() {
        mockDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }
    
    private func stub(status: Int, body: String = "") -> UpdateFetch {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private func release(_ tag: String) -> String {
        #"{"tag_name":"\#(tag)","html_url":"https://github.com/Etienne-Morax/morax-garage/releases/tag/\#(tag)"}"#
    }

    func testVersionComparison() {
        XCTAssertTrue(UpdateService.isVersion("1.0.10", newerThan: "1.0.9"))
        XCTAssertFalse(UpdateService.isVersion("1.0.9", newerThan: "1.0.10"))
        XCTAssertFalse(UpdateService.isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateService.isVersion("1.0.0", newerThan: "1.0"))
        XCTAssertTrue(UpdateService.isVersion("1.1", newerThan: "1.0.5"))
        XCTAssertTrue(UpdateService.isVersion("v2.0.0", newerThan: "1.9.9"))
        XCTAssertFalse(UpdateService.isVersion("1.0.0", newerThan: "1.0.0"))
    }

    @MainActor
    func testUpdateAvailableUsesReleaseURL() async {
        let service = UpdateService(defaults: mockDefaults, fetch: stub(status: 200, body: release("v9.0.0")))
        let result = await service.checkForUpdates(manual: false)
        XCTAssertTrue(result.isUpdateAvailable)
        XCTAssertEqual(result.latestVersion, "9.0.0")
        XCTAssertEqual(result.releaseNotesURL?.absoluteString, "https://github.com/Etienne-Morax/morax-garage/releases/tag/v9.0.0")
        XCTAssertNotNil(mockDefaults.object(forKey: "morax_last_update_check_date"))
    }

    @MainActor
    func testUpToDateWhenLatestMatchesCurrent() async {
        let service = UpdateService(defaults: mockDefaults, fetch: stub(status: 200, body: release("v1.0.0")))
        let result = await service.checkForUpdates(manual: false)
        XCTAssertFalse(result.isUpdateAvailable)
        XCTAssertTrue(result.message.contains("est à jour"))
    }

    @MainActor
    func testNoReleasePublishedTreatedAsUpToDate() async {
        let service = UpdateService(defaults: mockDefaults, fetch: stub(status: 404))
        let result = await service.checkForUpdates(manual: false)
        XCTAssertFalse(result.isUpdateAvailable)
        XCTAssertTrue(result.message.contains("Aucune version publiée"))
        XCTAssertEqual(result.releaseNotesURL, UpdateService.defaultReleasesURL)
    }

    @MainActor
    func testNetworkErrorReportsFailureWithoutClaimingUpToDate() async {
        let service = UpdateService(defaults: mockDefaults, fetch: { _ in throw URLError(.notConnectedToInternet) })
        let result = await service.checkForUpdates(manual: false)
        XCTAssertFalse(result.isUpdateAvailable)
        XCTAssertEqual(result.message, "Impossible de vérifier les mises à jour.")
        XCTAssertNotNil(service.errorMessage)
        XCTAssertNil(mockDefaults.object(forKey: "morax_last_update_check_date"))
    }

    @MainActor
    func testServerErrorAndBadJSONReportFailure() async {
        for fetch in [stub(status: 500), stub(status: 200, body: "{}")] {
            let service = UpdateService(defaults: mockDefaults, fetch: fetch)
            let result = await service.checkForUpdates(manual: false)
            XCTAssertEqual(result.message, "Impossible de vérifier les mises à jour.")
        }
    }

    @MainActor
    func testCheckForUpdatesManual() async {
        let service = UpdateService(defaults: mockDefaults, fetch: stub(status: 200, body: release("v1.0.0")))
        XCTAssertFalse(service.isChecking)
        
        let result = await service.checkForUpdates(manual: false)
        XCTAssertFalse(service.isChecking)
        XCTAssertFalse(result.isUpdateAvailable)
        XCTAssertEqual(result.currentVersion, "1.0.0")
        XCTAssertNotNil(service.lastCheckInfo)
    }
    
    @MainActor
    func testShouldAutoCheckEvaluation() {
        let service = UpdateService(defaults: mockDefaults)
        
        // Disabled -> always false
        XCTAssertFalse(service.shouldAutoCheck(frequency: .disabled))
        
        // On launch / silent -> always true
        XCTAssertTrue(service.shouldAutoCheck(frequency: .onLaunch))
        XCTAssertTrue(service.shouldAutoCheck(frequency: .silent))
        
        // Daily: without prior check -> true
        XCTAssertTrue(service.shouldAutoCheck(frequency: .daily))
        
        // Save check date from 1 hour ago -> daily check should be false
        mockDefaults.set(Date().addingTimeInterval(-3600), forKey: "morax_last_update_check_date")
        XCTAssertFalse(service.shouldAutoCheck(frequency: .daily))
        
        // Save check date from 25 hours ago -> daily check should be true
        mockDefaults.set(Date().addingTimeInterval(-90000), forKey: "morax_last_update_check_date")
        XCTAssertTrue(service.shouldAutoCheck(frequency: .daily))
    }
    
    func testDateFormatting() {
        let testDate = Date(timeIntervalSince1970: 1723896000)
        let formatted = UpdateService.formatDate(testDate)
        XCTAssertFalse(formatted.isEmpty)
    }
}
