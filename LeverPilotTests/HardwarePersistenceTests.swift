import XCTest
import EspressoBLE
@testable import LeverPilot

final class HardwarePersistenceTests: XCTestCase {
    
    private var testDefaults: UserDefaults!
    private let suiteName = "com.virtualespressomachine.tests"
    
    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }
    
    // MARK: - Persistence Round-Trip Test
    
    func testDeviceUUIDPersistenceAndRehydration() {
        let scaleID = UUID()
        let pressureID = UUID()
        
        // 1. Simulate saving paired devices to UserDefaults
        testDefaults.set(scaleID.uuidString, forKey: "ble.device.\(BLEDeviceRole.scale.rawValue)")
        testDefaults.set(pressureID.uuidString, forKey: "ble.device.\(BLEDeviceRole.pressure.rawValue)")
        
        // 2. Simulate rehydration logic
        var restored: [BLEDeviceRole: UUID] = [:]
        for role in BLEDeviceRole.allCases {
            if let raw = testDefaults.string(forKey: "ble.device.\(role.rawValue)"),
               let uuid = UUID(uuidString: raw) {
                restored[role] = uuid
            }
        }
        
        XCTAssertEqual(restored[.scale], scaleID)
        XCTAssertEqual(restored[.pressure], pressureID)
        
        // 3. Verify seeding into manager
        let manager = EspressoBLEManager(savedDevices: restored)
        XCTAssertEqual(manager.slots[.scale]?.id, scaleID)
        XCTAssertEqual(manager.slots[.pressure]?.id, pressureID)
        
        // 4. Simulate forget action
        testDefaults.removeObject(forKey: "ble.device.\(BLEDeviceRole.scale.rawValue)")
        let recheckedRaw = testDefaults.string(forKey: "ble.device.\(BLEDeviceRole.scale.rawValue)")
        XCTAssertNil(recheckedRaw)
    }
}
