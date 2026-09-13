import Foundation
import Testing
@testable import routun

@Suite("sing-box Config Builder Tests")
struct SingBoxConfigBuilderTests {
    @Test("Generates valid dual-stack TUN configuration when IPv6 is enabled")
    func dualStackTUN() {
        let policy = RoutePolicy(enableIPv6: true)
        let config = SingBoxConfigBuilder.build(policy: policy, socksHost: "127.0.0.1", socksPort: 1080)

        guard let inbounds = config["inbounds"] as? [[String: Any]],
              let tun = inbounds.first(where: { ($0["type"] as? String) == "tun" }) else {
            Issue.record("Expected tun inbound")
            return
        }

        #expect(tun["tag"] as? String == "tun-in")
        #expect(tun["auto_route"] as? Bool == true)
        #expect(tun["strict_route"] as? Bool == true)

        let addresses = tun["address"] as? [String] ?? []
        #expect(addresses.contains("172.19.0.1/30"))
        #expect(addresses.contains("fdfe:dcba:9876::1/126"))
    }

    @Test("Excludes IPv6 address when IPv6 is disabled in policy")
    func singleStackIPv4TUN() {
        let policy = RoutePolicy(enableIPv6: false)
        let config = SingBoxConfigBuilder.build(policy: policy)

        guard let inbounds = config["inbounds"] as? [[String: Any]],
              let tun = inbounds.first(where: { ($0["type"] as? String) == "tun" }) else {
            Issue.record("Expected tun inbound")
            return
        }

        let addresses = tun["address"] as? [String] ?? []
        #expect(addresses == ["172.19.0.1/30"])
    }

    @Test("Selective routing restricts byedpi-out to bypassed domain suffixes")
    func selectiveRoutingRules() {
        let policy = RoutePolicy(
            mode: .selective,
            groupPreferences: ["turkiye": true, "youtube": false, "general": false, "social": false, "telegram": false, "cloudflare": false],
            customInclude: ["custom-site.org"]
        )
        let config = SingBoxConfigBuilder.build(policy: policy)
        guard let route = config["route"] as? [String: Any],
              let rules = route["rules"] as? [[String: Any]] else {
            Issue.record("Expected route rules")
            return
        }

        // Must have sniffer, process protection, and private IP bypass
        #expect(rules.contains { ($0["action"] as? String) == "sniff" })
        #expect(rules.contains { rule in
            guard let procs = rule["process_name"] as? [String] else { return false }
            return procs.contains("ciadpi") && procs.contains("sing-box") && (rule["outbound"] as? String) == "direct"
        })
        #expect(rules.contains { ($0["ip_is_private"] as? Bool) == true && ($0["outbound"] as? String) == "direct" })

        // Selective TCP routing rule must have domain_suffix filter
        let tcpBypassRule = rules.first { rule in
            (rule["network"] as? String) == "tcp" && (rule["outbound"] as? String) == "byedpi-out"
        }
        #expect(tcpBypassRule != nil)
        let suffixes = tcpBypassRule?["domain_suffix"] as? [String] ?? []
        #expect(suffixes.contains("custom-site.org"))
        #expect(suffixes.contains("roblox.com"))
        #expect(!suffixes.contains("youtube.com"))
    }

    @Test("Global routing routes all public TCP web traffic to byedpi-out without domain restriction")
    func globalRoutingRules() {
        let policy = RoutePolicy(mode: .global)
        let config = SingBoxConfigBuilder.build(policy: policy)
        guard let route = config["route"] as? [String: Any],
              let rules = route["rules"] as? [[String: Any]] else {
            Issue.record("Expected route rules")
            return
        }

        let tcpBypassRule = rules.first { rule in
            (rule["network"] as? String) == "tcp" && (rule["outbound"] as? String) == "byedpi-out"
        }
        #expect(tcpBypassRule != nil)
        #expect(tcpBypassRule?["domain_suffix"] == nil)
    }

    @Test("QUIC handling respects scoped, blocked, and direct modes")
    func quicModes() {
        // Scoped in selective mode: rejects UDP/443 only for bypassed domains
        let scopedPolicy = RoutePolicy(
            mode: .selective,
            quicMode: .scoped,
            customInclude: ["example.com"]
        )
        let scopedConfig = SingBoxConfigBuilder.build(policy: scopedPolicy)
        let scopedRules = (scopedConfig["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let scopedQuic = scopedRules.first { rule in
            (rule["action"] as? String) == "reject" && (rule["network"] as? String) == "udp"
        }
        #expect(scopedQuic != nil)
        #expect(scopedQuic?["domain_suffix"] != nil)

        // Blocked mode: rejects UDP/443 globally without domain filter
        let blockedPolicy = RoutePolicy(quicMode: .blocked)
        let blockedConfig = SingBoxConfigBuilder.build(policy: blockedPolicy)
        let blockedRules = (blockedConfig["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let blockedQuic = blockedRules.first { rule in
            (rule["action"] as? String) == "reject" && (rule["network"] as? String) == "udp"
        }
        #expect(blockedQuic != nil)
        #expect(blockedQuic?["domain_suffix"] == nil)

        // Direct mode: no UDP/443 rejection rule
        let directPolicy = RoutePolicy(quicMode: .direct)
        let directConfig = SingBoxConfigBuilder.build(policy: directPolicy)
        let directRules = (directConfig["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let directQuic = directRules.first { rule in
            (rule["action"] as? String) == "reject" && (rule["network"] as? String) == "udp"
        }
        #expect(directQuic == nil)
    }

    @Test("Process protection rule includes both ciadpi and sing-box")
    func processProtectionRule() {
        let config = SingBoxConfigBuilder.build(policy: RoutePolicy())
        let rules = (config["route"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let processRule = rules.first { ($0["action"] as? String) == "route" && ($0["process_name"] as? [String]) != nil }
        let names = processRule?["process_name"] as? [String] ?? []
        #expect(names.contains("ciadpi"))
        #expect(names.contains("sing-box"))
        #expect(processRule?["outbound"] as? String == "direct")
    }

    @Test("DoH configuration generates valid sing-box 1.14 typed DNS and default resolver")
    func dohDnsConfiguration() throws {
        let policy = RoutePolicy(dnsMode: .doh)
        let config = SingBoxConfigBuilder.build(policy: policy)

        guard let route = config["route"] as? [String: Any] else {
            Issue.record("Expected route object")
            return
        }
        #expect(route["default_domain_resolver"] as? String == "cloudflare-doh")

        guard let dns = config["dns"] as? [String: Any],
              let servers = dns["servers"] as? [[String: Any]],
              let firstServer = servers.first else {
            Issue.record("Expected dns.servers")
            return
        }

        #expect(firstServer["tag"] as? String == "cloudflare-doh")
        #expect(firstServer["type"] as? String == "https")
        #expect(firstServer["server"] as? String == "1.1.1.1")
        #expect(dns["final"] as? String == "cloudflare-doh")

        guard let singboxPath = RoutunConfig.resolveBinary(named: "sing-box") else {
            return
        }

        let jsonString = try SingBoxConfigBuilder.buildJsonString(policy: policy)
        let (isValid, error) = SingBoxConfigBuilder.validate(configJson: jsonString, singboxPath: singboxPath)
        #expect(isValid == true, "sing-box check failed for DoH configuration: \(error ?? "unknown error")")
    }

    @Test("sing-box check validates all policy permutations")
    func singBoxCheckAllPermutations() throws {
        guard let singboxPath = RoutunConfig.resolveBinary(named: "sing-box") else {
            return
        }

        let modes = RoutingMode.allCases
        let quicModes = QUICMode.allCases
        let dnsModes = DNSMode.allCases
        let ipv6Options = [true, false]
        let targetScenarios: [([String], [String: Bool])] = [
            (["custom-test.org"], [:]),
            ([], ["general": false, "social": false, "turkiye": false, "youtube": false, "telegram": false, "cloudflare": false])
        ]

        for (customInc, groupPrefs) in targetScenarios {
            for mode in modes {
                for quic in quicModes {
                    for dns in dnsModes {
                        for ipv6 in ipv6Options {
                            let policy = RoutePolicy(
                                mode: mode,
                                quicMode: quic,
                                dnsMode: dns,
                                enableIPv6: ipv6,
                                groupPreferences: groupPrefs,
                                customInclude: customInc
                            )
                            let jsonString = try SingBoxConfigBuilder.buildJsonString(policy: policy)
                            let (isValid, error) = SingBoxConfigBuilder.validate(configJson: jsonString, singboxPath: singboxPath)
                            #expect(isValid == true, "sing-box check failed for mode=\(mode), quic=\(quic), dns=\(dns), ipv6=\(ipv6), targets=\(customInc.isEmpty ? "empty" : "included"): \(error ?? "nil")")
                        }
                    }
                }
            }
        }
    }
}
