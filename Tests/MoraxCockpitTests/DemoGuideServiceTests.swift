import XCTest
import Foundation
@testable import MoraxCockpitKit

final class DemoGuideServiceTests: XCTestCase {
    
    func testDemoGuideServiceContainsAll9Pages() {
        let service = DemoGuideService.shared
        XCTAssertEqual(service.pageGuides.count, 9)
        
        let expectedPages = [
            "Dashboard",
            "Storage Map",
            "Cleanup & Cache",
            "Permissions",
            "Mole Terminal",
            "Applications",
            "Homebrew",
            "Persistence Audit",
            "Environment"
        ]
        
        for expected in expectedPages {
            let guide = service.guide(for: expected)
            XCTAssertNotNil(guide, "Missing guide for page: \(expected)")
            
            if let guide = guide {
                XCTAssertFalse(guide.title.isEmpty, "Title should not be empty for \(expected)")
                XCTAssertFalse(guide.subtitle.isEmpty, "Subtitle should not be empty for \(expected)")
                XCTAssertFalse(guide.purpose.isEmpty, "Purpose should not be empty for \(expected)")
                XCTAssertFalse(guide.whyItMatters.isEmpty, "WhyItMatters should not be empty for \(expected)")
                XCTAssertFalse(guide.features.isEmpty, "Features should not be empty for \(expected)")
                XCTAssertFalse(guide.capabilities.isEmpty, "Capabilities should not be empty for \(expected)")
                XCTAssertFalse(guide.example.title.isEmpty, "Example title should not be empty for \(expected)")
                XCTAssertFalse(guide.example.stepByStep.isEmpty, "Example steps should not be empty for \(expected)")
                XCTAssertFalse(guide.safetyGuarantee.isEmpty, "Safety guarantee should not be empty for \(expected)")
            }
        }
    }
    
    func testDemoGuideScenariosAreValidAndComplete() {
        let service = DemoGuideService.shared
        XCTAssertGreaterThanOrEqual(service.scenarios.count, 3)
        
        for scenario in service.scenarios {
            XCTAssertFalse(scenario.id.isEmpty)
            XCTAssertFalse(scenario.title.isEmpty)
            XCTAssertFalse(scenario.narrative.isEmpty)
            XCTAssertGreaterThanOrEqual(scenario.steps.count, 2)
            XCTAssertFalse(scenario.outcome.storageReclaimed.isEmpty)
            XCTAssertFalse(scenario.outcome.performanceGain.isEmpty)
            XCTAssertFalse(scenario.outcome.safetyAssurance.isEmpty)
        }
    }
    
    func testDemoSafetyPrinciplesAreComplete() {
        let service = DemoGuideService.shared
        XCTAssertEqual(service.safetyPrinciples.count, 3)
        
        for principle in service.safetyPrinciples {
            XCTAssertGreaterThan(principle.ruleNumber, 0)
            XCTAssertFalse(principle.title.isEmpty)
            XCTAssertFalse(principle.shortSummary.isEmpty)
            XCTAssertFalse(principle.deepExplanation.isEmpty)
            XCTAssertFalse(principle.forbiddenPractices.isEmpty)
            XCTAssertFalse(principle.moraxStrictPractice.isEmpty)
            XCTAssertFalse(principle.technicalJustification.isEmpty)
        }
    }
    
    func testDemoFAQItemsAreComplete() {
        let service = DemoGuideService.shared
        XCTAssertGreaterThanOrEqual(service.faqItems.count, 5)
        
        for faq in service.faqItems {
            XCTAssertFalse(faq.category.isEmpty)
            XCTAssertFalse(faq.question.isEmpty)
            XCTAssertFalse(faq.answer.isEmpty)
        }
    }
}
