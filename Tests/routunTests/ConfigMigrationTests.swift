import Foundation
import Testing
@testable import routun

@Suite("Config Migration Tests")
struct ConfigMigrationTests {
    @Test("Decodes legacy v1.3.1 configuration JSON and backfills policy defaults")
    func decodeLegacyConfig() throws {
        let legacyJson = """
        {
            "ciadpi_path": "/opt/homebrew/bin/ciadpi",
            "singbox_path": "/opt/homebrew/bin/sing-box",
            "ciadpi_args": [
                "-i", "127.0.0.1",
                "-p", "1080",
                "-s", "1",
                "-t", "3",
                "-d", "3+s",
                "-r", "1+s"
            ],
            "socks_host": "127.0.0.1",
            "socks_port": 1080,
            "singbox_config": "/Library/Application Support/routun/config/singbox.json",
            "selected_profile": "default"
        }
        """

        let data = try #require(legacyJson.data(using: .utf8))
        let config = try JSONDecoder().decode(RoutunConfig.self, from: data)

        // Core fields preserved
        #expect(config.ciadpiPath == "/opt/homebrew/bin/ciadpi")
        #expect(config.singboxPath == "/opt/homebrew/bin/sing-box")
        #expect(config.socksHost == "127.0.0.1")
        #expect(config.socksPort == 1080)
        #expect(config.selectedProfile == "default")

        // New policy fields automatically populated with safe defaults
        #expect(config.routingMode == .selective)
        #expect(config.quicMode == .scoped)
        #expect(config.dnsMode == .disabled)
        #expect(config.enableIPv6 == true)
        #expect(config.groupPreferences.isEmpty)
        #expect(config.customInclude.isEmpty)
        #expect(config.customExclude.isEmpty)

        // Sanitizing legacy args strips the inert -t 3
        let sanitized = ByeDPICapability.darwinStandard.sanitize(args: config.ciadpiArgs)
        #expect(!sanitized.contains("-t"))
        #expect(sanitized.contains("-s"))
        #expect(sanitized.contains("-d"))
        #expect(sanitized.contains("-r"))
    }

    @Test("Round-trip encoding and decoding preserves all v1.4.0 policy configurations")
    func configRoundTrip() throws {
        let original = RoutunConfig(
            ciadpiPath: "/usr/local/libexec/routun/ciadpi",
            singboxPath: "/usr/local/libexec/routun/sing-box",
            ciadpiArgs: ["-s", "1", "-d", "3+s", "-r", "1+s"],
            socksHost: "127.0.0.1",
            socksPort: 1085,
            singboxConfig: "/Library/Application Support/routun/config/singbox.json",
            selectedProfile: "disoob-tlsrec",
            routingMode: .global,
            quicMode: .blocked,
            dnsMode: .doh,
            enableIPv6: false,
            groupPreferences: ["social": true, "turkiye": false],
            customInclude: ["custom-domain.org"],
            customExclude: ["work-intranet.net"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(RoutunConfig.self, from: data)

        #expect(decoded == original)
        #expect(decoded.routingMode == .global)
        #expect(decoded.quicMode == .blocked)
        #expect(decoded.dnsMode == .doh)
        #expect(decoded.enableIPv6 == false)
        #expect(decoded.groupPreferences["social"] == true)
        #expect(decoded.groupPreferences["turkiye"] == false)
        #expect(decoded.customInclude == ["custom-domain.org"])
        #expect(decoded.customExclude == ["work-intranet.net"])
    }

    @Test("Daemon configuration enforces secure service binary paths")
    func daemonConfigurationEnforcesSecurePaths() {
        let daemonConfig = RoutunConfig.daemonConfiguration()
        #expect(daemonConfig.ciadpiPath == RoutunConfig.serviceCiadpiPath)
        #expect(daemonConfig.singboxPath == RoutunConfig.serviceSingboxPath)
        #expect(daemonConfig.singboxConfig == RoutunConfig.defaultSingboxConfigFile)
    }

    @Test("Default configuration has selective routing, scoped QUIC, and standard args")
    func defaultConfigurationValues() {
        let config = RoutunConfig.defaultConfiguration()
        #expect(config.routingMode == .selective)
        #expect(config.quicMode == .scoped)
        #expect(config.dnsMode == .disabled)
        #expect(config.enableIPv6 == true)
        #expect(!config.ciadpiArgs.contains("-t"))
    }
}
