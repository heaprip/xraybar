// 4. Config — turns a profile and a routing set into Xray's config.json.
//
// Written from Xray's config documentation and from observing the configs v2rayN generates
// in TUN mode (behaviour reference only; no v2rayN code is used, see docs/DECISIONS.md D9).
// Validated on real traffic by the stage-0 PoC.

import Foundation

enum XrayConfig {
    typealias JSON = [String: Any]

    /// `ipv6`: this Mac has a global IPv6 address, so IPv6 must enter the tunnel too (D40).
    static func make(profile: Profile, routing: RoutingSet, settings: Settings, ipv6: Bool = false) -> JSON {
        [
            "log": log(settings),
            "inbounds": [tunInbound(settings, ipv6: ipv6)],
            "outbounds": [
                proxyOutbound(profile),
                ["tag": "direct", "protocol": "freedom"],
                ["tag": "block", "protocol": "blackhole"],
                ["tag": "dns-out", "protocol": "dns"],
            ],
            "dns": dns(routing, settings),
            "routing": ["domainStrategy": routing.domainStrategy, "rules": rules(routing)],
        ]
    }

    // MARK: Log

    /// Never file paths: the root session captures stdout/stderr itself (see the script).
    /// Default is errors only and no per-connection access log, so the log stays small.
    static func log(_ settings: Settings) -> JSON {
        settings.detailedLog == true
            ? ["loglevel": "warning"]                     // access log goes to stdout
            : ["loglevel": "error", "access": "none"]
    }

    // MARK: TUN inbound

    static func tunInbound(_ settings: Settings, ipv6: Bool = false) -> JSON {
        [
            "tag": "tun",
            "protocol": "tun",
            "settings": [
                "name": "utun77",
                "MTU": settings.tunMTU,
                "gateway": ["172.18.0.1/30"],
                // Xray installs these routes itself. Excluded (IPv4) networks are simply left out,
                // so the system routes them as usual. With a global IPv6 address, ::/0 too: left
                // out, IPv6 would follow the system's default route around the tunnel (D40).
                "autoSystemRoutingTable": CIDR.subtract(settings.routeExclusions ?? [], from: "0.0.0.0/0")
                    + (ipv6 ? ["::/0"] : []),
                // Outbounds bind to the physical interface, so Xray's own traffic
                // does not loop back into the tunnel (D2).
                "autoOutboundsInterface": "auto",
            ] as JSON,
            "sniffing": ["enabled": true, "destOverride": ["http", "tls"], "routeOnly": true] as JSON,
        ]
    }

    // MARK: Proxy outbound (VLESS only)

    static func proxyOutbound(_ p: Profile) -> JSON {
        var user: JSON = ["id": p.uuid, "encryption": p.encryption]
        if !p.flow.isEmpty { user["flow"] = p.flow }

        var stream: JSON = ["network": p.network]
        switch p.security {
        case "reality":
            stream["security"] = "reality"
            stream["realitySettings"] = nonEmpty([
                "serverName": p.sni, "fingerprint": p.fingerprint,
                "publicKey": p.publicKey, "shortId": p.shortId, "spiderX": p.spiderX,
            ])
        case "tls":
            stream["security"] = "tls"
            stream["tlsSettings"] = nonEmpty(["serverName": p.sni, "fingerprint": p.fingerprint])
        default:
            break
        }
        return [
            "tag": "proxy",
            "protocol": "vless",
            "settings": ["vnext": [["address": p.address, "port": p.port, "users": [user]]]],
            "streamSettings": stream,
        ]
    }

    // MARK: Routing

    static func rules(_ routing: RoutingSet) -> [JSON] {
        var out: [JSON] = [
            // In TUN mode: no LAN discovery chatter, no multicast.
            ["network": "udp", "port": "135,137-139,5353", "outboundTag": "block"],
            ["ip": ["224.0.0.0/3", "ff00::/8"], "outboundTag": "block"],
            // DNS reaching the tunnel is answered by Xray's DNS module.
            ["inboundTag": ["tun"], "port": "53", "outboundTag": "dns-out"],
            // Queries for direct domains go out direct.
            ["inboundTag": ["direct-dns"], "outboundTag": "direct"],
        ]
        out += routing.rules.flatMap(expand)
        // Everything else, including the DNS module's own queries, goes through the proxy.
        out.append(["inboundTag": ["dns-module"], "outboundTag": "proxy"])
        return out
    }

    /// One user rule becomes separate Xray rules for its domains and its IPs, because an
    /// Xray rule matches only when *all* its fields match.
    static func expand(_ r: Rule) -> [JSON] {
        guard r.enabled ?? true, r.ruleType != 2 else { return [] }   // 2: DNS-only rule
        var base: JSON = ["outboundTag": r.outboundTag.flatMap { $0.isEmpty ? nil : $0 } ?? "proxy"]
        if let v = r.port, !v.isEmpty { base["port"] = v }
        if let v = r.network, !v.isEmpty { base["network"] = v }
        if let v = r.protocol, !v.isEmpty { base["protocol"] = v }

        let domains = activeDomains(r)
        var out: [JSON] = []
        if !domains.isEmpty { out.append(base.merging(["domain": domains]) { $1 }) }
        if let ips = r.ip, !ips.isEmpty { out.append(base.merging(["ip": ips]) { $1 }) }
        if out.isEmpty && base.count > 1 { out.append(base) }   // port/network/protocol-only rule
        return out
    }

    /// `#` comments an entry out; `<COMMA>` is v2rayN's escape for commas inside regexps.
    static func activeDomains(_ r: Rule) -> [String] {
        (r.domain ?? []).filter { !$0.hasPrefix("#") }.map { $0.replacingOccurrences(of: "<COMMA>", with: ",") }
    }

    // MARK: DNS

    /// Domains of enabled direct rules are resolved by the direct resolver (outside the
    /// tunnel, so they get local answers); everything else by the remote resolvers.
    static func dns(_ routing: RoutingSet, _ settings: Settings) -> JSON {
        let directDomains = routing.rules
            .filter { ($0.enabled ?? true) && $0.outboundTag == "direct" && $0.ruleType != 1 }
            .flatMap(activeDomains)
        var servers: [Any] = []
        if !directDomains.isEmpty {
            servers += settings.directDNS.map {
                ["tag": "direct-dns", "address": $0, "domains": directDomains, "skipFallback": true] as JSON
            }
        }
        servers += settings.remoteDNS
        return ["tag": "dns-module", "servers": servers, "queryStrategy": "UseIPv4"]
    }

    // MARK: Output

    static func data(_ config: JSON) throws -> Data {
        try JSONSerialization.data(withJSONObject: config,
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Creating a utun needs root even for `xray run -test`, so validation runs on a copy
    /// with the TUN inbound swapped for a loopback SOCKS one. Everything else is identical.
    static func validationCopy(_ config: JSON) -> JSON {
        var copy = config
        copy["inbounds"] = [["tag": "tun", "protocol": "socks", "listen": "127.0.0.1", "port": 0] as JSON]
        return copy
    }

    private static func nonEmpty(_ d: [String: String]) -> [String: String] { d.filter { !$0.value.isEmpty } }
}

/// IPv4 networks, just enough to cut excluded networks out of 0.0.0.0/0.
enum CIDR {
    struct Net: Equatable { var base: UInt32; var prefix: Int }

    /// "10.0.0.0/8", or a single address meaning /32. Nil if it is not IPv4 CIDR.
    static func parse(_ text: String) -> Net? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
        let octets = parts.first?.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt32($0) } ?? []
        guard parts.count <= 2, octets.count == 4, octets.allSatisfy({ $0 < 256 }),
              let prefix = parts.count == 2 ? Int(parts[1]) : 32, (0...32).contains(prefix) else { return nil }
        let address = octets.reduce(0) { $0 << 8 | $1 }
        return Net(base: address & mask(prefix), prefix: prefix)
    }

    static func string(_ n: Net) -> String {
        (0..<4).map { String(n.base >> (24 - 8 * $0) & 0xFF) }.joined(separator: ".") + "/\(n.prefix)"
    }

    /// The fewest networks that cover `network` minus every exclusion: a network that
    /// partly overlaps an exclusion is split in halves until each half is in or out.
    static func subtract(_ exclusions: [String], from network: String) -> [String] {
        var nets = [parse(network)!]
        for ex in exclusions.compactMap(parse) {
            nets = nets.flatMap { cut(ex, from: $0) }
        }
        return nets.map(string)
    }

    private static func cut(_ ex: Net, from net: Net) -> [Net] {
        if ex.prefix <= net.prefix { return ex.base == net.base & mask(ex.prefix) ? [] : [net] }  // covers it, or apart
        guard net.base == ex.base & mask(net.prefix) else { return [net] }                        // apart
        let half = net.prefix + 1
        return [Net(base: net.base, prefix: half), Net(base: net.base | 1 << (32 - half), prefix: half)]
            .flatMap { cut(ex, from: $0) }
    }

    private static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : ~0 << (32 - prefix) }
}
