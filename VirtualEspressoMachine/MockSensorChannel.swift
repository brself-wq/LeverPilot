//
//  MockSensorChannel.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/2/26.
//


import Foundation
import Observation

// MARK: - Mock Sensor Channel

public final class MockSensorChannel: SensorChannel, @unchecked Sendable {
    public let key: SensorKey
    public let unit: String
    public var currentValue: Double?
    public var isConnected: Bool = true
    
    public init(key: SensorKey, unit: String, initialValue: Double? = 0.0) {
        self.key = key
        self.unit = unit
        self.currentValue = initialValue
    }
}

// MARK: - Mock Sensor Array

public final class MockSensorArray: SensorArrayProtocol, @unchecked Sendable {
    private var channels: [SensorKey: MockSensorChannel] = [:]
    
    public init() {
        channels[.pressure] = MockSensorChannel(key: .pressure, unit: "bar")
        channels[.weight] = MockSensorChannel(key: .weight, unit: "g")
        channels[.flow] = MockSensorChannel(key: .flow, unit: "g/s")
        channels[.power] = MockSensorChannel(key: .power, unit: "%", initialValue: 100.0)
    }
    
    public func channel(for key: SensorKey) -> (any SensorChannel)? {
        channels[key]
    }
    
    public subscript(key: SensorKey) -> (any SensorChannel)? {
        channels[key]
    }
    
    public func setReading(_ value: Double, for key: SensorKey) {
        channels[key]?.currentValue = value
    }
    
    public func captureSnapshot(at timestamp: TimeInterval, state: MachineState) -> MachineFrame {
        var readings: [SensorKey: Double] = [:]
        for (key, channel) in channels {
            if let val = channel.currentValue {
                readings[key] = val
            }
        }
        return MachineFrame(timestamp: timestamp, state: state, readings: readings)
    }
}
