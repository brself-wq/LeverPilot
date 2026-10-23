//
//  MeticulousServer.swift
//  LeverPilot
//

import Foundation
import Network

// MARK: - Lightweight Listing Model

/// Fast decodable struct that extracts only shot header metadata,
/// intentionally skipping heavy time-series `samples` and `profile_snapshot`.
private nonisolated struct ShotRecordListingHeader: Decodable, Sendable {
    let id: String
    let brewTemperature: Double
    let finalWeight: Double
    let profileName: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case brewTemperature = "brew_temperature"
        case finalWeight = "final_weight"
        case profileName = "profile_name"
        case timestamp
    }

    nonisolated func toMeticulousHistoryEntry() -> MeticulousHistoryEntry {
        let profile = MeticulousProfile(
            name: profileName,
            temperature: brewTemperature,
            dbKey: 1
        )

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: timestamp)
        let richTitle = "\(profileName) • \(String(format: "%.1fg", finalWeight)) (\(timeStr))"

        return MeticulousHistoryEntry(
            id: id,
            dbKey: 1,
            time: Int64(timestamp.timeIntervalSince1970),
            name: richTitle,
            profile: profile,
            data: nil
        )
    }
}

/// Actor-isolated HTTP & Socket.IO loopback server emulating the Meticulous machine API.
/// Serves recent shot history directly from disk on demand with re-entrancy protection.
public actor MeticulousServer {
    public static let shared = MeticulousServer()

    public private(set) var isRunning: Bool = false
    public private(set) var serverPort: UInt16 = 8080

    private var isStarting: Bool = false
    private var listener: NWListener?
    private var activeSessionId: String = "bb123"
    private var hasAckedSocketIONamespace: Bool = false

    private init() {}

    // MARK: - Configuration & Lifecycle

    public func configure(port: Int, isEnabled: Bool, isTraceLoggingEnabled: Bool) {
        MeticulousTraceLogger.isEnabled = isTraceLoggingEnabled
        let targetPort = UInt16(clamping: port)
        
        guard isEnabled else {
            self.isStarting = false
            if isRunning || listener != nil {
                stop()
            }
            Task { @MainActor in
                MeticulousTransponder.shared.setDisabled()
            }
            return
        }

        // Re-entrancy guard: if already running or currently negotiating startup on this port, do nothing
        if serverPort == targetPort && (isRunning || isStarting) {
            MeticulousTraceLogger.log("[Server] configure ignored: already \(isRunning ? "running" : "starting") on port \(port)")
            return
        }

        MeticulousTraceLogger.log("[Server] configure(port: \(port), enabled: \(isEnabled)) - starting listener")
        self.isStarting = true
        start(port: targetPort)
    }

    public func start(port: UInt16 = 8080) {
        stop()
        self.isStarting = true
        self.serverPort = port
        self.hasAckedSocketIONamespace = false
        MeticulousTraceLogger.log("[Server] Starting listener on port \(port)...")

        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let newListener = try NWListener(using: params, on: nwPort)
            
            newListener.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleStateUpdate(state, port: port)
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { [weak self] in
                    await self?.handleNewConnection(connection)
                }
            }

            newListener.start(queue: .global(qos: .userInteractive))
            self.listener = newListener
            
            Task { @MainActor in
                MeticulousTransponder.shared.setStandby()
            }
        } catch {
            self.isStarting = false
            self.isRunning = false
            MeticulousTraceLogger.log("[Server] ERROR: Failed to bind NWListener on \(port): \(error)")
        }
    }

    public func stop() {
        self.isStarting = false
        MeticulousTraceLogger.log("[Server] Stopping listener (was running: \(isRunning))...")
        listener?.cancel()
        listener = nil
        isRunning = false
        hasAckedSocketIONamespace = false
        Task { @MainActor in
            MeticulousTransponder.shared.setDisabled()
        }
    }

    #if DEBUG
    public func simulateClientActivity() {
        Task { @MainActor in
            MeticulousTransponder.shared.recordActivity()
        }
    }
    #endif

    // MARK: - Internal Connection Handling

    private func handleStateUpdate(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            self.isStarting = false
            self.isRunning = true
            MeticulousTraceLogger.log("[Server] NWListener READY on 127.0.0.1:\(port)")
            Task { @MainActor in
                MeticulousTransponder.shared.setStandby()
            }
        case .waiting(let error):
            self.isStarting = false
            self.isRunning = false
            MeticulousTraceLogger.log("[Server] NWListener WAITING: \(error)")
        case .failed(let error):
            self.isStarting = false
            self.isRunning = false
            self.listener = nil
            MeticulousTraceLogger.log("[Server] NWListener FAILED: \(error)")
            Task { @MainActor in
                MeticulousTransponder.shared.setDisabled()
            }
        case .cancelled:
            self.isStarting = false
            self.isRunning = false
            self.listener = nil
            MeticulousTraceLogger.log("[Server] NWListener CANCELLED")
            Task { @MainActor in
                MeticulousTransponder.shared.setDisabled()
            }
        default:
            self.isStarting = false
            self.isRunning = false
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let endpoint = "\(connection.endpoint)"
        MeticulousTraceLogger.log("[Connection] Client knocked: accepted from \(endpoint)")

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                MeticulousTraceLogger.log("[Connection \(endpoint)] State -> READY")
            case .waiting(let error):
                MeticulousTraceLogger.log("[Connection \(endpoint)] State -> WAITING: \(error)")
            case .failed(let error):
                MeticulousTraceLogger.log("[Connection \(endpoint)] State -> FAILED: \(error)")
            case .cancelled:
                MeticulousTraceLogger.log("[Connection \(endpoint)] State -> CANCELLED")
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInteractive))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                await self?.processIncomingRequest(connection: connection, endpoint: endpoint, data: data, isComplete: isComplete, error: error)
            }
        }
    }

    private func processIncomingRequest(connection: NWConnection, endpoint: String, data: Data?, isComplete: Bool, error: NWError?) async {
        guard let data = data, let request = String(data: data, encoding: .utf8) else {
            if let error = error {
                MeticulousTraceLogger.log("[Connection \(endpoint)] Read error: \(error)")
            }
            connection.cancel()
            return
        }

        let responseData = await route(request: request, endpoint: endpoint)
        
        connection.send(content: responseData, isComplete: true, completion: .contentProcessed({ sendError in
            if let sendError = sendError {
                MeticulousTraceLogger.log("[Connection \(endpoint)] Send error: \(sendError)")
                connection.cancel()
            } else {
                MeticulousTraceLogger.log("[Connection \(endpoint)] Send finished cleanly (\(responseData.count) bytes)")
                connection.cancel()
            }
        }))
    }

    // MARK: - HTTP & Socket.IO Routing

    private func route(request: String, endpoint: String) async -> Data {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, !firstLine.isEmpty else {
            return httpResponse(statusCode: 400, text: "Bad Request")
        }

        MeticulousTraceLogger.log("[HTTP \(endpoint)] >>> \(firstLine)")
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return httpResponse(statusCode: 400, text: "Bad Request")
        }

        let method = parts[0]
        let path = parts[1]

        // Record incoming client activity to update transponder state
        Task { @MainActor in
            MeticulousTransponder.shared.recordActivity()
        }

        // 1. CORS Preflight
        if method == "OPTIONS" {
            return corsPreflightResponse()
        }
        
        // 2. Engine.IO / Socket.IO Handshake & Heartbeat
        if path.hasPrefix("/socket.io/") {
            if method == "POST" {
                return httpResponse(statusCode: 200, text: "ok")
            }

            if !path.contains("sid=") {
                self.activeSessionId = "bb\(Int.random(in: 1000...9999))"
                self.hasAckedSocketIONamespace = false
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Open Packet (sid=\(activeSessionId))")
                let openPacket = "0{\"sid\":\"\(activeSessionId)\",\"upgrades\":[],\"pingInterval\":25000,\"pingTimeout\":20000,\"maxPayload\":1000000}"
                return httpResponse(statusCode: 200, text: openPacket)
            }

            if !self.hasAckedSocketIONamespace {
                self.hasAckedSocketIONamespace = true
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Socket.IO Connect (40)")
                return httpResponse(statusCode: 200, text: "40{\"sid\":\"\(activeSessionId)\"}")
            } else {
                // Hold Engine.IO poll for 5 seconds to eliminate short-polling spin loops
                MeticulousTraceLogger.log("[HTTP \(endpoint)] Holding Engine.IO poll (5s pause)...")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Engine.IO NOOP (6)")
                return httpResponse(statusCode: 200, text: "6")
            }
        }

        // 3b. Machine State Probe (Fixes Metic 404)
        if path.hasPrefix("/api/v1/machine") {
            let machinePayload = """
                    {
                        "state": "idle",
                        "status": "ready",
                        "temperature": 93.0,
                        "firmware": "2.0.0",
                        "serial": "LP-FLAIR-58"
                    }
                    """
            MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 /api/v1/machine serving idle state")
            return httpResponse(statusCode: 200, json: machinePayload)
        }
        
        // 4. History Stats & Last Shot (Must precede generic /api/v1/history)
        if path.hasPrefix("/api/v1/history/stats") {
            let count = fetchCandidateShotURLs().count
            let statsPayload = "{\"total_shots\":\(count),\"shots_today\":1}"
            MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 /api/v1/history/stats (count: \(count))")
            return httpResponse(statusCode: 200, json: statsPayload)
        }
        
        if path.hasPrefix("/api/v1/history/last") {
            if let lastShot = loadSingleDetailedShotEntry(forId: nil) {
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 /api/v1/history/last serving '\(lastShot.id)'")
                if let encoded = try? JSONEncoder().encode(lastShot),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    return httpResponse(statusCode: 200, json: jsonString)
                }
            }
            return httpResponse(statusCode: 200, json: "{}")
        }
        
        // 4b. Ingestion & Telemetry History Endpoint
        if path.hasPrefix("/api/v1/history") {
            // Check for specific requested shot ID in query param or body
            var requestedId: String? = nil
            if let idRange = request.range(of: "\"ids\":[\"") {
                let rest = request[idRange.upperBound...]
                if let endQuote = rest.firstIndex(of: "\"") {
                    requestedId = String(rest[..<endQuote])
                }
            } else if let idRange = request.range(of: "id=") {
                let rest = request[idRange.upperBound...]
                let end = rest.firstIndex(where: { $0 == "&" || $0 == " " || $0 == "\r" }) ?? rest.endIndex
                requestedId = String(rest[..<end])
            }
            
            if let requestedId = requestedId {
                if let detailedEntry = loadSingleDetailedShotEntry(forId: requestedId) {
                    MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Serving detailed telemetry for '\(detailedEntry.id)' (\(detailedEntry.data?.count ?? 0) points)")
                    let response = MeticulousHistoryResponse(history: [detailedEntry])
                    if let encoded = try? JSONEncoder().encode(response),
                       let jsonString = String(data: encoded, encoding: .utf8) {
                        return httpResponse(statusCode: 200, json: jsonString)
                    }
                }
            }
            
            // SANDBOX EXPERIMENT: Load all recent shots with FULL telemetry data!
            let candidateURLs = fetchCandidateShotURLs(maxCeiling: 5)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var detailedEntries: [MeticulousHistoryEntry] = []
            
            for url in candidateURLs {
                if let data = try? Data(contentsOf: url),
                   let record = try? decoder.decode(ShotRecord.self, from: data) {
                    detailedEntries.append(record.toMeticulousHistoryEntry())
                }
            }
            
            MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Serving FULL telemetry history (\(detailedEntries.count) shots)")
            let response = MeticulousHistoryResponse(history: detailedEntries)
            if let encoded = try? JSONEncoder().encode(response),
               let jsonString = String(data: encoded, encoding: .utf8) {
                return httpResponse(statusCode: 200, json: jsonString)
            }
            
            return httpResponse(statusCode: 200, json: "{\"history\":[]}")
        }
        
        // 5. Profile Catalog Endpoint
        if path.hasPrefix("/api/v1/profile") {
            let latest = loadRecentShotListingHeadersFromDisk().first
            let profileId = latest?.id ?? "leverpilot-profile"
            let profileName = latest?.profile.name ?? "LeverPilot Profile"
            let temp = latest?.profile.temperature ?? 93.0

            if path.contains("/list") || path == "/api/v1/profile" || path == "/api/v1/profile/" {
                let json = "[{\"id\":\"\(profileId)\",\"name\":\"\(profileName)\",\"temperature\":\(temp),\"version\":1}]"
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 /api/v1/profile/list serving '\(profileName)'")
                return httpResponse(statusCode: 200, json: json)
            } else {
                let json = "{\"id\":\"\(profileId)\",\"name\":\"\(profileName)\",\"temperature\":\(temp),\"version\":1}"
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 /api/v1/profile/\(profileId)")
                return httpResponse(statusCode: 200, json: json)
            }
        }

        MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 404 Not Handled: \(method) \(path)")
        return httpResponse(statusCode: 404, text: "Not Found")
    }

    // MARK: - Disk Catalog Providers

    /// Returns lightweight history entries (data: nil) filtered to recent pulls (capped at 20),
    /// or falling back to the 2 most recent pulls if none occurred today.
    private func loadRecentShotListingHeadersFromDisk() -> [MeticulousHistoryEntry] {
        let candidateURLs = fetchCandidateShotURLs()
        var entries: [MeticulousHistoryEntry] = []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in candidateURLs {
            if let data = try? Data(contentsOf: url),
               let header = try? decoder.decode(ShotRecordListingHeader.self, from: data) {
                entries.append(header.toMeticulousHistoryEntry())
            }
        }

        return entries
    }

    /// Loads and fully decodes a single shot file for full 10 Hz telemetry detail.
    private func loadSingleDetailedShotEntry(forId requestedId: String?) -> MeticulousHistoryEntry? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let shotLogsURL = documentsURL.appendingPathComponent("ShotLogs")

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: shotLogsURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        // Sort chronologically descending purely by filename
        let jsonURLs = fileURLs
            .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.hasPrefix("shot_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        var targetURL: URL? = nil

        // 1. Fast match: lookup by 8-character UUID prefix in filename
        if let requestedId = requestedId {
            let shortId = String(requestedId.prefix(8))
            targetURL = jsonURLs.first { $0.lastPathComponent.localizedCaseInsensitiveContains(shortId) }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 2. Fallback: Check lightweight header if filename match was not found
        if targetURL == nil, let requestedId = requestedId {
            for url in jsonURLs {
                if let data = try? Data(contentsOf: url),
                   let header = try? decoder.decode(ShotRecordListingHeader.self, from: data),
                   header.id == requestedId {
                    targetURL = url
                    break
                }
            }
        }

        // 3. Fallback: Most recent file if no ID specified
        if targetURL == nil {
            targetURL = jsonURLs.first
        }

        guard let url = targetURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        if let record = try? decoder.decode(ShotRecord.self, from: data) {
            return record.toMeticulousHistoryEntry()
        }

        return nil
    }

    /// Selects candidate shot URLs using a robust operational window:
    /// Any shots pulled within the last 48 hours, falling back to the 5 most recent pulls,
    /// with a strict ceiling of 20 shots.
    private func fetchCandidateShotURLs(maxCeiling: Int = 20) -> [URL] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let shotLogsURL = documentsURL.appendingPathComponent("ShotLogs")
        
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: shotLogsURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        // Chronologically descending by filename (ISO-8601 alphabetical ordering)
        let sorted = fileURLs
            .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.hasPrefix("shot_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        
        guard !sorted.isEmpty else { return [] }
        
        // 48-hour cutoff prefix in UTC to match ISO-8601 filename ordering
        let cutoffDate = Date().addingTimeInterval(-48 * 3600)
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let cutoffPrefix = "shot_" + isoFormatter.string(from: cutoffDate)
        
        // Lexicographical string comparison: any file >= cutoffPrefix was created within 48h
        let recent48hURLs = sorted.filter { $0.lastPathComponent >= cutoffPrefix }
        
        if !recent48hURLs.isEmpty {
            return Array(recent48hURLs.prefix(maxCeiling))
        } else {
            // Fallback: If nothing was pulled in the last 48 hours, provide the 5 most recent
            return Array(sorted.prefix(min(5, maxCeiling)))
        }
    }

    // MARK: - HTTP Encoders

    private func corsPreflightResponse() -> Data {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: *",
            "Connection: close"
        ].joined(separator: "\r\n") + "\r\n\r\n"
        
        return Data(headers.utf8)
    }

    private func httpResponse(statusCode: Int, json: String) -> Data {
        let headers = [
            "HTTP/1.1 \(statusCode) OK",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: *",
            "Connection: close",
            "Content-Length: \(json.utf8.count)"
        ].joined(separator: "\r\n") + "\r\n\r\n"
        
        return Data((headers + json).utf8)
    }
    
    private func httpResponse(statusCode: Int, text: String) -> Data {
        let headers = [
            "HTTP/1.1 \(statusCode) OK",
            "Content-Type: text/plain; charset=UTF-8",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: *",
            "Connection: close",
            "Content-Length: \(text.utf8.count)"
        ].joined(separator: "\r\n") + "\r\n\r\n"
        
        return Data((headers + text).utf8)
    }
}
