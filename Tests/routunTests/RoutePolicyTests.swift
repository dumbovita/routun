import Foundation
import Testing
@testable import routun

@Suite("Route Policy Tests")
struct RoutePolicyTests {
    @Test("Default RoutePolicy has selective mode, scoped QUIC, IPv6 disabled, and empty custom overrides")
    func defaultPolicyValues() {
        let policy = RoutePolicy()
        #expect(policy.mode == .selective)
        #expect(policy.quicMode == .scoped)
        #expect(policy.dnsMode == .disabled)
        #expect(policy.enableIPv6 == false)
        #expect(policy.groupPreferences.isEmpty)
        #expect(policy.customInclude.isEmpty)
        #expect(policy.customExclude.isEmpty)
    }

    @Test("Group enablement respects catalog defaults and explicit preferences")
    func groupPreferences() {
        var policy = RoutePolicy()

        // Unset preferences fall back to catalog defaults
        #expect(policy.isGroupEnabled(ServiceGroupCatalog.turkiye) == true)
        #expect(policy.isGroupEnabled(ServiceGroupCatalog.social) == true)
        #expect(policy.isGroupEnabled(ServiceGroupCatalog.cloudflare) == true)
        #expect(policy.isGroupEnabled(ServiceGroupCatalog.telegram) == false)

        // Explicit override: enable telegram
        policy.setGroupEnabled("telegram", enabled: true)
        #expect(policy.isGroupEnabled(ServiceGroupCatalog.telegram) == true)

        // Explicit override: disable turkiye
        policy.setGroupEnabled("turkiye", enabled: false)
        #expect(policy.isGroupEnabled(ServiceGroupCatalog.turkiye) == false)
    }

    @Test("Target resolution precedence: custom excludes override custom includes and enabled groups")
    func targetPrecedenceResolution() {
        var policy = RoutePolicy(
            customInclude: ["custom-site.org", "roblox.com"],
            customExclude: ["roblox.com", "youtube.com"]
        )

        // By default, turkiye (has roblox.com) and youtube (has youtube.com) are enabled
        let (bypassed, excluded) = policy.resolveTargets()

        // roblox.com and youtube.com MUST be excluded, NOT bypassed
        #expect(excluded.contains("roblox.com"))
        #expect(excluded.contains("youtube.com"))
        #expect(!bypassed.contains("roblox.com"))
        #expect(!bypassed.contains("youtube.com"))

        // custom-site.org MUST be bypassed
        #expect(bypassed.contains("custom-site.org"))

        // other domains from turkiye (e.g. wattpad.com) MUST still be bypassed
        #expect(bypassed.contains("wattpad.com"))
    }

    @Test("Enabling disabled groups adds their domains to bypassed targets")
    func enablingGroupAddsDomains() {
        var policy = RoutePolicy()
        let initialTargets = policy.resolveTargets().bypassedSuffixes
        #expect(!initialTargets.contains("telegram.org"))

        policy.setGroupEnabled("telegram", enabled: true)
        let updatedTargets = policy.resolveTargets().bypassedSuffixes
        #expect(updatedTargets.contains("telegram.org"))
        #expect(updatedTargets.contains("t.me"))
    }

    @Test("Codable serialization and deserialization round-trip preserves all policy fields")
    func codableRoundTrip() throws {
        var original = RoutePolicy(
            mode: .global,
            quicMode: .blocked,
            dnsMode: .doh,
            enableIPv6: false,
            groupPreferences: ["social": true, "turkiye": false],
            customInclude: ["https://example-bypass.org"],
            customExclude: ["*.corp.local"]
        )
        // ensure normalized
        original.customInclude = ["example-bypass.org"]
        original.customExclude = ["corp.local"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoutePolicy.self, from: data)

        #expect(decoded == original)
        #expect(decoded.mode == .global)
        #expect(decoded.quicMode == .blocked)
        #expect(decoded.dnsMode == .doh)
        #expect(decoded.enableIPv6 == false)
        #expect(decoded.groupPreferences["social"] == true)
        #expect(decoded.groupPreferences["turkiye"] == false)
        #expect(decoded.customInclude == ["example-bypass.org"])
        #expect(decoded.customExclude == ["corp.local"])
    }
}
