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
                guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    fatalError("CRITICAL: Application Support directory is unavailable.")
                }
                self.userProfilesDirectory = appSupport
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
    
    // MARK: - Safe Path Resolution
    
    /// Ensures that a profile ID strictly resolves to a file inside the user profiles directory.
    private func safeFileURL(for profileID: String) throws -> URL {
        guard let dir = userProfilesDirectory else {
            throw ProfileError.format("Cannot resolve disk path while operating in in-memory mode.")
        }
        
        // Strip any directory path components or traversal tokens
        let sanitizedID = (profileID as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        
        guard !sanitizedID.isEmpty, sanitizedID != ".", sanitizedID != ".." else {
            throw ProfileError.format("Invalid profile identifier: '\(profileID)'")
        }
        
        let candidateURL = dir.appendingPathComponent("\(sanitizedID).json").standardizedFileURL
        let canonicalDir = dir.standardizedFileURL
        
        // Verify candidate stays strictly within the designated profiles root directory
        guard candidateURL.path().hasPrefix(canonicalDir.path()) else {
            throw ProfileError.format("Sandbox boundary violation: path traversal detected.")
        }
        
        return candidateURL
    }
    
    // MARK: - CRUD Operations
    
    public func save(profile: Profile) throws {
        // If in-memory, just update and return
        guard case .disk = mode, userProfilesDirectory != nil else {
            updateInMemory(profile: profile)
            return
        }
        
        let fileURL = try safeFileURL(for: profile.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
            updateInMemory(profile: profile)
        } catch {
            lastErrorMessage = "Save failed: \(error.localizedDescription)"
            throw error
        }
    }
    
    private func updateInMemory(profile: Profile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
            sortProfiles()
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
        
        guard case .disk = mode else { return }
        let fileURL = try safeFileURL(for: profileId)
        if fileManager.fileExists(atPath: fileURL.path()) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    /// Purges all user edits and restores the pristine factory bundle catalog
    public func resetToFactoryDefaults(bundle: Bundle = .main) throws {
        if case .disk = mode, let dir = userProfilesDirectory {
            if fileManager.fileExists(atPath: dir.path()) {
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
                do {
                    let p = try loadProfile(from: url)
                    loaded.append(p)
                    factoryIDs.insert(p.id)
                } catch {
                    print("⚠️ Skipped factory preset '\(url.lastPathComponent)' due to error: \(error)")
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
        // Handle security-scoped document access safely (e.g. UIDocumentPicker / .fileImporter)
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let data = try Data(contentsOf: fileURL)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ProfileError.format("File at \(fileURL.lastPathComponent) is not valid UTF-8.")
        }
        return try parseProfile(from: jsonString)
    }
    
    private func ensureDirectoryExists() {
        guard let dir = userProfilesDirectory else { return }
        if !fileManager.fileExists(atPath: dir.path()) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                self.lastErrorMessage = "Failed to initialize profiles directory: \(error.localizedDescription)"
            }
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
