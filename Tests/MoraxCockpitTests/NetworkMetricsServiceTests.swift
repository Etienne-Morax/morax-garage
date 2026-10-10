import XCTest
@testable import MoraxCockpitKit

final class NetworkMetricsServiceTests: XCTestCase {
    func testRateIsZeroForFirstSampleAndUsesElapsedTimeForSecondSample() {
        XCTAssertEqual(NetworkRateCalculator.rate(previous: nil, current: 100, elapsed: 2), 0)
        XCTAssertEqual(NetworkRateCalculator.rate(previous: 100, current: 500, elapsed: 2), 200)
    }
    
    func testCounterRollbackDoesNotCreateNegativeRate() {
        XCTAssertEqual(NetworkRateCalculator.rate(previous: 500, current: 100, elapsed: 2), 0)
    }
    
    func testZeroOrNegativeElapsedTimeReturnsZeroRate() {
        XCTAssertEqual(NetworkRateCalculator.rate(previous: 100, current: 500, elapsed: 0), 0)
        XCTAssertEqual(NetworkRateCalculator.rate(previous: 100, current: 500, elapsed: -1), 0)
    }
    
    func testUnavailableNettopLeavesGlobalRatesVisible() {
        let snapshot = NetworkSnapshot.unavailableTopApplications(
            interfaceName: "en0", downloadBytesPerSecond: 42, uploadBytesPerSecond: 7
        )
        XCTAssertEqual(snapshot.interfaceName, "en0")
        XCTAssertEqual(snapshot.downloadBytesPerSecond, 42)
        XCTAssertEqual(snapshot.uploadBytesPerSecond, 7)
        XCTAssertEqual(snapshot.topApplicationsStatus, .unavailable)
        XCTAssertTrue(snapshot.topApplications.isEmpty)
    }
    
    @MainActor
    func testServiceUpdateSnapshotPublishesCurrentSnapshot() {
        let service = NetworkMetricsService()
        let customSnapshot = NetworkSnapshot(
            timestamp: Date(),
            interfaceName: "en0",
            downloadBytesPerSecond: 1024,
            uploadBytesPerSecond: 512,
            topApplications: [
                NetworkApplicationUsage(name: "Safari", downloadBytesPerSecond: 800, uploadBytesPerSecond: 400)
            ],
            topApplicationsStatus: .active
        )
        
        service.updateSnapshot(customSnapshot)
        XCTAssertEqual(service.currentSnapshot.interfaceName, "en0")
        XCTAssertEqual(service.currentSnapshot.downloadBytesPerSecond, 1024)
        XCTAssertEqual(service.currentSnapshot.uploadBytesPerSecond, 512)
        XCTAssertEqual(service.currentSnapshot.topApplicationsStatus, .active)
        XCTAssertEqual(service.currentSnapshot.topApplications.count, 1)
        XCTAssertEqual(service.currentSnapshot.topApplications.first?.name, "Safari")
    }
}
