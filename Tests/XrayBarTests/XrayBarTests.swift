import Foundation
import Testing
@testable import XrayBar

@Suite struct ImportTests {
    @Test func vlessRealityLink() throws {
        let p = try Import.profile(fromLink:
            "vless://11111111-2222-3333-4444-555555555555@example.com:443?type=tcp&security=reality&sni=www.apple.com&fp=chrome&pbk=PUBKEY&sid=ab12&flow=xtls-rprx-vision#My%20Server")
        #expect(p.name == "My Server")
        #expect(p.address == "example.com" && p.port == 443)
        #expect(p.uuid == "11111111-2222-3333-4444-555555555555")
        #expect(p.network == "raw" && p.security == "reality")
        #expect(p.sni == "www.apple.com" && p.publicKey == "PUBKEY" && p.shortId == "ab12")
        #expect(p.flow == "xtls-rprx-vision" && p.encryption == "none")
    }

    @Test func rejectsOtherSchemesAndTransports() {
        #expect(throws: ImportError.self) { try Import.profile(fromLink: "vmess://abc") }
        #expect(throws: ImportError.self) { try Import.profile(fromLink: "vless://u@h:443?type=ws") }
    }

    @Test func v2rayNRuleSetDecodes() throws {
        let json = #"[{"Id":"1","OutboundTag":"direct","Domain":["geosite:private"],"Ip":null,"Enabled":true,"RuleType":null,"Remarks":"LAN"}]"#
        let rules = try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
        #expect(rules == [Rule(remarks: "LAN", outboundTag: "direct", domain: ["geosite:private"], enabled: true)])
    }
}

@Suite struct ConfigTests {
    let profile = Profile(name: "t", address: "1.2.3.4", port: 443, uuid: "u", flow: "xtls-rprx-vision",
                          sni: "s", publicKey: "k", shortId: "i")

    @Test func ruleWithDomainsAndIPsSplitsInTwo() {
        let r = Rule(outboundTag: "direct", domain: ["geosite:ru", "#off", "regexp:a<COMMA>b"], ip: ["geoip:ru"])
        let out = XrayConfig.expand(r)
        #expect(out.count == 2)
        #expect(out[0]["domain"] as? [String] == ["geosite:ru", "regexp:a,b"])
        #expect(out[1]["ip"] as? [String] == ["geoip:ru"])
        #expect(out.allSatisfy { $0["outboundTag"] as? String == "direct" })
    }

    @Test func disabledAndDNSOnlyRulesAreSkipped() {
        #expect(XrayConfig.expand(Rule(domain: ["a"], enabled: false)).isEmpty)
        #expect(XrayConfig.expand(Rule(domain: ["a"], ruleType: 2)).isEmpty)
    }

    @Test func portOnlyRuleIsKept() {
        let out = XrayConfig.expand(Rule(outboundTag: "proxy", port: "0-65535"))
        #expect(out.count == 1 && out[0]["port"] as? String == "0-65535")
    }

    @Test func configShape() throws {
        let c = XrayConfig.make(profile: profile, routing: .global, settings: Settings())
        let inbound = try #require((c["inbounds"] as? [[String: Any]])?.first)
        #expect(inbound["protocol"] as? String == "tun")
        let tun = try #require(inbound["settings"] as? [String: Any])
        #expect(tun["autoSystemRoutingTable"] as? [String] == ["0.0.0.0/0"])
        #expect(tun["autoOutboundsInterface"] as? String == "auto")

        let log = try #require(c["log"] as? [String: Any])
        #expect(log["loglevel"] as? String == "error" && log["access"] as? String == "none")
        #expect(log["error"] == nil)                             // root session rejects file logs
        var verbose = Settings(); verbose.detailedLog = true
        #expect(XrayConfig.log(verbose)["access"] == nil)

        let rules = try #require((c["routing"] as? [String: Any])?["rules"] as? [[String: Any]])
        #expect(rules.allSatisfy { $0["process"] == nil })       // D2
        #expect(rules.last?["inboundTag"] as? [String] == ["dns-module"])

        let dns = try #require(c["dns"] as? [String: Any])
        let direct = try #require((dns["servers"] as? [Any])?.first as? [String: Any])
        #expect(direct["domains"] as? [String] == ["geosite:private"])
    }

    @Test func validationCopyHasNoTun() {
        let c = XrayConfig.validationCopy(XrayConfig.make(profile: profile, routing: .global, settings: Settings()))
        #expect((c["inbounds"] as? [[String: Any]])?.first?["protocol"] as? String == "socks")
    }
}

@Suite struct QuotingTests {
    @Test func shellAndAppleScript() {
        #expect(Session.shellQuoted("a'b") == #"'a'\''b'"#)
        #expect(Session.appleScriptEscaped(#"x "y" \z"#) == #"x \"y\" \\z"#)
    }
}

/// Opt-in: `scripts/test.sh --integration`.
/// Reads the local v2rayN database (read-only), generates a config for every imported server/routing pair and runs `xray run -test` on it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XRAYBAR_INTEGRATION"] != nil))
struct IntegrationTests {
    @Test func v2rayNImportProducesConfigsXrayAccepts() throws {
        let imported = try Import.fromV2rayN()
        #expect(!imported.profiles.isEmpty)
        let settings = Settings()
        for routing in imported.routing {
            let config = XrayConfig.validationCopy(
                XrayConfig.make(profile: imported.profiles[0], routing: routing, settings: settings))
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("xraybar-test.json")
            try XrayConfig.data(config).write(to: file)
            let xray = Process()
            xray.executableURL = URL(fileURLWithPath: settings.xrayPath)
            xray.arguments = ["run", "-test", "-c", file.path]
            xray.environment = ["XRAY_LOCATION_ASSET": settings.assetsDir]
            xray.standardOutput = FileHandle.nullDevice
            xray.standardError = FileHandle.nullDevice
            try xray.run()
            xray.waitUntilExit()
            try? FileManager.default.removeItem(at: file)
            #expect(xray.terminationStatus == 0, "routing set \(routing.name)")
        }
    }
}

@Suite struct StoreTests {
    /// A library.json written before `detailedLog` existed must still load (CLAUDE.md rule).
    @Test func settingsWithoutNewerFieldsDecode() throws {
        let json = #"{"assetsDir":"/x","directDNS":[],"remoteDNS":[],"systemDNS":[],"tunMTU":1500}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(s.detailedLog == nil && s.tunMTU == 1500)
    }
}

@Suite struct AssetsTests {
    @Test func versionParsingAndMinimum() {
        #expect(Assets.version("Xray 26.9.9 (Xray, Penetrates Everything.) 52a412d") == [26, 9, 9])
        #expect(Assets.version("v26.10.1") == [26, 10, 1])
        #expect(Assets.field("SHA2-256=", in: "MD5= aa\nSHA2-256= 2e93\n") == "2e93")
        #expect(Assets.version("Xray 26.3.27 (Xray…)").lexicographicallyPrecedes(Assets.minimumXray))
        #expect(!Assets.version("Xray 26.5.9 (Xray…)").lexicographicallyPrecedes(Assets.minimumXray))
        #expect(!Assets.version("Xray 26.10.1 (Xray…)").lexicographicallyPrecedes(Assets.minimumXray))
    }

    @Test func checksumMismatchIsRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("xraybar-sum.txt")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try Assets.verify(file, expected: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(throws: NSError.self) { try Assets.verify(file, expected: String(repeating: "0", count: 64)) }
        #expect(throws: NSError.self) { try Assets.verify(file, expected: "") }
    }
}

/// Opt-in (downloads ~130 MB): `scripts/test.sh --integration`. Installs into a temp directory.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XRAYBAR_INTEGRATION"] != nil))
struct AssetsDownloadTests {
    @Test func installsVersionsAndData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xraybar-core-test")
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        // The tested version (pinned hash) and one other release (.dgst hash).
        let tested = try await Assets.installXray(Assets.testedXray, in: root)
        #expect(Assets.version(try Assets.versionLine(ofXray: tested)) == Assets.version(Assets.testedXray))
        let available = try await Assets.availableXray()
        #expect(available.contains(Assets.testedXray))
        let other = try #require(available.first { $0 != Assets.testedXray })
        _ = try await Assets.installXray(other, in: root)
        #expect(Set(Assets.installedXray(in: root)) == [Assets.testedXray, other])

        try await Assets.updateData(.runetfreedom, in: root)
        for f in ["geoip.dat", "geosite.dat"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(f).path), "\(f)")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(f + ".new").path))
        }
    }
}

@Suite struct ShareTests {
    let profile = Profile(name: "My Server / DE", address: "example.com", port: 8443,
                          uuid: "11111111-2222-3333-4444-555555555555", flow: "xtls-rprx-vision",
                          sni: "www.apple.com", publicKey: "PUB-key_1", shortId: "ab12")

    @Test func linkRoundTrip() throws {
        var back = try Import.profile(fromLink: Import.link(for: profile))
        back.id = profile.id
        #expect(back == profile)
    }

    @MainActor @Test func qrRoundTrip() throws {
        let link = Import.link(for: profile)
        let image = AppModel.qrImage(link, size: 300)
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(try Import.qrCodes(in: cg) == [link])
    }
}

@Suite struct CIDRTests {
    @Test func parse() {
        #expect(CIDR.parse("10.1.2.3/8") == CIDR.Net(base: 0x0A00_0000, prefix: 8))
        #expect(CIDR.parse("192.168.1.10") == CIDR.Net(base: 0xC0A8_010A, prefix: 32))
        for bad in ["", "10.0.0/8", "256.0.0.0/8", "10.0.0.0/33", "fe80::/10", "10.0.0.0/8/1", "a.b.c.d"] {
            #expect(CIDR.parse(bad) == nil, "\(bad)")
        }
    }

    @Test func nothingExcludedKeepsEverything() {
        #expect(CIDR.subtract([], from: "0.0.0.0/0") == ["0.0.0.0/0"])
    }

    @Test func excludingOneHalf() {
        #expect(CIDR.subtract(["0.0.0.0/1"], from: "0.0.0.0/0") == ["128.0.0.0/1"])
    }

    @Test func excludingOneAddressLeaves32Networks() {
        let rest = CIDR.subtract(["203.0.113.7"], from: "0.0.0.0/0")
        #expect(rest.count == 32)
        #expect(!rest.contains { CIDR.parse($0)!.prefix == 32 && $0.hasPrefix("203.0.113.7") })
        // Coverage: 2^32 - 1 addresses remain.
        let total = rest.map { UInt64(1) << (32 - CIDR.parse($0)!.prefix) }.reduce(0, +)
        #expect(total == (UInt64(1) << 32) - 1)
    }

    @Test func overlappingExclusionsAndGarbageIgnored() {
        let rest = CIDR.subtract(["10.0.0.0/8", "10.1.0.0/16", "nonsense"], from: "0.0.0.0/0")
        let total = rest.map { UInt64(1) << (32 - CIDR.parse($0)!.prefix) }.reduce(0, +)
        #expect(total == (UInt64(1) << 32) - (UInt64(1) << 24))
        #expect(rest.count == 8)
    }
}
