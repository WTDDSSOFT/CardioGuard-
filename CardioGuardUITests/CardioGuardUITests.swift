//
//  CardioGuardUITests.swift
//  CardioGuardUITests
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import XCTest

final class CardioGuardUITests: XCTestCase {

    var app: XCUIApplication!

    override class func setUp() {
        super.setUp()
        XCUIApplication().launch()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        resetAppState()
    }

    override func tearDownWithError() throws {
        app = nil
    }

   
    // MARK: - Dashboard: Monitoring Toggle

    @MainActor
    func testStartMonitoringChangesButtonLabel() {
        app.buttons["Start Monitoring"].tap()
        XCTAssertTrue(app.buttons["Stop Monitoring"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStartMonitoringShowsLiveIndicator() {
        app.buttons["Start Monitoring"].tap()
        XCTAssertTrue(app.staticTexts["Live"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStopMonitoringHidesLiveIndicator() {
        app.buttons["Start Monitoring"].tap()
        XCTAssertTrue(app.staticTexts["Live"].waitForExistence(timeout: 2))
        app.buttons["Stop Monitoring"].tap()
        XCTAssertFalse(app.staticTexts["Live"].exists)
    }

    @MainActor
    func testStopMonitoringRestoresStartButton() {
        app.buttons["Start Monitoring"].tap()
        XCTAssertTrue(app.buttons["Stop Monitoring"].waitForExistence(timeout: 2))
        app.buttons["Stop Monitoring"].tap()
        XCTAssertTrue(app.buttons["Start Monitoring"].waitForExistence(timeout: 2))
    }

    // MARK: - Scanner: Navigation

    @MainActor
    func testScannerSheetOpens() {
        app.buttons["Open Scanner"].tap()
        XCTAssertTrue(app.navigationBars["BLE Scanner"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testScannerCancelDismissesSheet() {
        app.buttons["Open Scanner"].tap()
        XCTAssertTrue(app.navigationBars["BLE Scanner"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["BLE Scanner"].exists)
    }

    // MARK: - Scanner: Initial State

    @MainActor
    func testScannerInitialStateShowsReadyToScan() {
        openScanner()
        XCTAssertTrue(app.staticTexts["Ready to Scan"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testScannerInitialStateShowsStartScanButton() {
        openScanner()
        XCTAssertTrue(app.buttons["Start Scan"].exists)
    }

    // MARK: - Scanner: Scan Flow

    @MainActor
    func testStartScanShowsScanningTitle() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.staticTexts["Scanning..."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStartScanShowsStopButton() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.buttons["Stop Scan"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStopScanReturnsToIdleState() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.buttons["Stop Scan"].waitForExistence(timeout: 2))
        app.buttons["Stop Scan"].tap()
        XCTAssertTrue(app.staticTexts["Ready to Scan"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Start Scan"].exists)
    }

    @MainActor
    func testScanDiscoversMockDevices() {
        openScanner()
        app.buttons["Start Scan"].tap()
        // Mock discovers devices after 2.5 seconds
        XCTAssertTrue(app.staticTexts["CardioGuard Pro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HealthBand Ultra"].exists)
    }

    @MainActor
    func testScanShowsNearbyDevicesHeader() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.staticTexts["Nearby Devices"].waitForExistence(timeout: 5))
    }

    // MARK: - Scanner: Connect Flow

    @MainActor
    func testConnectToDeviceShowsConnectingState() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.staticTexts["CardioGuard Pro"].waitForExistence(timeout: 5))
        app.buttons["Connect"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Connecting..."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testConnectedStateShowsDoneButton() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.staticTexts["CardioGuard Pro"].waitForExistence(timeout: 5))
        app.buttons["Connect"].firstMatch.tap()
        // Mock connection takes 1.5 seconds
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testDoneButtonDismissesScanner() {
        openScanner()
        app.buttons["Start Scan"].tap()
        XCTAssertTrue(app.staticTexts["CardioGuard Pro"].waitForExistence(timeout: 5))
        app.buttons["Connect"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["BLE Scanner"].exists)
    }

    // MARK: - Helpers

    private func openScanner() {
        app.buttons["Open Scanner"].tap()
    }

    // Dismiss the scanner sheet and stop monitoring so each test starts from a clean dashboard.
    private func resetAppState() {
        if app.navigationBars["BLE Scanner"].exists {
            app.buttons["Cancel"].tap()
        }
        if app.buttons["Stop Monitoring"].exists {
            app.buttons["Stop Monitoring"].tap()
        }
    }
}
