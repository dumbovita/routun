import Foundation
import Testing
@testable import routun

@Suite("Strategy Profiles Tests")
struct StrategyProfilesTests {
    @Test("Exact profile counts match macOS capability catalog")
    func profileCounts() {
        #expect(StrategyProfiles.all.count == 51, "StrategyProfiles.all must contain exactly 51 Darwin-supported profiles")
        #expect(StrategyProfiles.canonical.count == 7, "StrategyProfiles.canonical must contain exactly 7 canonical profiles")
    }

    @Test("Default profile does not use inert fake TTL and matches proven Darwin parameters")
    func defaultProfileVerification() {
        let def = StrategyProfiles.defaultProfile
        #expect(def.args == ["-s", "1", "-d", "3+s", "-r", "1+s"])
        #expect(!def.args.contains("-t"))
        #expect(!def.args.contains("--ttl"))
    }

    @Test("Every profile in the catalog has unique ID and arguments")
    func uniqueIdsAndArguments() {
        var seenIds = Set<String>()
        var seenArgs = Set<String>()

        for profile in StrategyProfiles.all {
            #expect(!seenIds.contains(profile.id), "Duplicate profile ID found: \(profile.id)")
            seenIds.insert(profile.id)

            let argSignature = profile.args.joined(separator: " ")
            #expect(!seenArgs.contains(argSignature), "Duplicate profile args found: \(argSignature) in \(profile.id)")
            seenArgs.insert(argSignature)

            #expect(!profile.name.isEmpty, "Profile name must not be empty for \(profile.id)")
            #expect(!profile.family.isEmpty, "Profile family must not be empty for \(profile.id)")
            #expect(!profile.description.isEmpty, "Profile description must not be empty for \(profile.id)")
            #expect(!profile.args.isEmpty, "Profile args must not be empty for \(profile.id)")
        }
    }

    @Test("Zero profiles contain flags compiled out or inert on Darwin")
    func zeroInertFlagsInCatalog() {
        let prohibitedFlags = Set(["-t", "--ttl", "-Q", "--fake-tls-mod", "-f", "--fake", "-S", "--md5sig", "-T", "--timeout"])

        for profile in StrategyProfiles.all {
            for arg in profile.args {
                #expect(!prohibitedFlags.contains(arg), "Profile \(profile.id) contains prohibited/inert flag on Darwin: \(arg)")
            }
        }
    }

    @Test("Canonical profiles are properly defined and discoverable")
    func canonicalProfilesLookup() {
        let expectedCanonicalIds = [
            "default",
            "simple-split",
            "dual-split",
            "tlsrec-split",
            "disorder-sni",
            "oob-sni",
            "disorder-split-sni"
        ]

        let canonicalIds = StrategyProfiles.canonical.map(\.id)
        #expect(canonicalIds == expectedCanonicalIds)

        for id in expectedCanonicalIds {
            let found = StrategyProfiles.find(by: id)
            #expect(found != nil, "Canonical profile \(id) must be found via find(by:)")
            #expect(found?.id == id)
        }

        // Check finding profiles from allCombinations matrix as well
        #expect(StrategyProfiles.find(by: "disoob-tlsrec")?.id == "disoob-tlsrec")
        #expect(StrategyProfiles.find(by: "tlsrec-disorder-oob")?.id == "tlsrec-disorder-oob")

        // Case-insensitivity check
        #expect(StrategyProfiles.find(by: "DEFAULT")?.id == "default")
        #expect(StrategyProfiles.find(by: "Disorder-Split-SNI")?.id == "disorder-split-sni")

        // Unknown profile
        #expect(StrategyProfiles.find(by: "non-existent-profile-12345") == nil)
    }
}
