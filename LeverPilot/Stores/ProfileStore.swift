//
//  ProfileStore.swift
//  LeverPilot
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
    
    private static let overridesStorageKey = "profile_dial_in_overrides"
    
    public var profiles: [Profile] = []
    public private(set) var factoryProfileIDs: Set<String> = []
    public var lastErrorMessage: String? = nil
    
    /// Active dial-in overrides indexed by profile UUID.
    public private(set) var overrides: [String: ProfileOverride] = [:]
    
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
                guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    fatalError("CRITICAL: Documents directory is unavailable.")
                }
                let targetDir = docs.appendingPathComponent("Profiles", isDirectory: true)
                
                // One-time silent migration from Application Support -> Documents/Profiles
                if let legacyAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let oldDir = legacyAppSupport.appendingPathComponent("Profiles", isDirectory: true)
                    if fileManager.fileExists(atPath: oldDir.path()) && !fileManager.fileExists(atPath: targetDir.path()) {
                        try? fileManager.moveItem(at: oldDir, to: targetDir)
                    }
                }
                
                self.userProfilesDirectory = targetDir
            }
            ensureDirectoryExists()
            loadOverrides()
            loadAllProfiles(bundle: bundle)
            
        case .inMemory:
            self.userProfilesDirectory = nil
            loadOverrides()
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
    
    // MARK: - Dial-In Configuration Overrides
    
    public func hasOverride(for profileID: String) -> Bool {
        overrides[profileID] != nil
    }
    
    public func override(for profileID: String) -> ProfileOverride? {
        overrides[profileID]
    }
    
    /// Resolves the effective execution profile and dose for a given base profile.
    /// If an override exists in UserDefaults/memory, it bakes the sparse targets onto a copy of the base profile.
    public func effectiveProfile(for base: Profile, fallbackDose: Double) -> (profile: Profile, dose: Double) {
        guard let dialIn = overrides[base.id] else {
            return (base, fallbackDose)
        }
        return dialIn.applying(to: base, fallbackDose: fallbackDose)
    }
    
    /// Persists a new or updated dial-in override for a profile ID.
    /// If the override is empty (no fields changed), it automatically clears any existing record.
    public func saveOverride(_ override: ProfileOverride, for profileID: String) {
        if override.isEmpty {
            clearOverride(for: profileID)
            return
        }
        overrides[profileID] = override
        persistOverrides()
    }
    
    /// Removes the override for the given profile ID, reverting it to author factory specs.
    public func clearOverride(for profileID: String) {
        guard overrides.removeValue(forKey: profileID) != nil else { return }
        persistOverrides()
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
        clearOverride(for: profileId)
        
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
        overrides.removeAll()
        persistOverrides()
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
        
        // Reconcile and prune any lingering overrides for deleted profile IDs
        reconcileOrphanedOverrides(validIDs: Set(loaded.map(\.id)))
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
    
    // MARK: - Overrides Persistence & Garbage Collection
    
    private func loadOverrides() {
        guard case .disk = mode else {
            self.overrides = [:]
            return
        }
        guard let data = UserDefaults.standard.data(forKey: Self.overridesStorageKey) else {
            self.overrides = [:]
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: ProfileOverride].self, from: data)
            self.overrides = decoded
        } catch {
            print("⚠️ [ProfileStore] Failed to decode dial-in overrides: \(error)")
            self.overrides = [:]
        }
    }
    
    private func persistOverrides() {
        guard case .disk = mode else { return }
        do {
            let data = try JSONEncoder().encode(self.overrides)
            UserDefaults.standard.set(data, forKey: Self.overridesStorageKey)
        } catch {
            print("❌ [ProfileStore] Failed to persist dial-in overrides: \(error)")
        }
    }
    
    /// Audits stored overrides against current catalog IDs, pruning and logging any orphaned entries.
    private func reconcileOrphanedOverrides(validIDs: Set<String>) {
        let orphanedIDs = overrides.keys.filter { !validIDs.contains($0) }
        guard !orphanedIDs.isEmpty else { return }
        
        for id in orphanedIDs {
            overrides.removeValue(forKey: id)
            print("🧹 [ProfileStore] Pruned orphaned dial-in override for deleted profile: '\(id)'")
        }
        persistOverrides()
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
