import XCTest
@testable import MoraxCockpitKit

final class CleanupClassificationTests: XCTestCase {
    func testClassificationFollowsRiskTierWithoutChangingSafetyModel() {
        let date = Date(timeIntervalSince1970: 1)
        let safe = FileItem(url: URL(fileURLWithPath: "/tmp/cache"), sizeBytes: 1, modifiedDate: date, category: .systemUserCaches, riskTier: .safe)
        let rebuild = FileItem(url: URL(fileURLWithPath: "/tmp/node_modules"), sizeBytes: 1, modifiedDate: date, category: .devNodeModules, riskTier: .rebuildCost)
        let protected = FileItem(url: URL(fileURLWithPath: "/tmp/catalog"), sizeBytes: 1, modifiedDate: date, category: .stagedUserData, riskTier: .blocked)
        XCTAssertEqual(safe.cleanupClassification, .recoverableNow)
        XCTAssertEqual(rebuild.cleanupClassification, .potentiallyRecoverable)
        XCTAssertEqual(protected.cleanupClassification, .protectedInformational)
    }
}
