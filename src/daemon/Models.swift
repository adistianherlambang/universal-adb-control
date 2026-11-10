import Foundation
import AppKit
import CryptoKit

// MARK: - Models

public enum ClipboardType: String, Codable {
    case text = "TEXT"
    case image = "IMAGE"
    case files = "FILES"
    case ping = "PING"
    case pong = "PONG"
}

public struct ClipboardMessage: Codable {
    public let type: ClipboardType
    public let origin: String?
    public let hash: String?
    public let text: String?
    public let html: String?
    public let mime: String?
    public let remotePath: String?
    public let remotePaths: [String]?
    public let size: Int64?
    public let count: Int?
    public let status: String?

    public init(
        type: ClipboardType,
        origin: String? = nil,
        hash: String? = nil,
        text: String? = nil,
        html: String? = nil,
        mime: String? = nil,
        remotePath: String? = nil,
        remotePaths: [String]? = nil,
        size: Int64? = nil,
        count: Int? = nil,
        status: String? = nil
    ) {
        self.type = type
        self.origin = origin
        self.hash = hash
        self.text = text
        self.html = html
        self.mime = mime
        self.remotePath = remotePath
        self.remotePaths = remotePaths
        self.size = size
        self.count = count
        self.status = status
    }
}

// MARK: - Logger

public final class Logger {
    public static let shared = Logger()
    private let logFileUrl: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".universal-adb-control", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileUrl = dir.appendingPathComponent("daemon.log")
        if !FileManager.default.fileExists(atPath: logFileUrl.path) {
            FileManager.default.createFile(atPath: logFileUrl.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileUrl)
        fileHandle?.seekToEndOfFile()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    public func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print(message)
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}

// MARK: - Config

public struct DaemonConfig {
    public var preferredDevice: String?
    public var adbPath: String
    public var syncIntervalMs: Int = 300
    public var storageDir: URL

    public static func load() -> DaemonConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let confDir = home.appendingPathComponent(".universal-adb-control", isDirectory: true)
        try? FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)
        let confFile = confDir.appendingPathComponent("config.conf")

        var dev: String? = nil
        var adb = "/opt/homebrew/bin/adb"

        if FileManager.default.fileExists(atPath: confFile.path),
           let content = try? String(contentsOf: confFile, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    if parts[0] == "DEVICE" && !parts[1].isEmpty {
                        dev = parts[1]
                    } else if parts[0] == "ADB" && !parts[1].isEmpty {
                        adb = parts[1]
                    }
                }
            }
        }

        if !FileManager.default.fileExists(atPath: adb) {
            if FileManager.default.fileExists(atPath: "/usr/local/bin/adb") {
                adb = "/usr/local/bin/adb"
            }
        }

        let tmpDir = confDir.appendingPathComponent("temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        return DaemonConfig(preferredDevice: dev, adbPath: adb, storageDir: tmpDir)
    }
}

// MARK: - State Manager

public final class DaemonState {
    public static let shared = DaemonState()
    private let statusFile: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".universal-adb-control", isDirectory: true)
        statusFile = dir.appendingPathComponent("status.json")
    }

    public struct StatusData: Codable {
        public var running: Bool
        public var pid: Int32
        public var connectedDevice: String?
        public var lastSyncTime: String?
        public var lastContentType: String?
        public var lastDirection: String?
        public var lastError: String?
    }

    public func update(
        running: Bool,
        connectedDevice: String? = nil,
        contentType: String? = nil,
        direction: String? = nil,
        error: String? = nil
    ) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let data = StatusData(
            running: running,
            pid: ProcessInfo.processInfo.processIdentifier,
            connectedDevice: connectedDevice,
            lastSyncTime: df.string(from: Date()),
            lastContentType: contentType,
            lastDirection: direction,
            lastError: error
        )
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: statusFile)
        }
    }
}
