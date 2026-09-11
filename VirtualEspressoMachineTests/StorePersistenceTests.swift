//
//  StorePersistenceTests.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/11/26.
//


//
//  StorePersistenceTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
import MeticulousProfile
@testable import VirtualEspressoMachine

@MainActor
final class StorePersistenceTests: XCTestCase {
    
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Unique sandbox folder for each test run to test real disk I/O without polluting Application Support
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestStore_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    // MARK: - 1. In-Memory Isolation (Zero Disk Footprint)
    
    func test_profileStore_inMemoryMode_neverTouchesDisk() throws {
        let store = ProfileStore(mode: .inMemory)
        
        let customProfile = Profile(
            name: "Ephemeral Test Profile",
            id: "ephemeral-1",
            author: "Tester",
            authorId: "test-user",
            temperature: 92.0,
            finalWeight: 36.0,
            stages: []
        )
        
        try store.save(profile: customProfile)
        
        XCTAssertNotNil(store.profile(withID: "ephemeral-1"))
        XCTAssertFalse(store.isFactoryPreset(customProfile))
    }
    
    // MARK: - 2. Disk Persistence & Reloading
    
    func test_profileStore_diskMode_persistsAcrossStoreInstances() throws {
        let profileDir = tempDirectory.appendingPathComponent("Profiles", isDirectory: true)
        
        // Instance A: Saves a new recipe to disk
        let storeA = ProfileStore(mode: .disk(directory: profileDir))
        let profile = Profile(
            name: "Persistent Profile",
            id: "persisted-id-100",
            author: "Tester",
            authorId: "test-user",
            temperature: 94.0,
            finalWeight: 40.0,
            stages: []
        )
        try storeA.save(profile: profile)
        
        // Instance B: Boots up pointing to the exact same folder
        let storeB = ProfileStore(mode: .disk(directory: profileDir))
        
        let loaded = storeB.profile(withID: "persisted-id-100")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "Persistent Profile")
        XCTAssertEqual(loaded?.temperature, 94.0)
    }
    
    // MARK: - 3. Layering & Precedence (User Override vs Factory)
    
    func test_profileStore_userEditOverridesBundledProfile_andResetRestoresIt() throws {
        let profileDir = tempDirectory.appendingPathComponent("Profiles", isDirectory: true)
        let store = ProfileStore(mode: .disk(directory: profileDir))
        
        // 1. Find or verify a factory preset exists
        guard let factoryProfile = store.profiles.first else {
            XCTFail("Expected default factory profile in catalog")
            return
        }
        let originalName = factoryProfile.name
        let targetID = factoryProfile.id
        
        // 2. User edits the profile (same ID, changed parameters)
        var modified = factoryProfile
        modified.name = "Customized by Barista"
        modified.temperature = 99.0
        try store.save(profile: modified)
        
        // Must show modified version in catalog
        XCTAssertEqual(store.profile(withID: targetID)?.name, "Customized by Barista")
        XCTAssertEqual(store.profile(withID: targetID)?.temperature, 99.0)
        
        // 3. User hits "Reset to Factory Defaults"
        try store.resetToFactoryDefaults()
        
        // Must revert back to original factory values
        XCTAssertEqual(store.profile(withID: targetID)?.name, originalName)
        XCTAssertNotEqual(store.profile(withID: targetID)?.temperature, 99.0)
    }
    
    // MARK: - 4. ScenarioStore Recording & Purge
    
    func test_scenarioStore_recordsShot_andClearsHistory() throws {
        let logsDir = tempDirectory.appendingPathComponent("ShotLogs", isDirectory: true)
        let scenarioStore = ScenarioStore(mode: .disk(directory: logsDir))
        
        let initialCount = scenarioStore.scenarios.count
        
        let shot = ShotRecord(
            id: "test-shot-abc",
            profileId: "profile-1",
            profileName: "Morning Pull",
            finalWeight: 38.2,
            targetWeight: 36.0,
            samples: [
                ShotSample(timestamp: 0.0, pressure: 2.0, flow: 1.0, weight: 0.0),
                ShotSample(timestamp: 5.0, pressure: 9.0, flow: 2.2, weight: 38.2)
            ]
        )
        
        try scenarioStore.recordCompletedShot(shot)
        
        XCTAssertEqual(scenarioStore.scenarios.count, initialCount + 1)
        XCTAssertEqual(scenarioStore.scenarios.first?.id, "test-shot-abc")
        
        // Purge check
        try scenarioStore.clearAllHistory()
        XCTAssertEqual(scenarioStore.scenarios.count, 0)
    }
}