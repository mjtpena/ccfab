@testable import FabricTray
import XCTest

final class TrayPreferencesTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "trayDensity")
        super.tearDown()
    }

    // MARK: - Density Scaling

    func testDensityScaleValues() {
        XCTAssertEqual(TrayDensity.compact.scale, 0.85)
        XCTAssertEqual(TrayDensity.standard.scale, 1.0)
        XCTAssertEqual(TrayDensity.comfortable.scale, 1.2)
    }

    func testDensityWindowWidths() {
        XCTAssertLessThan(TrayDensity.compact.windowWidth, TrayDensity.standard.windowWidth)
        XCTAssertLessThan(TrayDensity.standard.windowWidth, TrayDensity.comfortable.windowWidth)
        XCTAssertEqual(TrayDensity.standard.windowWidth, 360)
    }

    func testDensityMaxListHeight() {
        XCTAssertLessThan(TrayDensity.compact.maxListHeight, TrayDensity.standard.maxListHeight)
        XCTAssertLessThan(TrayDensity.standard.maxListHeight, TrayDensity.comfortable.maxListHeight)
    }

    func testDensityIconSize() {
        XCTAssertLessThan(TrayDensity.compact.iconSize, TrayDensity.standard.iconSize)
        XCTAssertLessThan(TrayDensity.standard.iconSize, TrayDensity.comfortable.iconSize)
    }

    func testDensityRowVPad() {
        XCTAssertGreaterThanOrEqual(TrayDensity.compact.rowVPad, 2)
        XCTAssertLessThanOrEqual(TrayDensity.compact.rowVPad, TrayDensity.standard.rowVPad)
        XCTAssertLessThanOrEqual(TrayDensity.standard.rowVPad, TrayDensity.comfortable.rowVPad)
    }

    func testDensityCaptionSize() {
        XCTAssertLessThan(TrayDensity.compact.captionSize, TrayDensity.standard.captionSize)
        XCTAssertLessThan(TrayDensity.standard.captionSize, TrayDensity.comfortable.captionSize)
    }

    func testDensityAllCases() {
        XCTAssertEqual(TrayDensity.allCases.count, 3)
        XCTAssertEqual(TrayDensity.compact.rawValue, "S")
        XCTAssertEqual(TrayDensity.standard.rawValue, "M")
        XCTAssertEqual(TrayDensity.comfortable.rawValue, "L")
    }

    func testDensityIdentifiable() {
        XCTAssertEqual(TrayDensity.compact.id, "S")
        XCTAssertEqual(TrayDensity.standard.id, "M")
        XCTAssertEqual(TrayDensity.comfortable.id, "L")
    }

    // MARK: - Persistence

    func testDefaultDensity() {
        UserDefaults.standard.removeObject(forKey: "trayDensity")
        let prefs = TrayPreferences()
        XCTAssertEqual(prefs.density, .standard)
    }

    func testPersistsDensity() {
        let prefs = TrayPreferences()
        prefs.density = .comfortable
        // Allow Combine sink to fire
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let stored = UserDefaults.standard.string(forKey: "trayDensity")
        XCTAssertEqual(stored, "L")
    }

    func testRestoresDensity() {
        UserDefaults.standard.set("S", forKey: "trayDensity")
        let prefs = TrayPreferences()
        XCTAssertEqual(prefs.density, .compact)
    }

    func testInvalidStoredValueDefaultsToStandard() {
        UserDefaults.standard.set("XL", forKey: "trayDensity")
        let prefs = TrayPreferences()
        XCTAssertEqual(prefs.density, .standard)
    }
}
