// 2. Store — where XrayBar keeps its files. This is the only place the app writes to,
// besides the privileged session's /var/run/xraybar (see 5-Session and the script).

import Foundation

enum Store {
    static let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/XrayBar")
    static let libraryFile = dir.appendingPathComponent("library.json")
    /// Config handed to the privileged session, which copies it to a root-owned place.
    static let configFile = dir.appendingPathComponent("config.json")
    /// Its existence asks the running session to stop.
    static let stopFile = dir.appendingPathComponent("stop")

    /// Written by the root session; world-readable.
    static let runDir = URL(fileURLWithPath: "/var/run/xraybar")
    static let pidFile = runDir.appendingPathComponent("xray.pid")
    static let sessionPidFile = runDir.appendingPathComponent("session.pid")
    static let logFile = runDir.appendingPathComponent("xray.log")
    /// Present while DNS is overridden; kept in /var/db so it survives a power loss.
    static let dnsSavedFile = URL(fileURLWithPath: "/var/db/xraybar/dns.saved")

    static func load() -> Library {
        guard let data = try? Data(contentsOf: libraryFile) else { return Library() }
        if let library = try? JSONDecoder().decode(Library.self, from: data) { return library }
        // Unreadable (e.g. older format): keep it aside rather than overwrite it later.
        let aside = dir.appendingPathComponent("library.unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: libraryFile, to: aside)
        return Library()
    }

    static func save(_ library: Library) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(library), to: libraryFile)
    }

    /// Files are private to the user (0600): profiles contain credentials (stage 1: no Keychain yet).
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
