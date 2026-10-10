import XCTest
@testable import MoraxCockpitKit

final class AppSettingsTests: XCTestCase {
    private var mockDefaults: UserDefaults!
    private let suiteName = "com.morax.cockpit.tests.settings"
    
    override func setUp() {
        super.setUp()
        mockDefaults = UserDefaults(suiteName: suiteName)!
        mockDefaults.removePersistentDomain(forName: suiteName)
    }
    
    override func tearDown() {
        mockDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }
    
    @MainActor
    func testDefaultValues() {
        let settings = AppSettings(defaults: mockDefaults)
        
        XCTAssertTrue(settings.showDockIcon)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.updateCheckFrequency, .silent)
        XCTAssertEqual(settings.temperatureUnit, .system)
        XCTAssertTrue(settings.keepMenuBarPosition)
        XCTAssertTrue(settings.macosWidgetsEnabled)
        
        // Menu bar defaults
        XCTAssertTrue(settings.menuBarShowIcon)
        XCTAssertTrue(settings.menuBarShowCpu)
        XCTAssertFalse(settings.menuBarShowRam)
        XCTAssertFalse(settings.menuBarShowNetwork)
        XCTAssertFalse(settings.menuBarShowDisk)
        XCTAssertFalse(settings.menuBarShowTemperature)
        XCTAssertTrue(settings.menuBarShowSwapAlert)
    }
    
    @MainActor
    func testPersistenceOfPreferences() {
        let settings = AppSettings(defaults: mockDefaults)
        
        settings.showDockIcon = false
        settings.updateCheckFrequency = .daily
        settings.temperatureUnit = .fahrenheit
        settings.menuBarShowRam = true
        settings.menuBarShowNetwork = true
        settings.menuBarShowTemperature = true
        
        // Re-instantiate with the same defaults
        let loadedSettings = AppSettings(defaults: mockDefaults)
        
        XCTAssertFalse(loadedSettings.showDockIcon)
        XCTAssertEqual(loadedSettings.updateCheckFrequency, .daily)
        XCTAssertEqual(loadedSettings.temperatureUnit, .fahrenheit)
        XCTAssertTrue(loadedSettings.menuBarShowRam)
        XCTAssertTrue(loadedSettings.menuBarShowNetwork)
        XCTAssertTrue(loadedSettings.menuBarShowTemperature)
    }
    
    func testTemperatureFormatting() {
        let celsiusUnit = TemperatureUnit.celsius
        XCTAssertEqual(celsiusUnit.formatTemperature(celsius: 45.4), "45°C")
        XCTAssertNil(celsiusUnit.formatTemperature(celsius: nil))
        
        let fahrenheitUnit = TemperatureUnit.fahrenheit
        // 100°C = 212°F
        XCTAssertEqual(fahrenheitUnit.formatTemperature(celsius: 100.0), "212°F")
        // 0°C = 32°F
        XCTAssertEqual(fahrenheitUnit.formatTemperature(celsius: 0.0), "32°F")
        
        let kelvinUnit = TemperatureUnit.kelvin
        // 0°C = 273.15 K -> formatted as 273 K
        XCTAssertEqual(kelvinUnit.formatTemperature(celsius: 0.0), "273 K")
    }
    
    func testUpdateFrequencyAllCases() {
        let allCases = UpdateCheckFrequency.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.silent))
        XCTAssertTrue(allCases.contains(.onLaunch))
        XCTAssertTrue(allCases.contains(.daily))
        XCTAssertTrue(allCases.contains(.weekly))
        XCTAssertTrue(allCases.contains(.disabled))
    }
}
