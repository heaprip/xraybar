// 1. Model — everything XrayBar knows about. Plain values, no behaviour.
//
// Read the files in numeric order: 1-Model, 2-Store, 3-Import, 4-Config, 5-Session, 6-Menu.

import Foundation

/// A VLESS server. Other protocols are added only when actually needed.
struct Profile: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var address: String
    var port: Int
    var uuid: String
    var flow = ""
    var encryption = "none"
    var network = "raw"          // Xray transport; "tcp" in share links
    var security = "reality"     // "reality" | "tls" | "none"
    var sni = ""
    var fingerprint = "chrome"
    var publicKey = ""           // reality
    var shortId = ""             // reality
    var spiderX = ""             // reality
}

/// One routing rule, in v2rayN's `RulesItem` shape so v2rayN routing sets and
/// runetfreedom templates import unchanged (docs/DECISIONS.md D6).
struct Rule: Codable, Equatable, Sendable {
    var remarks: String?
    var outboundTag: String?     // "proxy" | "direct" | "block"
    var domain: [String]?        // "geosite:ru", "domain:example.com", "full:…", "#disabled"
    var ip: [String]?            // "geoip:private", CIDR
    var port: String?
    var network: String?
    var `protocol`: [String]?
    var enabled: Bool?
    var ruleType: Int?           // v2rayN ERuleType: 0 all, 1 routing only, 2 DNS only

    enum CodingKeys: String, CodingKey {
        case remarks = "Remarks", outboundTag = "OutboundTag", domain = "Domain", ip = "Ip"
        case port = "Port", network = "Network", `protocol` = "Protocol"
        case enabled = "Enabled", ruleType = "RuleType"
    }
}

/// An ordered list of rules; first match wins. Unmatched traffic goes to the proxy.
struct RoutingSet: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var domainStrategy = "AsIs"  // Xray: AsIs | IPIfNonMatch | IPOnDemand
    var rules: [Rule]
}

struct Settings: Codable, Equatable, Sendable {
    /// Directory with `xray/xray`, `geoip.dat`, `geosite.dat` (D8: v2rayN's by default).
    var assetsDir = NSHomeDirectory() + "/Library/Application Support/v2rayN/bin"
    var xrayPath: String { assetsDir + "/xray/xray" }
    /// Resolver for domains routed direct, and for everything else (through the proxy).
    var directDNS = ["77.88.8.8"]
    var remoteDNS = ["https://dns.google/dns-query", "8.8.8.8", "1.1.1.1"]
    /// Set as system DNS while connected; these addresses route into the tunnel (D3).
    var systemDNS = ["1.1.1.1", "8.8.8.8"]
    var tunMTU = 9000
}

/// Everything persisted, in one file.
struct Library: Codable, Equatable, Sendable {
    var profiles: [Profile] = []
    var routingSets: [RoutingSet] = [RoutingSet.global]
    var selectedProfile: UUID?
    var selectedRouting: UUID?
    var settings = Settings()

    var profile: Profile? { profiles.first { $0.id == selectedProfile } ?? profiles.first }
    var routing: RoutingSet { routingSets.first { $0.id == selectedRouting } ?? routingSets.first ?? .global }
}

extension RoutingSet {
    /// Fallback when nothing is imported: LAN direct, ads blocked, everything else proxied.
    static let global = RoutingSet(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Global",
        rules: [
            Rule(remarks: "Block ads", outboundTag: "block", domain: ["geosite:category-ads-all"]),
            Rule(remarks: "LAN direct", outboundTag: "direct", ip: ["geoip:private"]),
            Rule(remarks: "LAN domains direct", outboundTag: "direct", domain: ["geosite:private"]),
        ])
}
