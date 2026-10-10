import XCTest
import Foundation
import CoreGraphics
@testable import MoraxCockpitKit

final class TreemapLayoutTests: XCTestCase {
    
    func testSquarifyComputesProportionalAreas() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000) // Area 1,000,000
        
        let rects = TreemapLayoutEngine.squarify(items: [600_000, 300_000, 100_000], bounds: bounds)
        
        XCTAssertEqual(rects.count, 3)
        
        let totalComputedArea = rects.reduce(0) { $0 + ($1.width * $1.height) }
        XCTAssertEqual(totalComputedArea, 1_000_000, accuracy: 1.0)
        
        // Check proportionality
        XCTAssertEqual(rects[0].width * rects[0].height, 600_000, accuracy: 1.0)
        XCTAssertEqual(rects[1].width * rects[1].height, 300_000, accuracy: 1.0)
        XCTAssertEqual(rects[2].width * rects[2].height, 100_000, accuracy: 1.0)
    }
    
    func testSquarifyStaysWithinBoundingBox() {
        let bounds = CGRect(x: 50, y: 50, width: 800, height: 600)
        let areas: [CGFloat] = [200_000, 150_000, 80_000, 30_000, 20_000] // Sum = 480,000 = 800*600
        
        let rects = TreemapLayoutEngine.squarify(items: areas, bounds: bounds)
        
        XCTAssertEqual(rects.count, 5)
        for rect in rects {
            XCTAssertGreaterThanOrEqual(rect.minX, bounds.minX - 0.01)
            XCTAssertGreaterThanOrEqual(rect.minY, bounds.minY - 0.01)
            XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX + 0.01)
            XCTAssertLessThanOrEqual(rect.maxY, bounds.maxY + 0.01)
        }
    }
    
    func testComputeLayoutWithStorageNodeHierarchy() {
        let rootURL = URL(fileURLWithPath: "/tmp/root")
        let rootNode = StorageNode(
            url: rootURL,
            name: "Root",
            logicalSizeBytes: 100_000,
            allocatedSizeBytes: 100_000,
            isDirectory: true
        )
        
        let child1 = StorageNode(
            url: rootURL.appendingPathComponent("video.mov"),
            name: "video.mov",
            logicalSizeBytes: 50_000,
            allocatedSizeBytes: 50_000,
            isDirectory: false,
            category: .videoAndRender
        )
        let child2 = StorageNode(
            url: rootURL.appendingPathComponent("code.swift"),
            name: "code.swift",
            logicalSizeBytes: 30_000,
            allocatedSizeBytes: 30_000,
            isDirectory: false,
            category: .devAndBuild
        )
        let child3 = StorageNode(
            url: rootURL.appendingPathComponent("doc.pdf"),
            name: "doc.pdf",
            logicalSizeBytes: 20_000,
            allocatedSizeBytes: 20_000,
            isDirectory: false,
            category: .documents
        )
        
        rootNode.children = [child1, child2, child3]
        
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        let renderItems = TreemapLayoutEngine.computeLayout(for: rootNode, in: bounds)
        
        XCTAssertEqual(renderItems.count, 3)
        XCTAssertEqual(renderItems[0].node.name, "video.mov")
        XCTAssertEqual(renderItems[0].category, .videoAndRender)
        XCTAssertEqual(renderItems[1].node.name, "code.swift")
        XCTAssertEqual(renderItems[2].node.name, "doc.pdf")
    }
    
    func testComputeLayoutWithEmptyOrSingleChild() {
        let rootURL = URL(fileURLWithPath: "/tmp/empty")
        let emptyRoot = StorageNode(url: rootURL, isDirectory: true)
        
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let emptyResult = TreemapLayoutEngine.computeLayout(for: emptyRoot, in: bounds)
        XCTAssertEqual(emptyResult.count, 1)
        XCTAssertEqual(emptyResult.first?.rect, bounds)
    }

    func testComputeLayoutWithCloudPlaceholdersDoesNotLeaveEmptyVoid() {
        let rootURL = URL(fileURLWithPath: "/Users")
        let rootNode = StorageNode(
            url: rootURL,
            name: "Users",
            logicalSizeBytes: 4_000_000_000_000,
            allocatedSizeBytes: 800_000_000_000,
            isDirectory: true
        )

        let userURL = rootURL.appendingPathComponent("user")
        let userNode = StorageNode(
            url: userURL,
            name: "user",
            logicalSizeBytes: 4_000_000_000_000,
            allocatedSizeBytes: 800_000_000_000,
            isDirectory: true
        )

        let realFolder = StorageNode(
            url: userURL.appendingPathComponent("Pictures"),
            name: "Pictures",
            logicalSizeBytes: 800_000_000_000,
            allocatedSizeBytes: 800_000_000_000,
            isDirectory: true
        )

        // Huge dataless cloud placeholder (3 TB logical, 0 allocated)
        let cloudFolder = StorageNode(
            url: userURL.appendingPathComponent("CloudStorage"),
            name: "CloudStorage",
            logicalSizeBytes: 3_200_000_000_000,
            allocatedSizeBytes: 0,
            isDirectory: false,
            isCloudPlaceholder: true
        )

        userNode.children = [realFolder, cloudFolder]
        rootNode.children = [userNode]

        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let renderItems = TreemapLayoutEngine.computeLayout(for: rootNode, in: bounds, maxDepth: 3)

        // The userNode container should expand, and realFolder should receive the full interior
        let userRenderItem = renderItems.first { $0.node.name == "user" }
        let picturesRenderItem = renderItems.first { $0.node.name == "Pictures" }

        XCTAssertNotNil(userRenderItem)
        XCTAssertNotNil(picturesRenderItem)

        if let userItem = userRenderItem, let picItem = picturesRenderItem {
            // Pictures should take almost all of user's inner area (minus header)
            let userArea = userItem.rect.width * userItem.rect.height
            let picArea = picItem.rect.width * picItem.rect.height
            let ratio = picArea / userArea
            XCTAssertGreaterThan(ratio, 0.85, "Pictures must occupy the vast majority of user container, not shrunken to 20% due to cloud placeholders")
        }
    }
}
