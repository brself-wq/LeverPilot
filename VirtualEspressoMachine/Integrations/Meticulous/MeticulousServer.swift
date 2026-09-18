import Foundation
import SwiftUI
import Network
import Combine

public final class MeticulousServer: ObservableObject {
    public static let shared = MeticulousServer()

    @Published public var isRunning: Bool = false
    @Published public var serverPort: UInt16 = 8080
    @Published public var currentShotId: String = "shot-1"
    @Published public var stagedShot: MeticulousHistoryEntry?

    /// Hook fired when BQ completes downloading the telemetry shot payload
    public var onShotDelivered: (() -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.beanbridge.meticulousserver", qos: .userInteractive)

    private var internalShotCounter: Int = 0
    private var internalStagedShot: MeticulousHistoryEntry?

    private init() {
        start()
    }

    public func start(port: UInt16 = 8080) {
        stop()
        self.serverPort = port
        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: nwPort)
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[MeticulousServer] Ready on 127.0.0.1:\(port)")
                    case .failed(let error):
                        self?.isRunning = false
                        print("[MeticulousServer] Listener failed: \(error)")
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        self?.isRunning = false
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("[MeticulousServer] Failed to start: \(error)")
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    /// Stages the shot and assigns a fresh unique shot ID
    public func stageShot(_ shot: MeticulousHistoryEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
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

            self.internalStagedShot = staged

            DispatchQueue.main.async {
                self.currentShotId = newId
                self.stagedShot = staged
                print("[MeticulousServer] Staged Meticulous shot with ID '\(newId)'")
            }
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, let request = String(data: data, encoding: .utf8) else {
                if let error = error {
                    print("[MeticulousServer] Connection error: \(error)")
                }
                connection.cancel()
                return
            }

            let responseData = self.route(request: request)
            connection.send(content: responseData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func route(request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpResponse(statusCode: 400, body: "Bad Request")
        }

        print("[MeticulousServer] >>> \(firstLine)")
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return httpResponse(statusCode: 400, body: "Bad Request")
        }

        let method = parts[0]
        let path = parts[1]

        // 1. Handle CORS preflight (Crucial for Axios POST in Capacitor / WebView)
        if method == "OPTIONS" {
            print("[MeticulousServer] <<< 204 No Content (OPTIONS Preflight)")
            return corsPreflightResponse()
        }
        
        // Handle Socket.IO Handshake (Required for BQ to consider Meticulous connected)
        if path.hasPrefix("/socket.io/") {
            print("[MeticulousServer] <<< 200 OK (Socket.IO Handshake)")
            if path.contains("sid=") {
                // Connected confirmation packet (4 = MESSAGE, 0 = CONNECT)
                return httpResponse(statusCode: 200, text: "40{\"sid\":\"bb123\"}")
            } else {
                // Open handshake packet (0 = OPEN)
                let openPacket = "0{\"sid\":\"bb123\",\"upgrades\":[],\"pingInterval\":25000,\"pingTimeout\":20000,\"maxPayload\":1000000}"
                return httpResponse(statusCode: 200, text: openPacket)
            }
        }

        // 2. Handshake Ping from BQ (Checks if machine is online)
        // BQ specifically verifies: if (settings?.data?.config)
        if method == "GET" && path.hasPrefix("/api/v1/settings") {
            print("[MeticulousServer] <<< 200 OK (/api/v1/settings)")
            let settingsPayload = "{\"config\":{\"machine\":\"Flair 58 (Meticulous Emulated)\"},\"heat_on_boot\":true}"
            return httpResponse(statusCode: 200, json: settingsPayload)
        }

        // 3. Search History / Ingestion Endpoint
        if path.hasPrefix("/api/v1/history") {
            guard let staged = self.internalStagedShot else {
                let emptyResponse = "{\"history\":[]}"
                return httpResponse(statusCode: 200, json: emptyResponse)
            }

            // Distinguish between listing query (dump_data: false) and telemetry fetch (dump_data: true)
            let isDetailRequest = request.contains("\"dump_data\":true") || request.contains("\"dump_data\": true")

            if isDetailRequest {
                print("[MeticulousServer] <<< 200 OK: Serving detailed telemetry for '\(staged.id)'")
                let response = MeticulousHistoryResponse(history: [staged])
                if let encoded = try? JSONEncoder().encode(response),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    
                    // Notify coordinator that payload has been served
                    DispatchQueue.main.async { [weak self] in
                        self?.onShotDelivered?()
                    }
                    return httpResponse(statusCode: 200, json: jsonString)
                }
            } else {
                print("[MeticulousServer] <<< 200 OK: Serving shot listing (dump_data: false)")
                let listingShot = staged.withoutData()
                let response = MeticulousHistoryResponse(history: [listingShot])
                if let encoded = try? JSONEncoder().encode(response),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    return httpResponse(statusCode: 200, json: jsonString)
                }
            }
        }

        // 4. Default Profiles List (Optional fallback)
        if path.hasPrefix("/api/v1/profile") {
            return httpResponse(statusCode: 200, json: "[]")
        }

        print("[MeticulousServer] <<< 404 Not Handled: \(method) \(path)")
        return httpResponse(statusCode: 404, body: "Not Found")
    }

    private func corsPreflightResponse() -> Data {
        let headers = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Accept, Authorization\r
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
        Access-Control-Allow-Headers: Content-Type, Accept, Authorization\r
        Connection: close\r
        Content-Length: \(json.utf8.count)\r
        \r\n
        """
        return Data((headers + json).utf8)
    }

    private func httpResponse(statusCode: Int, body: String) -> Data {
        let headers = """
        HTTP/1.1 \(statusCode) Status\r
        Content-Type: text/plain\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        Content-Length: \(body.utf8.count)\r
        \r\n
        """
        return Data((headers + body).utf8)
    }
    
    private func httpResponse(statusCode: Int, text: String) -> Data {
        let headers = """
            HTTP/1.1 \(statusCode) OK\r
            Content-Type: text/plain; charset=UTF-8\r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type, Accept, Authorization\r
            Connection: close\r
            Content-Length: \(text.utf8.count)\r
            \r\n
            """
        return Data((headers + text).utf8)
    }
}
