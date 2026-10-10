//
//  MeticulousServer.swift
//  LeverPilot
//

import Foundation
import Network

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

        // 3. Settings Probe
        if path.hasPrefix("/api/v1/settings") {
            let settingsPayload = "{\"config\":{\"machine\":\"Flair 58 (Meticulous Emulated)\"},\"heat_on_boot\":true}"
            return httpResponse(statusCode: 200, json: settingsPayload)
        }

        // 4. Ingestion & Telemetry History Endpoint (Stateless Disk Catalog)
        if path.hasPrefix("/api/v1/history") {
            let recentEntries = loadRecentShotEntriesFromDisk()

            // Check for specific requested shot ID
            var requestedId: String? = nil
            if let idRange = request.range(of: "\"ids\":[\"") {
                let rest = request[idRange.upperBound...]
                if let endQuote = rest.firstIndex(of: "\"") {
                    requestedId = String(rest[..<endQuote])
                }
            }

            let isDetailRequest = request.contains("dump_data=true")
                || request.contains("\"dump_data\":true")
                || request.contains("\"dump_data\": true")

            if isDetailRequest {
                let matched = recentEntries.first(where: { $0.id == requestedId }) ?? recentEntries.first

                if let matched = matched {
                    MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Serving detailed telemetry for '\(matched.id)' (\(matched.data?.count ?? 0) points)")
                    let response = MeticulousHistoryResponse(history: [matched])
                    if let encoded = try? JSONEncoder().encode(response),
                       let jsonString = String(data: encoded, encoding: .utf8) {
                        return httpResponse(statusCode: 200, json: jsonString)
                    }
                }
            } else {
                let listingEntries = recentEntries.map { $0.withoutData() }
                MeticulousTraceLogger.log("[HTTP \(endpoint)] <<< 200 Serving history listing (\(listingEntries.count) shots)")
                let response = MeticulousHistoryResponse(history: listingEntries)
                if let encoded = try? JSONEncoder().encode(response),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    return httpResponse(statusCode: 200, json: jsonString)
                }
            }

            return httpResponse(statusCode: 200, json: "{\"history\":[]}")
        }

        // 5. Profile Catalog Endpoint
        if path.hasPrefix("/api/v1/profile") {
            let latest = loadRecentShotEntriesFromDisk().first
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

    // MARK: - Disk Catalog Provider

    private func loadRecentShotEntriesFromDisk() -> [MeticulousHistoryEntry] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let shotLogsURL = documentsURL.appendingPathComponent("ShotLogs")

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: shotLogsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let sortedURLs = fileURLs
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            .prefix(20)

        var entries: [MeticulousHistoryEntry] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in sortedURLs {
            if let data = try? Data(contentsOf: url),
               let record = try? decoder.decode(ShotRecord.self, from: data) {
                entries.append(record.toMeticulousHistoryEntry())
            }
        }

        return entries
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
