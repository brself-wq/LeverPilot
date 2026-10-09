//
//  MeticulousTransponder.swift
//  LeverPilot
//

import Foundation
import SwiftUI
import Combine

public enum MeticulousTransponderState: Equatable, Sendable {
    case disabled   // Server is switched OFF in Settings
    case standby    // Server is listening on port, no client activity in >2 mins
    case active     // Client connected or polled within the last 2 minutes
}

@MainActor
public final class MeticulousTransponder: ObservableObject {
    public static let shared = MeticulousTransponder()

    @Published public private(set) var state: MeticulousTransponderState = .standby
    
    private var lastActivityDate: Date = .distantPast
    private var decayTimer: AnyCancellable?

    private init() {
        // Checks every 10 seconds to smoothly decay active state to standby after 120s of silence
        decayTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkDecay()
            }
    }

    public func setDisabled() {
        self.state = .disabled
    }

    public func setStandby() {
        self.state = .standby
    }

    public func recordActivity() {
        self.lastActivityDate = Date()
        if self.state != .active {
            self.state = .active
        }
    }

    private func checkDecay() {
        guard state == .active else { return }
        if Date().timeIntervalSince(lastActivityDate) >= 120.0 {
            self.state = .standby
        }
    }
}
