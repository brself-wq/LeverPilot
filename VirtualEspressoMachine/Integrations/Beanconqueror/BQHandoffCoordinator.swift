//
//  BQHandoffCoordinator.swift
//  VirtualEspressoMachine
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
public final class BQHandoffCoordinator {
    public static let shared = BQHandoffCoordinator()
    
    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var fallbackItem: DispatchWorkItem?

    private init() {}

    /// Stages the completed ShotRecord, starts background assertion (iOS), and deep-links into Beanconqueror's Add Brew.
    public func addBrewToBeanconqueror(shareCode: String, shot: ShotRecord) {
        // 1. Stage the shot onto MeticulousServer
        MeticulousServer.shared.stageShot(shot)

        // 2. Set up delivery completion hook
        MeticulousServer.shared.onShotDelivered = { [weak self] in
            print("[BQHandoffCoordinator] Telemetry served to BQ. Ending background task in 2.0s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.endBackgroundTask()
            }
        }

        let targetURLString = "beanconqueror://int/bean/\(shareCode)/START_BREW_CHOOSE_PREPARATION"
        guard let bqURL = URL(string: targetURLString) else {
            print("[BQHandoffCoordinator] Invalid URL: \(targetURLString)")
            return
        }

        // 3. Begin background execution assertion (iOS)
        beginBackgroundTask()

        // 4. Dispatch deep-link
        #if canImport(UIKit)
        UIApplication.shared.open(bqURL, options: [:]) { [weak self] success in
            if !success {
                print("[BQHandoffCoordinator] Failed to launch Beanconqueror: \(targetURLString)")
                self?.endBackgroundTask()
            }
        }
        #elseif canImport(AppKit)
        let success = NSWorkspace.shared.open(bqURL)
        if !success {
            print("[BQHandoffCoordinator] Failed to launch Beanconqueror: \(targetURLString)")
            self.endBackgroundTask()
        }
        #endif

        // 5. Watchdog failsafe timer: terminate background task if user abandons
        fallbackItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            print("[BQHandoffCoordinator] Watchdog expired. Ending background assertion.")
            self?.endBackgroundTask()
        }
        self.fallbackItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0, execute: item)
    }

    public func beginBackgroundTask() {
        #if canImport(UIKit)
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BQAddBrewHandoff") { [weak self] in
            print("[BQHandoffCoordinator] iOS watchdog expired background execution.")
            self?.endBackgroundTask()
        }
        #endif
    }

    public func endBackgroundTask() {
        fallbackItem?.cancel()
        fallbackItem = nil
        MeticulousServer.shared.onShotDelivered = nil

        #if canImport(UIKit)
        if backgroundTaskID != .invalid {
            print("[BQHandoffCoordinator] Background assertion ended cleanly.")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif
    }
}
