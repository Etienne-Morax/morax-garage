import XCTest
@testable import MoraxCockpitKit

final class NettopCSVParserTests: XCTestCase {
    func testGroupsProcessRowsByApplicationNameAndKeepsThreeLargestRates() {
        let rows = [
            NettopProcessSample(processLabel: "Safari.12", bytesIn: 900, bytesOut: 100),
            NettopProcessSample(processLabel: "Safari.44", bytesIn: 200, bytesOut: 300),
            NettopProcessSample(processLabel: "Drive.8", bytesIn: 700, bytesOut: 700),
            NettopProcessSample(processLabel: "Mail.3", bytesIn: 10, bytesOut: 10),
            NettopProcessSample(processLabel: "VPN.2", bytesIn: 800, bytesOut: 0)
        ]
        
        let top = NettopApplicationAggregator.topApplications(from: rows, limit: 3)
        XCTAssertEqual(top.map(\.name), ["Safari", "Drive", "VPN"])
        XCTAssertEqual(top[0].downloadBytesPerSecond, 1100)
        XCTAssertEqual(top[0].uploadBytesPerSecond, 400)
        XCTAssertEqual(top[0].totalBytesPerSecond, 1500)
    }
    
    func testRejectsHeaderWithoutByteColumns() {
        XCTAssertThrowsError(try NettopCSVHeader.parse("time,process,state")) { error in
            guard let parseError = error as? NettopParseError,
                  case .missingRequiredColumns = parseError else {
                XCTFail("Expected NettopParseError.missingRequiredColumns, got \(error)")
                return
            }
        }
    }
    
    func testParsesStandardNettopHeaderAndSampleRow() throws {
        let headerLine = "time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,"
        let header = try NettopCSVHeader.parse(headerLine)
        
        let rowLine = "09:28:23.730455,apsd.372,,,413018,163883,2645,0,3462,,,,,,,,,,,,"
        let sample = try header.parseSample(from: rowLine)
        
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.processLabel, "apsd.372")
        XCTAssertEqual(sample?.cleanApplicationName, "apsd")
        XCTAssertEqual(sample?.bytesIn, 413018)
        XCTAssertEqual(sample?.bytesOut, 163883)
    }
    
    func testParsesOptimizedColumnFilteredHeaderAndSampleRow() throws {
        let headerLine = ",bytes_in,bytes_out,"
        let header = try NettopCSVHeader.parse(headerLine)
        
        let rowLine = "apsd.371,1658121,1308382,"
        let sample = try header.parseSample(from: rowLine)
        
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.processLabel, "apsd.371")
        XCTAssertEqual(sample?.cleanApplicationName, "apsd")
        XCTAssertEqual(sample?.bytesIn, 1658121)
        XCTAssertEqual(sample?.bytesOut, 1308382)
    }
    
    func testExtractsApplicationNameWithoutTrailingPID() {
        XCTAssertEqual(NettopProcessSample.cleanName(from: "Safari.123"), "Safari")
        XCTAssertEqual(NettopProcessSample.cleanName(from: "Google Chrome Helper (Renderer).456"), "Google Chrome Helper (Renderer)")
        XCTAssertEqual(NettopProcessSample.cleanName(from: "node"), "node")
        XCTAssertEqual(NettopProcessSample.cleanName(from: "daemon.service.99"), "daemon.service")
    }
    
    func testIgnoresMalformedRows() throws {
        let headerLine = "time,,interface,state,bytes_in,bytes_out"
        let header = try NettopCSVHeader.parse(headerLine)
        
        XCTAssertNil(try header.parseSample(from: ""))
        XCTAssertNil(try header.parseSample(from: "short,row"))
        XCTAssertNil(try header.parseSample(from: "time,proc,,not_a_number,100"))
    }
    
    func testDeltaCalculatorComputesAppRatesOverInterval() {
        let previous = [
            "Safari": NettopProcessSample(processLabel: "Safari", bytesIn: 1000, bytesOut: 500),
            "Mail": NettopProcessSample(processLabel: "Mail", bytesIn: 200, bytesOut: 100)
        ]
        let current = [
            "Safari": NettopProcessSample(processLabel: "Safari", bytesIn: 3000, bytesOut: 1500),
            "Mail": NettopProcessSample(processLabel: "Mail", bytesIn: 400, bytesOut: 200)
        ]
        
        let apps = NettopApplicationAggregator.calculateRates(
            previousTotals: previous,
            currentTotals: current,
            elapsed: 2.0,
            limit: 3
        )
        
        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps[0].name, "Safari")
        XCTAssertEqual(apps[0].downloadBytesPerSecond, 1000) // (3000-1000)/2
        XCTAssertEqual(apps[0].uploadBytesPerSecond, 500)   // (1500-500)/2
        XCTAssertEqual(apps[0].totalBytesPerSecond, 1500)
        
        XCTAssertEqual(apps[1].name, "Mail")
        XCTAssertEqual(apps[1].downloadBytesPerSecond, 100)  // (400-200)/2
        XCTAssertEqual(apps[1].uploadBytesPerSecond, 50)    // (200-100)/2
        XCTAssertEqual(apps[1].totalBytesPerSecond, 150)
    }
}
