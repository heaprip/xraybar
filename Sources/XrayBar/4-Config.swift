// 4. Config — turns a profile and a routing set into Xray's config.json.
//
// Written from Xray's config documentation and from observing the configs v2rayN generates
// in TUN mode (behaviour reference only; no v2rayN code is used, see docs/DECISIONS.md D9).
// Validated on real traffic by the stage-0 PoC.

import Foundation

enum XrayConfig {
    typealias JSON = [String: Any]

    static func make(profile: Profile, routing: RoutingSet, settings: Settings) -> JSON {
        [
            "log": log(settings),
            "inbounds": [tunInbound(settings)],
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

    static func tunInbound(_ settings: Settings) -> JSON {
        [
            "tag": "tun",
            "protocol": "tun",
            "settings": [
                "name": "utun77",
                "MTU": settings.tunMTU,
                "gateway": ["172.18.0.1/30"],
                // Xray installs these routes itself. IPv4 only until IPv6 is verified (roadmap).
                "autoSystemRoutingTable": ["0.0.0.0/0"],
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
