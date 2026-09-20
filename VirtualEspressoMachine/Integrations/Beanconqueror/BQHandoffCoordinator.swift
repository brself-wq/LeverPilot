//
//  BQHandoffCoordinator.swift
//  VirtualEspressoMachine
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Explicit Handoff Lifecycle State

public enum HandoffState: Equatable, Sendable {
    case idle
    case transferring
    case transferred
    case timedOut
}

@MainActor
public final class BQHandoffCoordinator: ObservableObject {
    public static let shared = BQHandoffCoordinator()

    // MARK: - Observable Handoff State
    @Published public private(set) var state: HandoffState = .idle

    // MARK: - Delivery Ledger Storage
    private let deliveredShotsKey = "bq.delivered_shot_ids"
    public var defaults: UserDefaults = .standard

    /// Optional injection hook for headless testing; if nil, dispatches to system.
    public var openURLHandler: (@MainActor (URL) -> Void)? = nil

    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var fallbackItem: DispatchWorkItem?

    private init() {}

    // MARK: - Delivery Ledger Queries & Mutations

    private var deliveredShotIDs: Set<String> {
        get {
            Set(defaults.stringArray(forKey: deliveredShotsKey) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: deliveredShotsKey)
        }
    }

    public func isDelivered(shotId: String) -> Bool {
        deliveredShotIDs.contains(shotId)
    }

    public func markDelivered(shotId: String) {
        var current = deliveredShotIDs
        current.insert(shotId)
        deliveredShotIDs = current
    }

    public func clearDeliveredLedger() {
        defaults.removeObject(forKey: deliveredShotsKey)
    }

    // MARK: - Lifecycle & Dispatch

    /// Stages the completed ShotRecord, transitions to .transferring, starts background assertion (iOS),
    /// and deep-links into Beanconqueror's Add Brew.
    public func addBrewToBeanconqueror(shareCode: String, shot: ShotRecord) {
        guard state != .transferring && state != .transferred else { return }

        state = .transferring

        // 1. Stage the shot onto MeticulousServer and wire callback (Consistent [weak self] capture)
        Task { [weak self] in
            await MeticulousServer.shared.stageShot(shot)
            await MeticulousServer.shared.setOnShotDelivered { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("[BQHandoffCoordinator] Telemetry served to BQ. Updating ledger and scheduling end of background task...")
                    self.markDelivered(shotId: shot.id)
                    self.state = .transferred

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.endBackgroundTask()
                    }
                }
            }
        }

        let targetURLString = "beanconqueror://int/bean/\(shareCode)/START_BREW_CHOOSE_PREPARATION"
        guard let bqURL = URL(string: targetURLString) else {
            print("[BQHandoffCoordinator] Invalid URL: \(targetURLString)")
            state = .timedOut
            return
        }

        // 2. Begin background execution assertion (iOS)
        beginBackgroundTask()

        // 3. Dispatch deep-link (or headless test hook)
        if let openURLHandler = openURLHandler {
            openURLHandler(bqURL)
            return
        }

        #if canImport(UIKit)
        UIApplication.shared.open(bqURL, options: [:]) { [weak self] success in
            if !success {
                print("[BQHandoffCoordinator] Failed to launch Beanconqueror: \(targetURLString)")
                self?.state = .timedOut
                self?.endBackgroundTask()
            }
        }
        #elseif canImport(AppKit)
        let success = NSWorkspace.shared.open(bqURL)
        if !success {
            print("[BQHandoffCoordinator] Failed to launch Beanconqueror: \(targetURLString)")
            self.state = .timedOut
            self.endBackgroundTask()
        }
        #endif

        // 4. Watchdog failsafe timer: transition to .timedOut if user abandons
        fallbackItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("[BQHandoffCoordinator] Watchdog expired. Ending background assertion.")
            if self.state == .transferring {
                self.state = .timedOut
            }
            self.endBackgroundTask()
        }
        self.fallbackItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0, execute: item)
    }

    public func resetState() {
        fallbackItem?.cancel()
        fallbackItem = nil
        endBackgroundTask()
        state = .idle
    }

    public func beginBackgroundTask() {
#if canImport(UIKit)
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BQAddBrewHandoff") { [weak self] in
            print("[BQHandoffCoordinator] iOS watchdog expired background execution.")
            self?.endBackgroundTask()
        }
#endif
    }

    public func endBackgroundTask() {
        fallbackItem?.cancel()
        fallbackItem = nil
        Task {
            await MeticulousServer.shared.setOnShotDelivered(nil)
        }

        #if canImport(UIKit)
        if backgroundTaskID != .invalid {
            print("[BQHandoffCoordinator] Background assertion ended cleanly.")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif
    }
}
