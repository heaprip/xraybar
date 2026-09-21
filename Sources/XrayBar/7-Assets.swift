// 7. Assets — XrayBar's own Xray versions and routing data (geoip.dat, geosite.dat).
//
// This is the ONLY code in the app that uses the network. It runs when the user asks
// (download a version, check for versions, update routing data), plus one connectivity probe
// right after connecting with an Xray version that has not proven itself yet (D23).
// Nothing is used unless it passes its check:
// - Xray: the version tested with XrayBar is checked against a SHA-256 pinned right here (D22);
//   other versions against the SHA-256 in their release's .dgst file. A download is only staged
//   here: root copies it into its own store, the only place the session runs xray from (D38).
// - Routing data (rebuilt daily upstream): the SHA-256 published next to each file.
// Same-origin checksums prove a complete, unaltered download, not that upstream is benign.

import CryptoKit
import Foundation

enum Assets {
    /// geoip.dat and geosite.dat here.
    static let dir = Store.dir.appendingPathComponent("core")
    /// Installed Xray versions, <tag>/xray, root-owned (xraybar-install.sh --xray).
    static let store = URL(fileURLWithPath: "/Library/Application Support/XrayBar/xray")
    /// Downloads wait here, <tag>/xray, until root has copied them into the store.
    static let staging = Store.dir.appendingPathComponent("download")
    /// The tag of the copy of v2rayN's xray (Settings.v2rayNXray) in the store.
    static let v2rayNTag = "v2rayN"

    enum DataSource: String, Codable, CaseIterable, Sendable {
        case runetfreedom, loyalsoldier

        var title: String {
            switch self {
            case .runetfreedom: L("runetfreedom (Russia)")
            case .loyalsoldier: L("Loyalsoldier (China)")
            }
        }
        var baseURL: String {
            switch self {
            case .runetfreedom: "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/"
            case .loyalsoldier: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/"
            }
        }
    }

    /// Oldest Xray with native TUN routing on macOS (`autoSystemRoutingTable`); older releases
    /// ignore those fields and bring up a tunnel no traffic enters.
    static let minimumXray = [26, 5, 9]

    /// The version tested with this XrayBar and the SHA-256 of its zip per CPU. Cross-checked:
    /// the release's .dgst, an own download, and the binary is byte-identical to v2rayN 7.25.2's.
    static let testedXray = "v26.9.9"
    #if arch(arm64)
    static let zipName = "Xray-macos-arm64-v8a.zip"
    static let testedSHA256 = "b7cf765d60ccc703853d4218c49a1eacc5bca764543b9540bdeaf45c951afc7d"
    #else
    static let zipName = "Xray-macos-64.zip"
    static let testedSHA256 = "32b5d106b9936f3ae2044cd283d9e22749b57fd30b34a58792b86c90018bb5e4"
    #endif

    /// No cookies, no cache, nothing persisted by URLSession.
    private static let session = URLSession(configuration: .ephemeral)

    // MARK: Xray versions

    static func xrayPath(_ tag: String, in root: URL = store) -> String {
        root.appendingPathComponent("\(tag)/xray").path
    }

    /// Installed versions, newest first.
    static func installedXray(in root: URL = store) -> [String] {
        let tags = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return tags.filter { FileManager.default.isExecutableFile(atPath: xrayPath($0, in: root)) }
            .sorted { version($1).lexicographicallyPrecedes(version($0)) }
    }

    /// Release tags on GitHub, prereleases included (every Xray release since 26.5 is one),
    /// that are new enough for native TUN, newest first.
    static func availableXray() async throws -> [String] {
        let (data, response) = try await retrying {
            try await session.data(from: URL(string: "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=20")!)
        }
        try check(response, "Xray releases")
        let releases = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return releases.compactMap { $0["tag_name"] as? String }
            .filter { !version($0).lexicographicallyPrecedes(minimumXray) }
    }

    /// Downloads and verifies one version into <root>/<tag>/xray, returns the binary.
    static func downloadXray(_ tag: String, in root: URL = staging) async throws -> URL {
        let fm = FileManager.default
        let target = root.appendingPathComponent(tag)
        let staging = root.appendingPathComponent("\(tag).new")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let url = "https://github.com/XTLS/Xray-core/releases/download/\(tag)/\(zipName)"
        let zip = try await download(url, to: staging.appendingPathComponent(zipName))
        let expected = tag == testedXray ? testedSHA256 : field("SHA2-256=", in: try await text(url + ".dgst"))
        try verify(zip, expected: expected)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.appendingPathComponent("unpacked").path])
        let binary = staging.appendingPathComponent("xray")
        try fm.moveItem(at: staging.appendingPathComponent("unpacked/xray"), to: binary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try? fm.removeItem(at: staging.appendingPathComponent("unpacked"))
        try? fm.removeItem(at: zip)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: staging, to: target)
        return URL(fileURLWithPath: xrayPath(tag, in: root))
    }

    // MARK: Routing data

    /// Both files are downloaded and verified before either replaces the current one.
    static func updateData(_ source: DataSource, in root: URL = dir) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var verified: [(URL, URL)] = []
        defer { verified.forEach { try? fm.removeItem(at: $0.0) } }
        for name in ["geoip.dat", "geosite.dat"] {
            let url = source.baseURL + name
            let file = try await download(url, to: root.appendingPathComponent(name + ".new"))
            verified.append((file, root.appendingPathComponent(name)))
            try verify(file, expected: String(try await text(url + ".sha256sum").prefix { !$0.isWhitespace }))
        }
        for (new, current) in verified {
            try? fm.removeItem(at: current)
            try fm.moveItem(at: new, to: current)
        }
    }

    // MARK: Trial of a new Xray version

    /// One request through the tunnel. HTTP 204 means traffic flows end to end.
    static func probe() async -> Bool {
        var request = URLRequest(url: URL(string: "https://cp.cloudflare.com/generate_204")!)
        request.timeoutInterval = 8
        for _ in 1...3 {
            if let (_, r) = try? await session.data(for: request), (r as? HTTPURLResponse)?.statusCode == 204 { return true }
            try? await Task.sleep(for: .seconds(2))
        }
        return false
    }

    // MARK: Helpers

    /// [26, 9, 9] from "v26.9.9" or "Xray 26.9.9 (Xray, Penetrates Everything.) …".
    static func version(_ text: String) -> [Int] {
        let word = text.hasPrefix("Xray ") ? text.split(separator: " ").dropFirst().first : text.split(separator: " ").first
        return (word ?? "").drop { $0 == "v" }.split(separator: ".").compactMap { Int($0) }
    }

    static func versionLine(ofXray path: String) throws -> String {
        try run(path, ["version"]).split(separator: "\n").first.map(String.init) ?? ""
    }

    static func field(_ key: String, in text: String) -> String {
        text.split(separator: "\n").first { $0.hasPrefix(key) }
            .map { $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func download(_ url: String, to destination: URL) async throws -> URL {
        let (temp, response) = try await retrying { try await session.download(from: URL(string: url)!) }
        try check(response, url)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private static func text(_ url: String) async throws -> String {
        let (data, response) = try await retrying { try await session.data(from: URL(string: url)!) }
        try check(response, url)
        return String(decoding: data, as: UTF8.self)
    }

    /// GitHub's release downloads fail now and then (HTTP 502/503/504, dropped connections):
    /// three attempts, 2 s then 4 s apart. Other HTTP errors are returned at once.
    private static func retrying<T>(_ request: () async throws -> (T, URLResponse)) async throws -> (T, URLResponse) {
        for attempt in 1...3 {
            do {
                let result = try await request()
                let code = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
                if !(500...599).contains(code) || attempt == 3 { return result }
            } catch where attempt < 3 && error is URLError {}
            try await Task.sleep(for: .seconds(2 * attempt))
        }
        return try await request()   // not reached
    }

    private static func check(_ response: URLResponse, _ what: String) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw failure("\(URL(string: what)?.lastPathComponent ?? what): HTTP \(code)") }
    }

    static func verify(_ file: URL, expected: String) throws {
        guard expected.count == 64, try sha256(file) == expected.lowercased() else {
            throw failure(String(format: L("%@: checksum mismatch, nothing was installed"), file.lastPathComponent))
        }
    }

    static func sha256(_ file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw failure("\(tool) failed: \(text)") }
        return text
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "XrayBar", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
