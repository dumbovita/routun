import Foundation

public final class SingBoxConfigBuilder {
    public static func build(
        policy: RoutePolicy,
        socksHost: String = "127.0.0.1",
        socksPort: Int = 1080
    ) -> [String: Any] {
        let (bypassedSuffixes, excludedSuffixes) = policy.resolveTargets()

        var tunAddresses = ["172.19.0.1/30"]
        if policy.enableIPv6 {
            tunAddresses.append("fdfe:dcba:9876::1/126")
        }

        let inbounds: [[String: Any]] = [
            [
                "type": "tun",
                "tag": "tun-in",
                "address": tunAddresses,
                "auto_route": true,
                "strict_route": true,
                "stack": "system",
                "dns_mode": policy.dnsMode == .doh ? "route" : "disabled"
            ]
        ]

        let outbounds: [[String: Any]] = [
            [
                "type": "socks",
                "tag": "byedpi-out",
                "server": socksHost,
                "server_port": socksPort
            ],
            [
                "type": "direct",
                "tag": "direct"
            ]
        ]

        var rules: [[String: Any]] = [
            // 1. Sniffer rule for protocol and SNI/Host inspection
            [
                "action": "sniff",
                "sniffer": ["tls", "http", "quic"],
                "timeout": "500ms"
            ],
            // 2. Direct rule for proxy processes to prevent routing loops
            [
                "process_name": ["ciadpi", "sing-box"],
                "action": "route",
                "outbound": "direct"
            ],
            // 3. Direct rule for private and local IP ranges
            [
                "ip_is_private": true,
                "action": "route",
                "outbound": "direct"
            ]
        ]

        // 4. User explicit exclusions
        if !excludedSuffixes.isEmpty {
            rules.append([
                "domain_suffix": excludedSuffixes,
                "action": "route",
                "outbound": "direct"
            ])
        }

        // 5. QUIC handling
        switch policy.quicMode {
        case .scoped:
            if policy.mode == .selective {
                if !bypassedSuffixes.isEmpty {
                    rules.append([
                        "domain_suffix": bypassedSuffixes,
                        "network": "udp",
                        "port": 443,
                        "action": "reject",
                        "method": "default",
                        "no_drop": true
                    ])
                }
            } else {
                rules.append([
                    "network": "udp",
                    "port": 443,
                    "action": "reject",
                    "method": "default",
                    "no_drop": true
                ])
            }
        case .blocked:
            rules.append([
                "network": "udp",
                "port": 443,
                "action": "reject",
                "method": "default",
                "no_drop": true
            ])
        case .direct:
            break
        }

        // 6. Direct rule for general UDP traffic
        rules.append([
            "network": "udp",
            "action": "route",
            "outbound": "direct"
        ])

        // 7. TCP web traffic DPI bypass rule
        if policy.mode == .selective {
            if !bypassedSuffixes.isEmpty {
                rules.append([
                    "domain_suffix": bypassedSuffixes,
                    "network": "tcp",
                    "port": [80, 443],
                    "action": "route",
                    "outbound": "byedpi-out"
                ])
            }
        } else {
            rules.append([
                "network": "tcp",
                "port": [80, 443],
                "action": "route",
                "outbound": "byedpi-out"
            ])
        }

        var routeConfig: [String: Any] = [
            "rules": rules,
            "final": "direct",
            "auto_detect_interface": true
        ]
        if policy.dnsMode == .doh {
            routeConfig["default_domain_resolver"] = "cloudflare-doh"
        }

        var config: [String: Any] = [
            "$schema": "https://sing-box.sagernet.org/schema.json",
            "log": [
                "level": "info",
                "timestamp": true
            ],
            "inbounds": inbounds,
            "outbounds": outbounds,
            "route": routeConfig
        ]

        // 8. Optional DoH handling if enabled (sing-box 1.14 typed DNS format)
        if policy.dnsMode == .doh {
            config["dns"] = [
                "servers": [
                    [
                        "tag": "cloudflare-doh",
                        "type": "https",
                        "server": "1.1.1.1",
                        "detour": "direct"
                    ]
                ],
                "final": "cloudflare-doh",
                "strategy": "prefer_ipv4"
            ]
        }

        return config
    }

    /// Build and serialize sing-box configuration to pretty-printed JSON data
    public static func buildJsonData(
        policy: RoutePolicy,
        socksHost: String = "127.0.0.1",
        socksPort: Int = 1080
    ) throws -> Data {
        let dict = build(policy: policy, socksHost: socksHost, socksPort: socksPort)
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    /// Build and serialize sing-box configuration to JSON string
    public static func buildJsonString(
        policy: RoutePolicy,
        socksHost: String = "127.0.0.1",
        socksPort: Int = 1080
    ) throws -> String {
        let data = try buildJsonData(policy: policy, socksHost: socksHost, socksPort: socksPort)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return string
    }

    /// Validate a JSON configuration string using the installed sing-box binary
    public static func validate(configJson: String, singboxPath: String) -> (isValid: Bool, error: String?) {
        guard FileManager.default.isExecutableFile(atPath: singboxPath) else {
            return (false, "sing-box binary not executable at \(singboxPath)")
        }

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("singbox-check-\(UUID().uuidString).json")
        do {
            try configJson.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: singboxPath)
            proc.arguments = ["check", "-c", tempFile.path]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 {
                return (true, nil)
            } else {
                let errOutput = String(data: data, encoding: .utf8) ?? "sing-box check returned \(proc.terminationStatus)"
                return (false, errOutput)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
