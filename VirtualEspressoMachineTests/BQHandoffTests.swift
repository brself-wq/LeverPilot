//
//  BQHandoffTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
@testable import VirtualEspressoMachine

@MainActor
final class BQHandoffTests: XCTestCase {

    private var coordinator: BQHandoffCoordinator!
    private var testDefaults: UserDefaults!
    private let suiteName = "com.virtualespressomachine.tests.handoff"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)

        coordinator = BQHandoffCoordinator.shared
        coordinator.defaults = testDefaults
        coordinator.openURLHandler = { _ in } // Headless mock: silences system app launching
        coordinator.clearDeliveredLedger()
        coordinator.resetState()
    }

    override func tearDown() {
        coordinator.defaults = .standard
        coordinator.openURLHandler = nil
        coordinator.resetState()
        coordinator.clearDeliveredLedger()
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Initial State
    
    func test_initialStateIsIdle() {
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - Delivery Ledger Persistence

    func test_deliveryLedger_marksAndQueriesSuccessfully() {
        let shotID = "test-shot-123"
        XCTAssertFalse(coordinator.isDelivered(shotId: shotID))

        coordinator.markDelivered(shotId: shotID)
        XCTAssertTrue(coordinator.isDelivered(shotId: shotID))

        let restored = testDefaults.stringArray(forKey: "bq.delivered_shot_ids") ?? []
        XCTAssertTrue(restored.contains(shotID))
    }

    func test_deliveryLedger_clearAllRemovesDeliveredIDs() {
        let shotID = "test-shot-abc"
        coordinator.markDelivered(shotId: shotID)
        XCTAssertTrue(coordinator.isDelivered(shotId: shotID))

        coordinator.clearDeliveredLedger()
        XCTAssertFalse(coordinator.isDelivered(shotId: shotID))
    }

    // MARK: - State Machine Transitions

    func test_handoffTransitionsToTransferring_andThenTransferredOnDeliveryHook() async {
        let dummyShot = ShotRecord(
            id: "verified-shot-99",
            profileId: "profile-test",
            samples: [ShotSample(timestamp: 0.0, pressure: 2.0, flow: 1.0, weight: 0.0)]
        )

        var capturedURL: URL?
        coordinator.openURLHandler = { capturedURL = $0 }

        // 1. Dispatch handoff
        coordinator.addBrewToBeanconqueror(shareCode: "valid-share-code", shot: dummyShot)
        XCTAssertEqual(coordinator.state, .transferring)
        XCTAssertEqual(
            capturedURL?.absoluteString,
            "beanconqueror://int/bean/valid-share-code/START_BREW_CHOOSE_PREPARATION"
        )

        // Allow staging task to complete
        try? await Task.sleep(nanoseconds: 20_000_000)

        // 2. Simulate BQ consuming the payload via MeticulousServer loopback hook
        await MeticulousServer.shared.simulateShotDelivered()

        // Allow MainActor handoff update to execute
        try? await Task.sleep(nanoseconds: 20_000_000)

        // 3. Must transition to .transferred and record in the ledger
        XCTAssertEqual(coordinator.state, .transferred)
        XCTAssertTrue(coordinator.isDelivered(shotId: dummyShot.id))
    }

    func test_resetStateReturnsToIdle() {
        let dummyShot = ShotRecord(
            id: "shot-reset-test",
            profileId: "profile-test",
            samples: []
        )

        coordinator.addBrewToBeanconqueror(shareCode: "code", shot: dummyShot)
        XCTAssertEqual(coordinator.state, .transferring)

        coordinator.resetState()
        XCTAssertEqual(coordinator.state, .idle)
    }
}

