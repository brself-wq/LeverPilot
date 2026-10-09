//
//  MeticulousTraceLogger.swift
//  LeverPilot
//

import Foundation

/// Fast, thread-safe, nonisolated flight recorder writing directly to Documents/MeticulousTrace.log.
public nonisolated final class MeticulousTraceLogger: @unchecked Sendable {
    public static let shared = MeticulousTraceLogger()

    /// Gated directly by settingsStore.traceLogging. When false, disk writes are suppressed.
    public static var isEnabled: Bool = false

    private let queue = DispatchQueue(label: "com.leverpilot.tracelogger", qos: .utility)
    private let logFileURL: URL?
    private let formatter: DateFormatter

    private init() {
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.logFileURL = documentsURL.appendingPathComponent("MeticulousTrace.log")
        } else {
            self.logFileURL = nil
        }
    }

    public static func log(_ message: String) {
        shared.write(message)
    }

    private func write(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        #if DEBUG
        print(line, terminator: "")
        #endif

        guard Self.isEnabled, let url = logFileURL else { return }

        queue.async {
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: url.path) {
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    _ = try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: data)
                    try? fileHandle.synchronize()
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
