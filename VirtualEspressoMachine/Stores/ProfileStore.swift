//
//  ProfileStore.swift
//  VirtualEspressoMachine
//

import Foundation
import Observation
import MeticulousProfile

@Observable
@MainActor
public final class ProfileStore {
    
    public enum StorageMode: Sendable {
        case disk(directory: URL? = nil)
        case inMemory
    }
    
    public var profiles: [Profile] = []
    public private(set) var factoryProfileIDs: Set<String> = []
    public var lastErrorMessage: String? = nil
    
    private let mode: StorageMode
    private let fileManager = FileManager.default
    private let userProfilesDirectory: URL?
    
    public init(mode: StorageMode = .disk(), bundle: Bundle = .main) {
        self.mode = mode
        
        switch mode {
        case .disk(let customURL):
            if let customURL {
                self.userProfilesDirectory = customURL
            } else {
                let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                self.userProfilesDirectory = appSupport
                    .appendingPathComponent("VirtualEspressoMachine", isDirectory: true)
                    .appendingPathComponent("Profiles", isDirectory: true)
            }
            ensureDirectoryExists()
            loadAllProfiles(bundle: bundle)
            
        case .inMemory:
            self.userProfilesDirectory = nil
            loadBundledOnly(bundle: bundle)
        }
    }
    
    // MARK: - Factory vs User Checks
    
    public func isFactoryPreset(_ profile: Profile) -> Bool {
        factoryProfileIDs.contains(profile.id)
    }
    
    // MARK: - Query & Resolution
    
    public func profile(withID id: String) -> Profile? {
        profiles.first(where: { $0.id == id })
    }
    
    public func resolveForExecution(_ profile: Profile) throws -> Profile {
        do {
            return try processProfileVariables(originalProfile: profile)
        } catch {
            self.lastErrorMessage = "Failed to resolve profile variables: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - CRUD Operations
    
    public func save(profile: Profile) throws {
        // Update in-memory array
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
            sortProfiles()
        }
        
        // If in-memory, we are done
        guard case .disk = mode, let dir = userProfilesDirectory else { return }
        
        let fileURL = dir.appendingPathComponent("\(profile.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastErrorMessage = "Save failed: \(error.localizedDescription)"
            throw error
        }
    }
    
    public func duplicate(profile: Profile) throws -> Profile {
        var copy = profile
        copy.id = UUID().uuidString
        copy.name = "\(profile.name) (Copy)"
        try save(profile: copy)
        return copy
    }
    
    public func delete(profileId: String) throws {
        guard !factoryProfileIDs.contains(profileId) else {
            throw ProfileError.format("Cannot delete factory bundled profile.")
        }
        
        profiles.removeAll(where: { $0.id == profileId })
        
        guard case .disk = mode, let dir = userProfilesDirectory else { return }
        let fileURL = dir.appendingPathComponent("\(profileId).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    /// Purges all user edits and restores the pristine factory bundle catalog
    public func resetToFactoryDefaults(bundle: Bundle = .main) throws {
        if case .disk = mode, let dir = userProfilesDirectory {
            if fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
                ensureDirectoryExists()
            }
        }
        loadAllProfiles(bundle: bundle)
    }
    
    // MARK: - Loading & Layering (Bundle -> Disk Overlay)
    
    public func loadAllProfiles(bundle: Bundle = .main) {
        var loaded: [Profile] = []
        var factoryIDs: Set<String> = []
        
        // 1. Layer 1: Read Factory Presets from Bundle
        if let bundleURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            for url in bundleURLs {
                if let p = try? loadProfile(from: url) {
                    loaded.append(p)
                    factoryIDs.insert(p.id)
                }
            }
        }
        
        // 2. Layer 2: Overlay User Edits / Additions from Application Support
        if case .disk = mode, let dir = userProfilesDirectory,
           let userFiles = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in userFiles where url.pathExtension.lowercased() == "json" {
                if let userProfile = try? loadProfile(from: url) {
                    // Precedence: User override replaces factory preset with matching ID
                    if let existingIdx = loaded.firstIndex(where: { $0.id == userProfile.id }) {
                        loaded[existingIdx] = userProfile
                    } else {
                        loaded.append(userProfile)
                    }
                }
            }
        }
        
        if loaded.isEmpty {
            let fallback = createDefaultProfile()
            loaded = [fallback]
            factoryIDs.insert(fallback.id)
        }
        
        self.factoryProfileIDs = factoryIDs
        self.profiles = loaded
        sortProfiles()
    }
    
    private func loadBundledOnly(bundle: Bundle) {
        loadAllProfiles(bundle: bundle)
    }
    
    public func loadProfile(from fileURL: URL) throws -> Profile {
        let data = try Data(contentsOf: fileURL)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ProfileError.format("File at \(fileURL.lastPathComponent) is not valid UTF-8.")
        }
        return try parseProfile(from: jsonString)
    }
    
    private func ensureDirectoryExists() {
        guard let dir = userProfilesDirectory else { return }
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    private func sortProfiles() {
        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private func createDefaultProfile() -> Profile {
        Profile(
            name: "Default Dynamic Lever",
            id: "default-lever-01",
            author: "System",
            authorId: "local",
            temperature: 88.0,
            finalWeight: 45.0,
            variables: [],
            stages: []
        )
    }
}
