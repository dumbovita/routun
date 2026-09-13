import Foundation
import Testing
@testable import routun

@Suite("Service Group Catalog Tests")
struct ServiceGroupCatalogTests {
    @Test("Catalog contains exactly the 6 curated built-in groups")
    func builtInGroupsCountAndIds() {
        let groups = ServiceGroupCatalog.builtInGroups
        #expect(groups.count == 6)

        let ids = groups.map(\.id)
        let expectedIds = ["general", "social", "turkiye", "youtube", "telegram", "cloudflare"]
        #expect(ids == expectedIds)
    }

    @Test("Default enabled status matches expected policy defaults")
    func defaultEnabledStatus() {
        #expect(ServiceGroupCatalog.general.defaultEnabled == true)
        #expect(ServiceGroupCatalog.social.defaultEnabled == true)
        #expect(ServiceGroupCatalog.turkiye.defaultEnabled == true)
        #expect(ServiceGroupCatalog.youtube.defaultEnabled == true)
        #expect(ServiceGroupCatalog.cloudflare.defaultEnabled == true)

        #expect(ServiceGroupCatalog.telegram.defaultEnabled == false)
    }

    @Test("Domain normalization strips schemes, paths, ports, wildcards, and trims whitespace")
    func domainNormalization() {
        #expect(ServiceGroupCatalog.normalizeDomain("https://discord.com/") == "discord.com")
        #expect(ServiceGroupCatalog.normalizeDomain("http://Discord.com:443/path/resource?query=1") == "discord.com")
        #expect(ServiceGroupCatalog.normalizeDomain("*.instagram.com") == "instagram.com")
        #expect(ServiceGroupCatalog.normalizeDomain(".*.cloudflare.com") == "cloudflare.com")
        #expect(ServiceGroupCatalog.normalizeDomain(".youtube.com") == "youtube.com")
        #expect(ServiceGroupCatalog.normalizeDomain("x.com.") == "x.com")
        #expect(ServiceGroupCatalog.normalizeDomain("  TWITTER.COM  ") == "twitter.com")

        // Invalid and adversarial inputs
        #expect(ServiceGroupCatalog.normalizeDomain("") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("   ") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("http://") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("invalid host with spaces.com") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("nodot") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("foo*bar.com") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("..") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("example..com") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("..example.com") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("user@example.com") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("example.com#fragment") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("example.com;cmd") == nil)
        #expect(ServiceGroupCatalog.normalizeDomain("[::1]") == nil)

        // Idempotency: normalizing an already normalized domain returns identical output
        let samples = ["discord.com", "instagram.com", "cloudflare.com", "x.com", "youtube.com"]
        for sample in samples {
            let normalized = ServiceGroupCatalog.normalizeDomain(sample)
            #expect(normalized == sample)
            #expect(ServiceGroupCatalog.normalizeDomain(normalized!) == sample)
        }
    }

    @Test("Normalize list deduplicates, trims, validates, and sorts domain suffixes")
    func normalizeList() {
        let input = [
            "https://X.COM",
            "x.com",
            "*.x.com",
            "   ",
            "facebook.com:443/page",
            "invalid domain",
            "instagram.com"
        ]

        let normalized = ServiceGroupCatalog.normalize(input)
        #expect(normalized == ["facebook.com", "instagram.com", "x.com"])
    }

    @Test("Built-in groups contain clean normalized suffixes without wildcards or schemes")
    func builtInGroupSuffixesAreClean() {
        for group in ServiceGroupCatalog.builtInGroups {
            #expect(!group.id.isEmpty)
            #expect(!group.name.isEmpty)
            #expect(!group.description.isEmpty)
            #expect(!group.domainSuffixes.isEmpty, "Group \(group.id) must have at least one domain suffix")

            for suffix in group.domainSuffixes {
                #expect(!suffix.contains("://"), "Suffix must not contain protocol: \(suffix)")
                #expect(!suffix.contains("/"), "Suffix must not contain slash: \(suffix)")
                #expect(!suffix.contains(":"), "Suffix must not contain port: \(suffix)")
                #expect(!suffix.contains("*"), "Suffix must not contain asterisk: \(suffix)")
                #expect(suffix == suffix.lowercased(), "Suffix must be lowercase: \(suffix)")
            }
        }
    }

    @Test("Find by ID works case-insensitively and handles whitespace")
    func findById() {
        #expect(ServiceGroupCatalog.find(byId: "turkiye")?.id == "turkiye")
        #expect(ServiceGroupCatalog.find(byId: "TURKIYE ")?.id == "turkiye")
        #expect(ServiceGroupCatalog.find(byId: "YouTube")?.id == "youtube")
        #expect(ServiceGroupCatalog.find(byId: "general")?.id == "general")
        #expect(ServiceGroupCatalog.find(byId: "nonexistent") == nil)
    }
}
