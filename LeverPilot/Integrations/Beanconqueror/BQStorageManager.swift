//
//  BQStorageManager.swift
//  LeverPilot
//

import Foundation
import SwiftUI
import Combine

@MainActor
public final class BQStorageManager: ObservableObject {
    public static let shared = BQStorageManager()

    @Published public var beans: [BQBean] = []
    @Published public var syncStatusMessage: String = "No folder selected"
    @Published public var isConfigured: Bool = false
    @Published public var isSyncing: Bool = false

    private let bookmarkKey = "BQ_Folder_Security_Bookmark"

    private init() {
        restoreBookmarkAndSync()
    }

    public func saveFolderBookmark(url: URL) {
        // Ephemeral scope solely to generate and persist the bookmark data
        guard url.startAccessingSecurityScopedResource() else {
            syncStatusMessage = "Failed to access folder security scope"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try url.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            isConfigured = true
            syncStatusMessage = "Folder linked. Reading archive..."
            syncArchive(folderURL: url)
        } catch {
            syncStatusMessage = "Bookmark error: \(error.localizedDescription)"
        }
    }

    public func refresh() {
        restoreBookmarkAndSync()
    }

    private func restoreBookmarkAndSync() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            syncStatusMessage = "Beanconqueror folder not linked"
            isConfigured = false
            return
        }

        var isStale = false
        do {
            let folderURL = try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                saveFolderBookmark(url: folderURL)
                return
            }

            isConfigured = true
            syncArchive(folderURL: folderURL)
        } catch {
            syncStatusMessage = "Failed to resolve folder: \(error.localizedDescription)"
            isConfigured = false
        }
    }

    private func syncArchive(folderURL: URL) {
        isSyncing = true
        syncStatusMessage = "Syncing beans..."

        // Decompress and parse off the main actor
        Task.detached(priority: .userInitiated) {
            // 1. Maintain security scope across the entire file I/O lifecycle
            let isAccessing = folderURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            guard isAccessing else {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatusMessage = "Permission denied to Beanconqueror folder"
                }
                return
            }

            let directJsonURL = folderURL.appendingPathComponent("Beanconqueror.json")
            let zipURL = folderURL.appendingPathComponent("Beanconqueror.zip")

            var payloadData: Data? = nil

            // Check 1: Direct uncompressed JSON file (if present)
            if FileManager.default.fileExists(atPath: directJsonURL.path) {
                payloadData = try? Data(contentsOf: directJsonURL)
            }

            // Check 2: ZIP archive extraction
            if payloadData == nil && FileManager.default.fileExists(atPath: zipURL.path) {
                let extractedFiles = MicroZipReader.extractJSONFiles(from: zipURL)
                payloadData = extractedFiles.first(where: { $0.key.localizedCaseInsensitiveContains("beanconqueror.json") })?.value ?? extractedFiles.values.first
            }

            guard let rawData = payloadData else {
                await MainActor.run {
                    self.isSyncing = false
                    if !FileManager.default.fileExists(atPath: zipURL.path) && !FileManager.default.fileExists(atPath: directJsonURL.path) {
                        self.syncStatusMessage = "Beanconqueror.zip not found in folder"
                    } else {
                        self.syncStatusMessage = "No JSON found inside Beanconqueror archive"
                    }
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                let export = try decoder.decode(BQExport.self, from: rawData)
                let activeBeans = export.beans
                    .filter(\.isActive)
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                await MainActor.run {
                    self.beans = activeBeans
                    self.isSyncing = false
                    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    self.syncStatusMessage = "Synced at \(timestamp) (\(activeBeans.count) active beans)"
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatusMessage = "Parse error: \(error.localizedDescription)"
                }
            }
        }
    }
}
