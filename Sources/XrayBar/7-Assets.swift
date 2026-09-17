// 7. Assets — XrayBar's own copy of Xray and the routing data (geoip.dat, geosite.dat).
//
// This is the ONLY code in the app that uses the network, and it runs only when the user
// picks "Update Xray and Routing Data…". Every file is checked against the SHA-256 its
// upstream project publishes before it is used; nothing is swapped in unless all files pass.
// The checksums come from the same GitHub release as the files: they prove the download is
// complete and unaltered in transit, not that the upstream release itself is benign.

import CryptoKit
import Foundation

enum Assets {
    /// Same layout as v2rayN's bin directory: xray/xray, geoip.dat, geosite.dat.
    static let dir = Store.dir.appendingPathComponent("core")

    enum DataSource: String, Codable, CaseIterable, Sendable {
        case runetfreedom, loyalsoldier

        var title: String {
            switch self {
            case .runetfreedom: "runetfreedom (Russia)"
            case .loyalsoldier: "Loyalsoldier (China)"
            }
        }
        var baseURL: String {
            switch self {
            case .runetfreedom: "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/"
            case .loyalsoldier: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/"
            }
        }
    }

    #if arch(arm64)
    static let xrayZip = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-macos-arm64-v8a.zip"
    #else
    static let xrayZip = "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-macos-64.zip"
    #endif

    /// No cookies, no cache, nothing persisted by URLSession.
    private static let session = URLSession(configuration: .ephemeral)

    /// Downloads everything into a staging directory, verifies it, then replaces `dir`.
    /// Returns Xray's version line. A running session keeps its files until the next Connect.
    static func update(dataSource: DataSource, into target: URL = dir) async throws -> String {
        let staging = target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + ".new")
        let fm = FileManager.default
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging.appendingPathComponent("xray"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // Xray: zip + "SHA2-256= <hex>" line in the .dgst file next to it.
        let zip = try await download(xrayZip, to: staging.appendingPathComponent("xray.zip"))
        try verify(zip, expected: field("SHA2-256=", in: try await text(xrayZip + ".dgst")))
        let unpacked = staging.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let xray = staging.appendingPathComponent("xray/xray")
        try fm.moveItem(at: unpacked.appendingPathComponent("xray"), to: xray)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xray.path)
        try? fm.removeItem(at: unpacked)
        try? fm.removeItem(at: zip)

        // Routing data: "<hex>  <name>" in <name>.sha256sum.
        for name in ["geoip.dat", "geosite.dat"] {
            let url = dataSource.baseURL + name
            let file = try await download(url, to: staging.appendingPathComponent(name))
            try verify(file, expected: String(try await text(url + ".sha256sum").prefix { !$0.isWhitespace }))
        }

        let version = try run(xray.path, ["version"]).split(separator: "\n").first.map(String.init) ?? "Xray"
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        return version
    }

    // MARK: Helpers

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

    private static func check(_ response: URLResponse, _ url: String) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw failure("\(URL(string: url)?.lastPathComponent ?? url): HTTP \(code)") }
    }

    static func field(_ key: String, in text: String) -> String {
        text.split(separator: "\n").first { $0.hasPrefix(key) }
            .map { $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    static func verify(_ file: URL, expected: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard expected.count == 64, actual == expected.lowercased() else {
            throw failure("\(file.lastPathComponent): checksum mismatch, nothing was installed")
        }
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
