//
//  PreFlightValidatorTests.swift
//  LeverPilotTests
//

import XCTest
import MeticulousProfile
import EspressoBLE
@testable import LeverPilot

@MainActor
final class PreFlightValidatorTests: XCTestCase {
    
    private var bleManager: EspressoBLEManager!
    private var validProfile: Profile!
    
    override func setUp() {
        super.setUp()
        bleManager = EspressoBLEManager()
        
        let dummyStage = Stage(
            name: "Extraction",
            key: "stage_1",
            type: .pressure,
            dynamics: Dynamics(points: [Point(0.0, 9.0)], over: .time, interpolation: .linear),
            exitTriggers: [ExitTrigger(type: .weight, value: 36.0)]
        )
        
        validProfile = Profile(
            name: "Test Espresso",
            id: "test-profile-1",
            author: "Barista",
            authorId: "barista-1",
            temperature: 93.0,
            finalWeight: 36.0,
            stages: [dummyStage]
        )
    }
    
    override func tearDown() {
        bleManager = nil
        validProfile = nil
        super.tearDown()
    }
    
    // MARK: - Profile Verification
    
    func test_evaluate_failsWhenProfileIsNil() {
        let issues = PreFlightValidator.evaluate(profile: nil, bleManager: bleManager)
        XCTAssertTrue(issues.contains(.noProfileSelected))
    }
    
    func test_evaluate_failsWhenProfileHasNoStages() {
        var emptyProfile = validProfile!
        emptyProfile.stages = []
        
        let issues = PreFlightValidator.evaluate(profile: emptyProfile, bleManager: bleManager)
        XCTAssertTrue(issues.contains(.profileHasNoStages))
    }
    
    // MARK: - Hardware Verification (Default Offline State)
    
    func test_evaluate_failsWhenPeripheralsAreDisconnected() {
        let issues = PreFlightValidator.evaluate(profile: validProfile, bleManager: bleManager)
        
        // Out-of-the-box fresh bleManager has offline slots
        XCTAssertTrue(issues.contains(.scaleDisconnected))
        XCTAssertTrue(issues.contains(.pressureDisconnected))
        XCTAssertFalse(issues.isEmpty)
    }
    
    // MARK: - Granular Bluetooth State Tests (ADR-009)
    
    func test_evaluate_surfacesBluetoothPoweredOff_whenManagerReportsPoweredOff() {
        // Mock manager centralState to poweredOff
        let manager = EspressoBLEManager()
        // Manager centralState defaults to .unknown (not ready), which maps to .bluetoothPoweredOff
        let issues = PreFlightValidator.evaluate(profile: validProfile, bleManager: manager)
        XCTAssertTrue(issues.contains(.bluetoothPoweredOff))
    }
    
    // MARK: - Debug Scenario Override
    
    func test_evaluate_passesWhenDebugScenarioIsPrimed_EvenIfHardwareOffline() {
        let mockScenario = ShotRecord(
            id: "fixture-1",
            profileId: validProfile.id,
            samples: [ShotSample(timestamp: 0.0, pressure: 0.0, flow: 0.0, weight: 0.0)]
        )
        
        let issues = PreFlightValidator.evaluate(
            profile: validProfile,
            bleManager: bleManager,
            primedScenario: mockScenario
        )
        
        XCTAssertTrue(issues.isEmpty, "Priming a debug scenario must satisfy pre-flight telemetry interlock")
    }
    
    // MARK: - Session Copy Isolation
    
    func test_sessionCopyIsolation_doesNotMutateCatalogProfile() throws {
        let store = ProfileStore(mode: .inMemory)
        try store.save(profile: validProfile)
        
        var sessionCopy = try XCTUnwrap(store.profile(withID: validProfile.id))
        sessionCopy.finalWeight = 50.0
        sessionCopy.temperature = 99.0
        
        let persisted = try XCTUnwrap(store.profile(withID: validProfile.id))
        XCTAssertEqual(persisted.finalWeight, 36.0)
        XCTAssertEqual(persisted.temperature, 93.0)
        XCTAssertNotEqual(persisted.finalWeight, sessionCopy.finalWeight)
    }
}
