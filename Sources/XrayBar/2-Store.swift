// 2. Store — where XrayBar keeps its files. This is the only place the app writes to,
// besides the privileged session's /var/run/xraybar (see 5-Session and the script).

import Foundation
import Security

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

    /// The VLESS ids (the servers' credentials) as the keychain holds them; nil if it could not
    /// be read, and then they stay in library.json (D45).
    @MainActor private static var inKeychain: [String: String]?

    @MainActor static func load() -> Library {
        inKeychain = Keychain.read()
        guard let data = try? Data(contentsOf: libraryFile) else { return Library() }
        guard var library = try? JSONDecoder().decode(Library.self, from: data) else {
            // Unreadable (e.g. older format): keep it aside rather than overwrite it later.
            let aside = dir.appendingPathComponent("library.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: libraryFile, to: aside)
            return Library()
        }
        let inFile = library.profiles.contains { !$0.uuid.isEmpty }
        for i in library.profiles.indices where library.profiles[i].uuid.isEmpty {
            library.profiles[i].uuid = inKeychain?[library.profiles[i].id.uuidString] ?? ""
        }
        if inFile && inKeychain != nil { try? save(library) }   // moves them out of the file
        return library
    }

    /// library.json without the VLESS ids once the keychain has taken them.
    @MainActor static func save(_ library: Library) throws {
        var file = library
        let secrets = Dictionary(library.profiles.map { ($0.id.uuidString, $0.uuid) }) { a, _ in a }
        if inKeychain != nil, secrets == inKeychain || Keychain.write(secrets) {
            inKeychain = secrets
            for i in file.profiles.indices { file.profiles[i].uuid = "" }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(file), to: libraryFile)
    }

    /// Files are private to the user (0600): configs, and library.json if the keychain is unavailable, hold credentials.
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// One generic password item in the login keychain: {profile id: VLESS id} as JSON. One item,
/// so macOS asks for access once after an app update (an ad-hoc signed app is "new" each
/// build), not once per server (D45).
enum Keychain {
    private static var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.github.heaprip.xraybar",
         kSecAttrAccount as String: "server-credentials"]
    }

    /// Empty if there is no item yet; nil if it could not be read (access denied, locked).
    static func read() -> [String: String]? {
        var query = item
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess: return (result as? Data).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        case errSecItemNotFound: return [:]
        default: return nil
        }
    }

    static func write(_ secrets: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(secrets) else { return false }
        let status = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var add = item
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "XrayBar server credentials"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
