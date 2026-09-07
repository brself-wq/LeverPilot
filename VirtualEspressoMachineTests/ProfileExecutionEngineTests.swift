//
//  ProfileExecutionEngineTests.swift
//  VirtualEspressoMachineTests
//
//  Created by Ben Self on 9/6/26.
//

import XCTest
import MeticulousProfile
@testable import VirtualEspressoMachine

final class ProfileExecutionEngineTests: XCTestCase {

    var engine: ProfileExecutionEngine!

    override func setUp() {
        super.setUp()
        engine = ProfileExecutionEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Firmware Parity: Stage Time Trigger Tests

    @MainActor
    func test_bloomStage_doesNotPrematurelyCutoffAtAbsoluteShotTime() throws {
        let profileStore = ProfileStore()

        guard let profile = profileStore.profiles.first(where: {
            $0.id.localizedCaseInsensitiveContains("nutcracker") ||
            $0.name.localizedCaseInsensitiveContains("nutcracker")
        }) else {
            XCTFail("Chocolate Nutcracker profile not found in ProfileStore. Available: \(profileStore.profiles.map(\.name))")
            return
        }

        XCTAssertGreaterThan(profile.stages.count, 1, "Profile must have at least 2 stages")
        let bloomStage = profile.stages[1]

        let triggers = try XCTUnwrap(bloomStage.exitTriggers, "Bloom stage must have exit triggers decoded")
        XCTAssertFalse(triggers.isEmpty, "Bloom stage must have at least one exit trigger")

        // Preinfusion ended at 5.0 seconds
        let baseline = StageBaseline(startTime: 5.0, startWeight: 2.0)

        // 1. Tick at total shot time = 6.0s (only 1.0s elapsed in Bloom)
        let frameAt1sOfBloom = MachineFrame(
            timestamp: 6.0,
            state: .extracting,
            readings: [
                .time: 6.0,
                .pressure: 0.0,
                .flow: 0.0,
                .weight: 2.0,
                .power: 100.0
            ]
        )

        let resultAt1s = engine.evaluate(
            stage: bloomStage,
            stageIndex: 1,
            totalStages: profile.stages.count,
            frame: frameAt1sOfBloom,
            baseline: baseline,
            finalWeightTarget: profile.finalWeight
        )

        XCTAssertFalse(
            resultAt1s.shouldAdvanceStage,
            "Bloom stage must NOT advance at t=6.0s total time when bloom duration is 6.0s and started at t=5.0s."
        )

        // 2. Tick at total shot time = 11.0s (exactly 6.0s elapsed in Bloom: 11.0 - 5.0 = 6.0)
        let frameAt6sOfBloom = MachineFrame(
            timestamp: 11.0,
            state: .extracting,
            readings: [
                .time: 11.0,
                .pressure: 0.0,
                .flow: 0.0,
                .weight: 2.0,
                .power: 100.0
            ]
        )

        let resultAt6s = engine.evaluate(
            stage: bloomStage,
            stageIndex: 1,
            totalStages: profile.stages.count,
            frame: frameAt6sOfBloom,
            baseline: baseline,
            finalWeightTarget: profile.finalWeight
        )

        XCTAssertTrue(
            resultAt6s.shouldAdvanceStage,
            "Bloom stage MUST advance when stage elapsed time reaches the 6.0s duration target."
        )
    }

    // MARK: - Weight Trigger / Final Cutoff Tests

    @MainActor
    func test_weightTrigger_respectsCupTarget() throws {
        let profileStore = ProfileStore()

        guard let profile = profileStore.profiles.first(where: {
            $0.id.localizedCaseInsensitiveContains("nutcracker") ||
            $0.name.localizedCaseInsensitiveContains("nutcracker")
        }) ?? profileStore.profiles.first else {
            XCTFail("No profile loaded in ProfileStore")
            return
        }

        // Test the final stage against the cup target
        let targetStageIndex = profile.stages.count - 1
        let targetStage = profile.stages[targetStageIndex]

        // Determine target weight: either from a stage-level weight trigger or the profile's finalWeight
        let stageWeightTrigger = targetStage.exitTriggers?.first(where: { $0.type == .weight })
        let isRelative = stageWeightTrigger?.relative ?? false
        let baseTarget = stageWeightTrigger?.value.numericValue ?? profile.finalWeight

        let baselineStartWeight = 5.0
        let baseline = StageBaseline(startTime: 10.0, startWeight: baselineStartWeight)
        let cutoffWeight = isRelative ? (baselineStartWeight + baseTarget) : baseTarget

        // Keep localTime at only 0.1s so no secondary time failsafes trigger
        let sampleTime = baseline.startTime + 0.1

        // Case 1: Scale is 2.0g under target
        let frameUnderYield = MachineFrame(
            timestamp: sampleTime,
            state: .extracting,
            readings: [
                .time: sampleTime,
                .pressure: 0.0,
                .flow: 0.0,
                .weight: max(0.0, cutoffWeight - 2.0),
                .power: 100.0
            ]
        )

        let resultUnder = engine.evaluate(
            stage: targetStage,
            stageIndex: targetStageIndex,
            totalStages: profile.stages.count,
            frame: frameUnderYield,
            baseline: baseline,
            finalWeightTarget: profile.finalWeight
        )
        XCTAssertFalse(
            resultUnder.shouldAdvanceStage,
            "Engine should not advance when weight (\(cutoffWeight - 2.0)g) is below target (\(cutoffWeight)g)."
        )

        // Case 2: Scale reaches target
        let frameAtYield = MachineFrame(
            timestamp: sampleTime,
            state: .extracting,
            readings: [
                .time: sampleTime,
                .pressure: 0.0,
                .flow: 0.0,
                .weight: cutoffWeight,
                .power: 100.0
            ]
        )

        let resultAtYield = engine.evaluate(
            stage: targetStage,
            stageIndex: targetStageIndex,
            totalStages: profile.stages.count,
            frame: frameAtYield,
            baseline: baseline,
            finalWeightTarget: profile.finalWeight
        )
        XCTAssertTrue(
            resultAtYield.shouldAdvanceStage,
            "Engine MUST advance when weight reaches target (\(cutoffWeight)g)."
        )
    }
}
