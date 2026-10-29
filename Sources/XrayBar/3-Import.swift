// 3. Import — getting profiles and routing sets in: share links and v2rayN.

import Foundation
import SQLite3
import Vision

enum ImportError: LocalizedError {
    case unsupported(String)
    case v2rayN(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let s): String(format: L("Unsupported link: %@"), s)
        case .v2rayN(let s): String(format: L("v2rayN import failed: %@"), s)
        }
    }
}

enum Import {
    // MARK: Share links

    /// `vless://uuid@host:port?type=tcp&security=reality&sni=…&pbk=…&sid=…&fp=…&flow=…#name`
    /// The de-facto VLESS share-link format (XTLS/Xray-core discussion #716); raw transport only.
    static func profile(fromLink link: String) throws -> Profile {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.hasPrefix("hysteria2://") || link.hasPrefix("hy2://") { return try hysteria2(link) }
        guard let url = URLComponents(string: link), url.scheme == "vless",
              let host = url.host, let port = url.port, let user = url.user, !user.isEmpty
        else { throw ImportError.unsupported(String(link.prefix(16)) + "…") }

        let q = Dictionary((url.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                           uniquingKeysWith: { first, _ in first })
        let network = q["type"].map { $0 == "tcp" ? "raw" : $0 } ?? "raw"
        guard network == "raw" else { throw ImportError.unsupported("transport \(network)") }

        return Profile(
            name: url.fragment?.removingPercentEncoding ?? host,
            address: host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
            port: port,
            uuid: user.removingPercentEncoding ?? user,
            flow: q["flow"] ?? "",
            encryption: q["encryption"].flatMap { $0.isEmpty ? nil : $0 } ?? "none",
            network: network,
            security: q["security"].flatMap { $0.isEmpty ? nil : $0 } ?? "none",
            sni: q["sni"] ?? "",
            fingerprint: q["fp"].flatMap { $0.isEmpty ? nil : $0 } ?? "chrome",
            publicKey: q["pbk"] ?? "",
            shortId: q["sid"] ?? "",
            spiderX: q["spx"] ?? "")
    }

    /// `hysteria2://password@host:port/?sni=…&obfs=salamander&obfs-password=…&pinSHA256=…#name`
    /// (Hysteria 2's URI scheme; also `hy2://`). Port hopping: a list or range in place of the
    /// port, or `mport=` as v2rayN writes it. `insecure=1` is ignored: the certificate is always
    /// checked, as v2rayN does with Xray (D51).
    static func hysteria2(_ text: String) throws -> Profile {
        // URLComponents rejects "host:443,5000-6000": keep the first port, the list goes to `ports`.
        var link = text, hop: String?
        let head = text.prefix { $0 != "?" && $0 != "#" }
        if let m = head.firstMatch(of: /:(\d+)([,-][\d,-]+)(?=\/?$)/) {
            hop = String(m.output.1 + m.output.2)
            link.replaceSubrange(m.range, with: ":" + m.output.1)
        }
        guard let url = URLComponents(string: link), let host = url.host, !host.isEmpty,
              let user = url.user, !user.isEmpty
        else { throw ImportError.unsupported(String(text.prefix(16)) + "…") }
        let q = Dictionary((url.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                           uniquingKeysWith: { first, _ in first })
        if let obfs = q["obfs"], !obfs.isEmpty, obfs != "salamander" { throw ImportError.unsupported("obfs \(obfs)") }
        return Profile(
            name: url.fragment?.removingPercentEncoding ?? host,
            address: host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
            port: url.port ?? 443,
            uuid: [user, url.password].compactMap { $0 }.joined(separator: ":"),
            network: "hysteria", security: "tls", sni: q["sni"] ?? "", fingerprint: "",
            kind: "hysteria2",
            obfsPassword: q["obfs"] == "salamander" ? q["obfs-password"] : nil,
            ports: hop ?? q["mport"].flatMap { $0.isEmpty ? nil : $0 },
            pinSHA256: q["pinSHA256"].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// The same formats in the other direction, for sharing (and QR codes).
    static func link(for p: Profile) -> String {
        var c = URLComponents()
        if p.kind == "hysteria2" {
            c.scheme = "hysteria2"
            c.user = p.uuid
            c.host = p.address.contains(":") ? "[\(p.address)]" : p.address
            c.port = p.port
            let query: [(String, String?)] = [
                ("sni", p.sni), ("obfs", p.obfsPassword.map { _ in "salamander" }), ("obfs-password", p.obfsPassword),
                ("pinSHA256", p.pinSHA256), ("mport", p.ports),
            ]
            c.queryItems = query.compactMap { k, v in v.flatMap { $0.isEmpty ? nil : URLQueryItem(name: k, value: $0) } }
            c.fragment = p.name
            return c.string ?? ""
        }
        c.scheme = "vless"
        c.user = p.uuid
        c.host = p.address.contains(":") ? "[\(p.address)]" : p.address
        c.port = p.port
        let query: [(String, String)] = [
            ("type", p.network == "raw" ? "tcp" : p.network), ("encryption", p.encryption),
            ("security", p.security), ("sni", p.sni), ("fp", p.fingerprint), ("pbk", p.publicKey),
            ("sid", p.shortId), ("spx", p.spiderX), ("flow", p.flow),
        ]
        c.queryItems = query.filter { !$0.1.isEmpty }.map { URLQueryItem(name: $0.0, value: $0.1) }
        c.fragment = p.name
        return c.string ?? ""
    }

    // MARK: Subscriptions (D59)

    /// A subscription's body: share links, one per line, plain or base64 (as v2rayN and v2rayNG
    /// serve them), or a JSON array of full Xray configs, of which only the proxy outbound is
    /// used: routing stays with XrayBar's routing sets. What XrayBar cannot use is skipped.
    static func subscription(_ body: String) -> [Profile] {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
            let configs = json as? [[String: Any]] ?? (json as? [String: Any]).map { [$0] } ?? []
            return configs.compactMap(profile(fromConfig:))
        }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            .filter { !$0.isWhitespace }
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let lines = Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) } ?? text
        return lines.split(whereSeparator: \.isNewline).compactMap { try? profile(fromLink: String($0)) }
    }

    /// The proxy outbound of a full Xray config (tag "proxy", else the first VLESS or Hysteria
    /// one), read back into a profile: the inverse of 4-Config's proxyOutbound.
    static func profile(fromConfig config: [String: Any]) -> Profile? {
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        guard let o = outbounds.first(where: { $0["tag"] as? String == "proxy" })
                ?? outbounds.first(where: { ["vless", "hysteria"].contains($0["protocol"] as? String) })
        else { return nil }
        let dict = { (d: Any?, key: String) in (d as? [String: Any])?[key] as? [String: Any] ?? [:] }
        let int = { (v: Any?) in v as? Int ?? (v as? String).flatMap { Int($0) } }
        let settings = o["settings"] as? [String: Any] ?? [:]
        let stream = o["streamSettings"] as? [String: Any] ?? [:]
        let name = config["remarks"] as? String

        switch o["protocol"] as? String {
        case "hysteria":
            let tls = dict(stream, "tlsSettings"), finalmask = dict(stream, "finalmask")
            let masks = finalmask["udp"] as? [[String: Any]] ?? []
            guard let address = settings["address"] as? String, let port = int(settings["port"]),
                  let auth = dict(stream, "hysteriaSettings")["auth"] as? String,
                  masks.allSatisfy({ $0["type"] as? String == "salamander" })   // gecko: not supported (D51)
            else { return nil }
            return Profile(name: name ?? address, address: address, port: port, uuid: auth,
                           network: "hysteria", security: "tls", sni: tls["serverName"] as? String ?? "",
                           fingerprint: "", kind: "hysteria2",
                           obfsPassword: masks.first.flatMap { dict($0, "settings")["password"] as? String },
                           ports: dict(finalmask["quicParams"], "udpHop")["ports"] as? String,
                           pinSHA256: tls["pinnedPeerCertSha256"] as? String)
        case "vless":
            // Older configs nest the server in vnext[0].users[0]; newer ones put it in settings.
            let server = (settings["vnext"] as? [[String: Any]])?.first ?? settings
            let user = (server["users"] as? [[String: Any]])?.first ?? server
            let network = (stream["network"] as? String).map { $0 == "tcp" ? "raw" : $0 } ?? "raw"
            let security = stream["security"] as? String ?? "none"
            let reality = dict(stream, "realitySettings"), tls = dict(stream, "tlsSettings")
            let s = security == "reality" ? reality : tls
            guard network == "raw", let address = server["address"] as? String, let port = int(server["port"]),
                  let id = user["id"] as? String else { return nil }
            return Profile(name: name ?? address, address: address, port: port, uuid: id,
                           flow: user["flow"] as? String ?? "",
                           encryption: user["encryption"] as? String ?? "none", network: network, security: security,
                           sni: s["serverName"] as? String ?? "", fingerprint: s["fingerprint"] as? String ?? "chrome",
                           publicKey: reality["password"] as? String ?? reality["publicKey"] as? String ?? "",
                           shortId: reality["shortId"] as? String ?? "", spiderX: reality["spiderX"] as? String ?? "")
        default:
            return nil
        }
    }

    // MARK: QR codes

    /// Text of every QR code found in an image (Vision, on-device).
    static func qrCodes(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }

    // MARK: v2rayN (one-time, read-only)

    static let v2rayNDatabase = NSHomeDirectory() + "/Library/Application Support/v2rayN/guiConfigs/guiNDB.db"

    /// Reads VLESS and Hysteria 2 profiles and routing sets from v2rayN's SQLite database, read-only.
    /// Hysteria 2 servers using what Xray here does not (gecko obfs, realm) are left out.
    static func fromV2rayN(path: String = v2rayNDatabase) throws -> (profiles: [Profile], routing: [RoutingSet]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else { throw ImportError.v2rayN("cannot open \(path)") }
        defer { sqlite3_close(db) }

        let profiles = try rows(db, """
            select Remarks, Address, Port, Password, Network, StreamSecurity, Sni, Fingerprint,
                   PublicKey, ShortId, SpiderX, ProtoExtra, ConfigType, CertSha from ProfileItem
            where ConfigType in (5, 7)
            """).compactMap { r -> Profile? in
            let extra = (try? JSONSerialization.jsonObject(with: Data(r[11].utf8))) as? [String: Any] ?? [:]
            let text = { (key: String) in (extra[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            if r[12] == "7" {   // EConfigType.Hysteria2
                guard ["GeckoMinPacketSize", "GeckoMaxPacketSize", "Hy2RealmUrl"].allSatisfy({ text($0) == nil }) else { return nil }
                return Profile(name: r[0], address: r[1], port: Int(r[2]) ?? 443, uuid: r[3], network: "hysteria",
                               security: "tls", sni: r[6], fingerprint: "", kind: "hysteria2",
                               obfsPassword: text("SalamanderPass"), ports: text("Ports")?.replacingOccurrences(of: ":", with: "-"),
                               pinSHA256: r[13].isEmpty ? nil : r[13])
            }
            return Profile(
                name: r[0], address: r[1], port: Int(r[2]) ?? 443, uuid: r[3],
                flow: extra["Flow"] as? String ?? "",
                encryption: (extra["VlessEncryption"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "none",
                network: r[4] == "tcp" || r[4].isEmpty ? "raw" : r[4],
                security: r[5].isEmpty ? "none" : r[5], sni: r[6],
                fingerprint: r[7].isEmpty ? "chrome" : r[7],
                publicKey: r[8], shortId: r[9], spiderX: r[10])
        }

        let routing = try rows(db, "select Remarks, DomainStrategy, RuleSet from RoutingItem order by Sort")
            .compactMap { r -> RoutingSet? in
                guard let rules = try? JSONDecoder().decode([Rule].self, from: Data(r[2].utf8)) else { return nil }
                return RoutingSet(name: r[0], domainStrategy: r[1].isEmpty ? "AsIs" : r[1], rules: rules)
            }
        return (profiles, routing)
    }

    /// Adds imported items, skipping ones already present (same server and user / same name and rules).
    @discardableResult
    static func merge(_ imported: (profiles: [Profile], routing: [RoutingSet]), into library: inout Library) -> Int {
        var added = 0
        for p in imported.profiles where !library.profiles.contains(where: {
            $0.address == p.address && $0.port == p.port && $0.uuid == p.uuid
        }) {
            library.profiles.append(p); added += 1
        }
        for r in imported.routing where !library.routingSets.contains(where: { $0.name == r.name && $0.rules == r.rules }) {
            library.routingSets.append(r); added += 1
        }
        return added
    }

    private static func rows(_ db: OpaquePointer?, _ sql: String) throws -> [[String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK
        else { throw ImportError.v2rayN(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(stmt) }
        var result: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(stmt)).map { i in
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            })
        }
        return result
    }
}

