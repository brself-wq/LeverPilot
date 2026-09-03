//
//  MeticulousProfile.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/2/26.
//


import Foundation

/// Lightweight stub of MeticulousProfile for early machine workflow prototyping.
public struct MeticulousProfile: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let finalWeight: Double
    
    public init(
        id: String = "classic-espresso",
        name: String = "Classic 2:1 Espresso",
        finalWeight: Double = 36.0
    ) {
        self.id = id
        self.name = name
        self.finalWeight = finalWeight
    }
    
    public static let mock = MeticulousProfile()
}