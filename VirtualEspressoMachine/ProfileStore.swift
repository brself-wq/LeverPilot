//
//  ProfileStore.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/3/26.
//

import Foundation
import Observation
import MeticulousProfile

/// A catalog container holding available profiles, responsible for loading and variable resolution.
/// Owned directly by the VirtualEspressoMachine.
@Observable
@MainActor
public final class ProfileStore {
    
    /// The collection of available profiles in this machine's catalog
    public var profiles: [Profile] = []
    
    /// Latest error encountered during disk or parsing operations
    public var lastErrorMessage: String? = nil
    
    /// Standard initializer: loads from the app bundle with a built-in fallback
    public init(bundle: Bundle = .main) {
        loadBundledProfiles(from: bundle)
        
        // Zero-setup fallback: if no JSON files exist in the bundle yet, inject a working default
        if profiles.isEmpty {
            let defaultProfile = createDefaultProfile()
            self.profiles = [defaultProfile]
        }
    }
    
    /// Testing / Preview initializer: inject an explicit list of profiles
    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
    
    // MARK: - Query & Resolution
    
    /// Look up a profile in the catalog by its unique identifier
    public func profile(withID id: String) -> Profile? {
        profiles.first(where: { $0.id == id })
    }
    
    /// Resolves all `$variables` in a profile into concrete numeric values.
    /// Called by the machine when arming or selecting a profile for execution.
    public func resolveForExecution(_ profile: Profile) throws -> Profile {
        do {
            return try processProfileVariables(originalProfile: profile)
        } catch {
            self.lastErrorMessage = "Failed to resolve profile variables: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - File & Bundle Loading
    
    /// Scans a bundle for all `.json` files and appends valid Meticulous profiles to the catalog
    public func loadBundledProfiles(from bundle: Bundle = .main) {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return
        }
        
        var loaded: [Profile] = []
        for url in urls {
            do {
                let profile = try loadProfile(from: url)
                loaded.append(profile)
            } catch {
                print("[ProfileStore] Skipped non-profile JSON at \(url.lastPathComponent): \(error)")
            }
        }
        
        if !loaded.isEmpty {
            self.profiles = loaded
        }
    }
    
    /// Reads and parses a single Profile from a file URL
    public func loadProfile(from fileURL: URL) throws -> Profile {
        let data = try Data(contentsOf: fileURL)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ProfileError.format("File at \(fileURL.lastPathComponent) is not valid UTF-8 text.")
        }
        return try parseProfile(from: jsonString)
    }
    
    // MARK: - Default Factory Fallback
    
    private func createDefaultProfile() -> Profile {
        let piStage = Stage(
            name: "Dynamic PI",
            key: "stage_pi",
            type: .flow,
            dynamics: Dynamics(
                points: [Point(0.0, 12.0), Point(6.0, 12.0)],
                over: .time,
                interpolation: .linear
            ),
            exitTriggers: [
                ExitTrigger(type: .time, value: 6.0),
                ExitTrigger(type: .weight, value: 4.0),
                ExitTrigger(type: .pressure, value: 2.0)
            ],
            limits: [
                Limit(type: .pressure, value: 9.0)
            ]
        )
        
        let extractionStage = Stage(
            name: "Main Flow",
            key: "stage_extract",
            type: .flow,
            dynamics: Dynamics(
                points: [Point(0.0, 2.5), Point(30.0, 2.5)],
                over: .time,
                interpolation: .linear
            ),
            exitTriggers: [
                ExitTrigger(type: .time, value: 30.0)
            ],
            limits: [
                Limit(type: .pressure, value: 6.0)
            ]
        )
        
        return Profile(
            name: "Default Dynamic Lever",
            id: "default-lever-01",
            display: Display(
                shortDescription: "Fast saturation pre-infusion with 6-bar limited flow decline."
            ),
            author: "System",
            authorId: "local",
            temperature: 88.0,
            finalWeight: 45.0,
            variables: [],
            stages: [piStage, extractionStage]
        )
    }
}
