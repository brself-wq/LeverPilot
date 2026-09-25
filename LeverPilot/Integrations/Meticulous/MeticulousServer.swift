//
//  MeticulousServer.swift
//  LeverPilot
//

import Foundation
import Network

/// Actor-isolated HTTP & Socket.IO loopback server emulating the Meticulous machine API.
/// Serializes incoming HTTP parsing, socket handling, and telemetry staging without data races.
public actor MeticulousServer {
    public static let shared = MeticulousServer()

    // MARK: - Isolated Server State
    public private(set) var isRunning: Bool = false
    public private(set) var serverPort: UInt16 = 8080
    public private(set) var currentShotId: String = "shot-1"
    public private(set) var stagedShot: MeticulousHistoryEntry?
    public private(set) var verboseLogging: Bool = false

    private var onShotDelivered: (@Sendable () -> Void)?
    private var listener: NWListener?
    private var internalShotCounter: Int = 0
    private var hasConnectedSocketIO: Bool = false

    private init() {
        // Starts via configure() on app launch
    }

    // MARK: - Configuration & Lifecycle

    /// Configures the server from user settings, restarting the listener only if the port changes.
    public func configure(port: Int, verbose: Bool) {
        self.verboseLogging = verbose
        let targetPort = UInt16(clamping: port)
        if serverPort != targetPort || listener == nil {
            start(port: targetPort)
        }
    }

    public func setVerboseLogging(_ enabled: Bool) {
        self.verboseLogging = enabled
    }

    public func setOnShotDelivered(_ handler: (@Sendable () -> Void)?) {
        self.onShotDelivered = handler
    }

    public func start(port: UInt16 = 8080) {
        stop()
        self.serverPort = port
        self.hasConnectedSocketIO = false
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
        } catch {
            print("[MeticulousServer] Failed to start: \(error)")
            self.isRunning = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        hasConnectedSocketIO = false
    }

    // MARK: - Shot Staging

    /// Stages a completed shot entry and assigns a unique sequence ID.
    public func stageShot(_ shot: MeticulousHistoryEntry) {
        self.internalShotCounter += 1
        let newId = shot.id.isEmpty ? "shot-\(self.internalShotCounter)" : shot.id

        let staged = MeticulousHistoryEntry(
            id: newId,
            dbKey: self.internalShotCounter,
            time: shot.time,
            name: shot.name,
            profile: shot.profile,
            data: shot.data
        )

        self.currentShotId = newId
        self.stagedShot = staged
        print("[MeticulousServer] Staged Meticulous shot with ID '\(newId)'")
    }

    /// Convenience helper to stage a completed LeverPilot `ShotRecord` directly.
    public func stageShot(_ record: ShotRecord) {
        stageShot(record.toMeticulousHistoryEntry())
    }

    #if DEBUG
    /// Hook for automated testing to simulate payload delivery without an active TCP client.
    public func simulateShotDelivered() {
        onShotDelivered?()
    }
    #endif

    // MARK: - Internal Connection Handling

    private func handleStateUpdate(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            self.isRunning = true
            print("[MeticulousServer] Ready on 127.0.0.1:\(port)")
        case .failed(let error):
            self.isRunning = false
            print("[MeticulousServer] Listener failed: \(error)")
        case .cancelled:
            self.isRunning = false
        default:
            self.isRunning = false
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] data, _, _, error in
            Task { [weak self] in
                await self?.processIncomingRequest(connection: connection, data: data, error: error)
            }
        }
    }

    private func processIncomingRequest(connection: NWConnection, data: Data?, error: NWError?) {
        guard let data = data, let request = String(data: data, encoding: .utf8) else {
            if let error = error {
                logVerbose("[MeticulousServer] Connection error: \(error)")
            }
            connection.cancel()
            return
        }

        let responseData = route(request: request)
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - HTTP & Socket.IO Routing

    private func route(request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpResponse(statusCode: 400, text: "Bad Request")
        }

        logVerbose("[MeticulousServer] >>> \(firstLine)")
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return httpResponse(statusCode: 400, text: "Bad Request")
        }

        let method = parts[0]
        let path = parts[1]

        // 1. Universal CORS Preflight
        if method == "OPTIONS" {
            logVerbose("[MeticulousServer] <<< 204 No Content (OPTIONS Preflight)")
            return corsPreflightResponse()
        }
        
        // 2. Engine.IO / Socket.IO Handshake & Heartbeat
        if path.hasPrefix("/socket.io/") {
            // Engine.IO Rule: All client POSTs carrying packets must be answered with "ok"
            if method == "POST" {
                logVerbose("[MeticulousServer] <<< 200 OK (Socket.IO POST -> 'ok')")
                return httpResponse(statusCode: 200, text: "ok")
            }

            // Engine.IO Rule: Initial handshake GET (no sid) gets the open packet
            if !path.contains("sid=") {
                self.hasConnectedSocketIO = false
                logVerbose("[MeticulousServer] <<< 200 OK (Engine.IO Open Packet)")
                let openPacket = "0{\"sid\":\"bb123\",\"upgrades\":[],\"pingInterval\":25000,\"pingTimeout\":20000,\"maxPayload\":1000000}"
                return httpResponse(statusCode: 200, text: openPacket)
            }

            // Engine.IO Rule: Long-poll GET with sid
            if !self.hasConnectedSocketIO {
                // First GET poll: emit Socket.IO connect ack for default namespace '/'
                self.hasConnectedSocketIO = true
                logVerbose("[MeticulousServer] <<< 200 OK (Socket.IO Namespace Connect)")
                return httpResponse(statusCode: 200, text: "40{\"sid\":\"bb123\"}")
            } else {
                // Subsequent polls: emit Pong (packet type '3') to satisfy heartbeat
                logVerbose("[MeticulousServer] <<< 200 OK (Engine.IO Pong)")
                return httpResponse(statusCode: 200, text: "3")
            }
        }

        // 3. Settings / Presence Probe from BQ
        if path.hasPrefix("/api/v1/settings") {
            logVerbose("[MeticulousServer] <<< 200 OK (/api/v1/settings)")
            let settingsPayload = "{\"config\":{\"machine\":\"Flair 58 (Meticulous Emulated)\"},\"heat_on_boot\":true}"
            return httpResponse(statusCode: 200, json: settingsPayload)
        }

        // 4. Ingestion & Telemetry History Endpoint
        if path.hasPrefix("/api/v1/history") {
            guard let staged = self.stagedShot else {
                logVerbose("[MeticulousServer] <<< 200 OK (/api/v1/history -> empty)")
                let emptyResponse = "{\"history\":[]}"
                return httpResponse(statusCode: 200, json: emptyResponse)
            }

            // Detect dump_data in URL query param OR in JSON body
            let isDetailRequest = request.contains("dump_data=true")
                || request.contains("\"dump_data\":true")
                || request.contains("\"dump_data\": true")

            if isDetailRequest {
                print("[MeticulousServer] <<< 200 OK: Serving detailed telemetry for '\(staged.id)'")
                let response = MeticulousHistoryResponse(history: [staged])
                if let encoded = try? JSONEncoder().encode(response),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    
                    // Trigger delivery ledger hook
                    let callback = self.onShotDelivered
                    Task {
                        callback?()
                    }
                    return httpResponse(statusCode: 200, json: jsonString)
                }
            } else {
                logVerbose("[MeticulousServer] <<< 200 OK: Serving shot listing for '\(staged.id)' (dump_data: false)")
                let listingShot = staged.withoutData()
                let response = MeticulousHistoryResponse(history: [listingShot])
                if let encoded = try? JSONEncoder().encode(response),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    return httpResponse(statusCode: 200, json: jsonString)
                }
            }
        }

        // 5. Default Profile Catalog Stub
        if path.hasPrefix("/api/v1/profile") {
            logVerbose("[MeticulousServer] <<< 200 OK (/api/v1/profile)")
            return httpResponse(statusCode: 200, json: "[]")
        }

        logVerbose("[MeticulousServer] <<< 404 Not Handled: \(method) \(path)")
        return httpResponse(statusCode: 404, text: "Not Found")
    }

    private func logVerbose(_ message: String) {
        if verboseLogging {
            print(message)
        }
    }

    // MARK: - HTTP Encoders (Strict Header Hygiene & Permissive CORS)

    private func corsPreflightResponse() -> Data {
        let headers = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: *\r
        Connection: close\r
        \r\n
        """
        return Data(headers.utf8)
    }

    private func httpResponse(statusCode: Int, json: String) -> Data {
        let headers = """
        HTTP/1.1 \(statusCode) OK\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: *\r
        Connection: close\r
        Content-Length: \(json.utf8.count)\r
        \r\n
        """
        return Data((headers + json).utf8)
    }
    
    private func httpResponse(statusCode: Int, text: String) -> Data {
        let headers = """
        HTTP/1.1 \(statusCode) OK\r
        Content-Type: text/plain; charset=UTF-8\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: *\r
        Connection: close\r
        Content-Length: \(text.utf8.count)\r
        \r\n
        """
        return Data((headers + text).utf8)
    }
}
