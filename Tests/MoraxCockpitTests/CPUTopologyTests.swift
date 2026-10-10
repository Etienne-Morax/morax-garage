import XCTest
@testable import MoraxCockpitKit

final class CPUTopologyTests: XCTestCase {

    func testAppleSiliconKeepsPerformanceAndEfficiencyClusters() {
        let topology = CPUTopology.resolve(
            perfLevel0Cores: 8,
            perfLevel1Cores: 4,
            physicalCores: 12,
            logicalCores: 12
        )

        XCTAssertEqual(topology.performanceCores, 8)
        XCTAssertEqual(topology.efficiencyCores, 4)
        XCTAssertTrue(topology.isHeterogeneous)
        XCTAssertEqual(topology.totalCores, 12)
    }

    func testIntelFallsBackToPhysicalCoresWithoutEfficiencyCluster() {
        // Intel Macs expose no hw.perflevel* keys: both readings come back nil.
        let topology = CPUTopology.resolve(
            perfLevel0Cores: nil,
            perfLevel1Cores: nil,
            physicalCores: 6,
            logicalCores: 12
        )

        XCTAssertEqual(topology.performanceCores, 6, "hyper-threading must not inflate the core count")
        XCTAssertEqual(topology.efficiencyCores, 0)
        XCTAssertFalse(topology.isHeterogeneous)
        XCTAssertEqual(topology.totalCores, 6)
    }

    func testFallsBackToLogicalCoresWhenPhysicalCountIsUnreadable() {
        let topology = CPUTopology.resolve(
            perfLevel0Cores: nil,
            perfLevel1Cores: nil,
            physicalCores: nil,
            logicalCores: 4
        )

        XCTAssertEqual(topology.performanceCores, 4)
        XCTAssertEqual(topology.efficiencyCores, 0)
    }

    func testCurrentTopologyReportsAtLeastOneCore() {
        XCTAssertGreaterThan(CPUTopology.current().totalCores, 0)
    }

    func testSnapshotLabelDropsClusterSplitOnHomogeneousCPU() {
        let intel = SystemSnapshot(eCoreCount: 0, pCoreCount: 6)
        let appleSilicon = SystemSnapshot(eCoreCount: 4, pCoreCount: 8)

        XCTAssertEqual(intel.coreLayoutLabel, "6 COEURS")
        XCTAssertEqual(appleSilicon.coreLayoutLabel, "8P / 4E COEURS")
    }
}
