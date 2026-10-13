//
//  ProfileOverrideTests.swift
//  LeverPilotTests
//

import XCTest
@testable import LeverPilot
import MeticulousProfile

@MainActor
final class ProfileOverrideTests: XCTestCase {
    
    private func makeFixtureProfile(
        id: String = "test-profile-1",
        temp: Double = 88.0,
        weight: Double = 36.0,
        variables: [Variable] = []
    ) -> Profile {
        Profile(
            name: "Test Recipe",
            id: id,
            author: "Tester",
            authorId: "local",
            temperature: temp,
            finalWeight: weight,
            variables: variables,
            stages: []
        )
    }
    
    // MARK: - 1. Sparse Delta Math
    
    func testSparseDeltaReturnsNilWhenNoChanges() {
        let base = makeFixtureProfile()
        let sparse = ProfileOverride.createSparse(
            baseProfile: base,
            baseDose: 18.0,
            workingDose: 18.0,
            workingTargetWeight: 36.0,
            workingTemperature: 88.0,
            workingVariables: [:]
        )
        
        XCTAssertNil(sparse, "Unchanged parameters must produce a nil sparse delta.")
    }
    
    func testSparseDeltaCapturesOnlyModifiedFields() {
        let base = makeFixtureProfile(
            temp: 88.0,
            weight: 36.0,
            variables: [
                Variable(name: "Pre-infusion", key: "pi_time", type: .time, value: 8.0),
                Variable(name: "Peak Flow", key: "peak_flow", type: .flow, value: 2.0)
            ]
        )
        
        // Only modify dose and pi_time; leave weight, temp, and peak_flow unchanged
        let sparse = ProfileOverride.createSparse(
            baseProfile: base,
            baseDose: 18.0,
            workingDose: 19.5,
            workingTargetWeight: 36.0,
            workingTemperature: 88.0,
            workingVariables: [
                "pi_time": 10.0,
                "peak_flow": 2.0
            ]
        )
        
        XCTAssertNotNil(sparse)
        XCTAssertEqual(sparse?.dose, 19.5)
        XCTAssertNil(sparse?.targetWeight, "Unchanged target weight must remain nil.")
        XCTAssertNil(sparse?.temperature, "Unchanged temperature must remain nil.")
        XCTAssertEqual(sparse?.variables["pi_time"], 10.0)
        XCTAssertNil(sparse?.variables["peak_flow"], "Unchanged variable must not be stored.")
    }
    
    // MARK: - 2. Physical Range Clamping
    
    func testClampingGuardsAgainstExcessiveSetpoints() {
        let base = makeFixtureProfile(
            variables: [
                Variable(name: "Pressure", key: "p_max", type: .pressure, value: 6.0),
                Variable(name: "Flow", key: "f_target", type: .flow, value: 2.0)
            ]
        )
        
        // Malformed/drifted override injecting 50 bar and 25 mL/s
        let override = ProfileOverride(
            variables: [
                "p_max": 50.0,
                "f_target": 25.0
            ]
        )
        
        let (effective, _) = override.applying(to: base, fallbackDose: 18.0)
        
        let clampedPressure = effective.variables.first(where: { $0.key == "p_max" })?.value
        let clampedFlow = effective.variables.first(where: { $0.key == "f_target" })?.value
        
        XCTAssertEqual(clampedPressure, 12.0, "Pressure must be clamped to safe ceiling of 12.0 bar.")
        XCTAssertEqual(clampedFlow, 10.0, "Flow must be clamped to safe ceiling of 10.0 mL/s.")
    }
    
    // MARK: - 3. Whitelist-Only Variable Injection
    
    func testStaleOrphanedVariableKeysAreIgnored() {
        let base = makeFixtureProfile(
            variables: [
                Variable(name: "Bloom", key: "bloom_time", type: .time, value: 5.0)
            ]
        )
        
        // Override contains a deleted/renamed variable key 'old_stage_press'
        let override = ProfileOverride(
            variables: [
                "bloom_time": 7.0,
                "old_stage_press": 9.0
            ]
        )
        
        let (effective, _) = override.applying(to: base, fallbackDose: 18.0)
        
        XCTAssertEqual(effective.variables.count, 1)
        XCTAssertEqual(effective.variables.first?.key, "bloom_time")
        XCTAssertEqual(effective.variables.first?.value, 7.0)
    }
    
    // MARK: - 4. Store Persistence & Revert Lifecycle
    
    func testProfileStoreSaveAndClearLifecycle() {
        let store = ProfileStore(mode: .inMemory)
        let base = makeFixtureProfile(id: "uuid-123")
        
        XCTAssertFalse(store.hasOverride(for: "uuid-123"))
        
        // 1. Save override
        let override = ProfileOverride(dose: 20.0, targetWeight: 42.0)
        store.saveOverride(override, for: "uuid-123")
        
        XCTAssertTrue(store.hasOverride(for: "uuid-123"))
        let (resolved, resolvedDose) = store.effectiveProfile(for: base, fallbackDose: 18.0)
        XCTAssertEqual(resolvedDose, 20.0)
        XCTAssertEqual(resolved.finalWeight, 42.0)
        
        // 2. Clear / Revert
        store.clearOverride(for: "uuid-123")
        XCTAssertFalse(store.hasOverride(for: "uuid-123"))
        
        let (reverted, revertedDose) = store.effectiveProfile(for: base, fallbackDose: 18.0)
        XCTAssertEqual(revertedDose, 18.0)
        XCTAssertEqual(reverted.finalWeight, 36.0)
    }
}
