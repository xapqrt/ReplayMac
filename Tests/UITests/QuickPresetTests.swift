import XCTest
import Defaults
@testable import UI

final class QuickPresetTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Defaults.reset(.quickPreset1Seconds, .quickPreset2Seconds, .quickPreset3Seconds)
    }

    func testClampKeepsPresetsInsideTheAllowedRange() {
        XCTAssertEqual(AppSettings.clampQuickPreset(0), AppSettings.quickPresetRange.lowerBound)
        XCTAssertEqual(AppSettings.clampQuickPreset(-30), AppSettings.quickPresetRange.lowerBound)
        XCTAssertEqual(AppSettings.clampQuickPreset(45), 45)
        XCTAssertEqual(AppSettings.clampQuickPreset(10_000), AppSettings.quickPresetRange.upperBound)
    }

    func testDefaultPresetsMatchTheHistoricalHotkeys() {
        // Fresh installs keep the 15 s / 60 s meaning of the two legacy
        // hotkeys and add a 2 minute third preset.
        XCTAssertEqual(AppSettings.quickPresetSeconds, [15, 60, 120])
    }

    func testPresetLabels() {
        XCTAssertEqual(SettingsView.quickPresetLabel(15), "15 seconds")
        XCTAssertEqual(SettingsView.quickPresetLabel(60), "1 minute")
        XCTAssertEqual(SettingsView.quickPresetLabel(90), "1 min 30 s")
        XCTAssertEqual(SettingsView.quickPresetLabel(120), "2 minutes")
        XCTAssertEqual(SettingsView.quickPresetLabel(300), "5 minutes")
    }
}
