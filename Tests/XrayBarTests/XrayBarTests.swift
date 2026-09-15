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
        #expect(log["access"] == nil && log["error"] == nil)   // root session rejects file logs

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

/// Opt-in: `swift build --build-tests && XRAYBAR_INTEGRATION=1 swift test --skip-build`
/// (a changed environment makes SwiftPM rebuild, which loses the Testing macro plugin under CLT).
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
