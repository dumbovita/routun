import Foundation
import Darwin
import Dispatch

// MARK: - Strategy Target

public struct StrategyTarget: Hashable {
    public let name: String
    public let host: String
    public let port: Int
    public let path: String
    public let isReference: Bool

    public init(name: String, host: String, port: Int = 443, path: String = "/", isReference: Bool = false) {
        self.name = name
        self.host = host
        self.port = port
        self.path = path
        self.isReference = isReference
    }

    public var urlString: String {
        let scheme = (port == 443) ? "https" : "http"
        return "\(scheme)://\(host)\(path)"
    }

    /// Parse a user-provided target string (e.g. "*.anadolu.edu.tr", "saglik.gov.tr", "https://discord.com")
    public static func parse(from raw: String) -> StrategyTarget? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty { return nil }

        // Strip leading wildcards (*., *)
        while str.hasPrefix("*.") {
            str.removeFirst(2)
        }
        while str.hasPrefix("*") {
            str.removeFirst(1)
        }
        str = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty { return nil }

        let hasScheme = str.contains("://")
        let urlStr = hasScheme ? str : "https://\(str)"

        guard let components = URLComponents(string: urlStr),
              let rawHost = components.host, !rawHost.isEmpty else {
            return nil
        }

        let cleanHost = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleanHost.isEmpty else { return nil }

        let port = components.port ?? (components.scheme == "http" ? 80 : 443)
        let path = components.path.isEmpty ? "/" : components.path

        return StrategyTarget(
            name: cleanHost,
            host: cleanHost,
            port: port,
            path: path,
            isReference: false
        )
    }

    /// Parse a list of raw inputs, supporting comma-separated and space-separated strings
    public static func parseList(from rawList: [String]) -> [StrategyTarget] {
        var targets = [StrategyTarget]()
        var seen = Set<String>()
        for raw in rawList {
            let splitParts = raw.components(separatedBy: ",")
            for part in splitParts {
                if let target = parse(from: part), !seen.contains(target.host) {
                    seen.insert(target.host)
                    targets.append(target)
                }
            }
        }
        return targets
    }
}

public enum StrategyTargets {
    /// Curated representative dataset combining major global platforms and daily-use services
    public static let all: [StrategyTarget] = [
        // Reference sanity check (unblocked connectivity baseline)
        StrategyTarget(name: "Apple", host: "apple.com", port: 443, path: "/", isReference: true),

        // Global platforms subject to censorship or DPI restrictions
        StrategyTarget(name: "Discord (Web/API)", host: "discord.com", port: 443, path: "/"),
        StrategyTarget(name: "Discord (Gateway)", host: "gateway.discord.gg", port: 443, path: "/"),
        StrategyTarget(name: "Roblox", host: "roblox.com", port: 443, path: "/"),
        StrategyTarget(name: "Wattpad", host: "wattpad.com", port: 443, path: "/"),
        StrategyTarget(name: "Pastebin", host: "pastebin.com", port: 443, path: "/"),
        StrategyTarget(name: "X / Twitter", host: "x.com", port: 443, path: "/"),
        StrategyTarget(name: "Instagram", host: "instagram.com", port: 443, path: "/"),
        StrategyTarget(name: "Facebook", host: "facebook.com", port: 443, path: "/"),
        StrategyTarget(name: "YouTube", host: "youtube.com", port: 443, path: "/"),
        StrategyTarget(name: "Google Video CDN", host: "redirector.googlevideo.com", port: 443, path: "/"),
        StrategyTarget(name: "RuTracker", host: "rutracker.org", port: 443, path: "/"),
        StrategyTarget(name: "Tor Project", host: "torproject.org", port: 443, path: "/"),
        StrategyTarget(name: "LinkedIn", host: "linkedin.com", port: 443, path: "/"),
        StrategyTarget(name: "Medium", host: "medium.com", port: 443, path: "/"),

        // Frequently used daily services & social media
        StrategyTarget(name: "Google", host: "google.com", port: 443, path: "/"),
        StrategyTarget(name: "Reddit", host: "reddit.com", port: 443, path: "/"),
        StrategyTarget(name: "Wikipedia", host: "wikipedia.org", port: 443, path: "/"),
        StrategyTarget(name: "Spotify", host: "spotify.com", port: 443, path: "/"),
        StrategyTarget(name: "Twitch", host: "twitch.tv", port: 443, path: "/"),
        StrategyTarget(name: "Cloudflare", host: "cloudflare.com", port: 443, path: "/"),

        // Microsoft & Windows consumer / authentication services
        StrategyTarget(name: "Microsoft Login", host: "login.microsoftonline.com", port: 443, path: "/"),
        StrategyTarget(name: "Microsoft Live", host: "login.live.com", port: 443, path: "/"),
        StrategyTarget(name: "Xbox Live Auth", host: "user.auth.xboxlive.com", port: 443, path: "/"),

        // Sensitive education & government portals (strict TLS/WAF compatibility verification)
        StrategyTarget(name: "Anadolu University", host: "anadolu.edu.tr", port: 443, path: "/"),
        StrategyTarget(name: "Saglik Bakanligi", host: "saglik.gov.tr", port: 443, path: "/")
    ]
}

// MARK: - Strategy Profile

public struct StrategyProfile: Equatable {
    public let id: String
    public let name: String
    public let family: String
    public let description: String
    public let args: [String]
    public let complexity: Int

    public init(id: String, name: String, family: String = "Custom", description: String, args: [String], complexity: Int) {
        self.id = id
        self.name = name
        self.family = family
        self.description = description
        self.args = args
        self.complexity = complexity
    }

    /// Complete ByeDPI command line arguments with binding, listen port, and adaptive evasion
    public func fullArgs(host: String = "127.0.0.1", port: Int = 1080, maxConn: Int = 512) -> [String] {
        return ["-i", host, "-p", String(port), "-A", "torst,ssl_err"] + args + ["-c", String(maxConn)]
    }
}

public enum StrategyProfiles {
    // MARK: - Canonical Curated Profiles
    public static let defaultProfile = StrategyProfile(
        id: "default",
        name: "Default (Balanced)",
        family: "Balanced",
        description: "Split, SNI disorder, TLS record split (known-safe fallback)",
        args: ["-s", "1", "-d", "3+s", "-r", "1+s", "-t", "3"],
        complexity: 0
    )

    public static let simpleSplit = StrategyProfile(
        id: "simple-split",
        name: "Minimal Split (1+s)",
        family: "Split",
        description: "Lightweight single split at SNI start with minimal overhead",
        args: ["-s", "1+s"],
        complexity: 1
    )

    public static let dualSplit = StrategyProfile(
        id: "dual-split",
        name: "Dual Split (1 + 2+s)",
        family: "Dual Split",
        description: "Two-stage split at initial byte and within SNI",
        args: ["-s", "1", "-s", "2+s"],
        complexity: 2
    )

    public static let tlsrecSplit = StrategyProfile(
        id: "tlsrec-split",
        name: "TLS Record Split",
        family: "TLS Record",
        description: "TLS record layer segmentation at SNI with byte 1 split",
        args: ["-r", "1+s", "-s", "1"],
        complexity: 3
    )

    public static let disorderSni = StrategyProfile(
        id: "disorder-sni",
        name: "SNI Disorder",
        family: "Disorder",
        description: "Reverse packet order delivery at SNI",
        args: ["-d", "1+s", "-r", "1+s"],
        complexity: 4
    )

    public static let oobSni = StrategyProfile(
        id: "oob-sni",
        name: "OOB Byte Injection",
        family: "OOB",
        description: "Out-of-band urgent byte into SNI to choke DPI parsers",
        args: ["-o", "1+s", "-s", "1"],
        complexity: 5
    )

    public static let fakeDisorder = StrategyProfile(
        id: "fake-disorder",
        name: "Fake TTL + Disorder",
        family: "Fake TTL",
        description: "Low-TTL dummy packet injection + SNI disorder",
        args: ["-t", "3", "-s", "1", "-d", "2+s", "-r", "1+s"],
        complexity: 6
    )

    public static let canonical: [StrategyProfile] = [
        defaultProfile,
        simpleSplit,
        dualSplit,
        tlsrecSplit,
        disorderSni,
        oobSni,
        fakeDisorder
    ]

    // MARK: - Exhaustive Combinations Matrix
    public static let allCombinations: [StrategyProfile] = [
        // Canonical Fallback
        defaultProfile,

        // 1. Pure Splits
        StrategyProfile(id: "split-1", name: "Split 1", family: "Split", description: "Split at initial byte", args: ["-s", "1"], complexity: 1),
        StrategyProfile(id: "split-2", name: "Split 2", family: "Split", description: "Split at byte 2", args: ["-s", "2"], complexity: 1),
        StrategyProfile(id: "split-1s", name: "Split 1+s", family: "Split", description: "Split at SNI start", args: ["-s", "1+s"], complexity: 1),
        StrategyProfile(id: "split-2s", name: "Split 2+s", family: "Split", description: "Split inside SNI", args: ["-s", "2+s"], complexity: 1),
        StrategyProfile(id: "split-3s", name: "Split 3+s", family: "Split", description: "Split at byte 3 of SNI", args: ["-s", "3+s"], complexity: 1),
        StrategyProfile(id: "split-se", name: "Split 0+s+e", family: "Split", description: "Split at end of SNI", args: ["-s", "0+s+e"], complexity: 1),
        StrategyProfile(id: "split-sm", name: "Split 0+s+m", family: "Split", description: "Split at middle of SNI", args: ["-s", "0+s+m"], complexity: 1),

        // 2. Dual Splits
        StrategyProfile(id: "dual-split-1-1s", name: "Dual Split 1 + 1+s", family: "Dual Split", description: "Byte 1 split + SNI start split", args: ["-s", "1", "-s", "1+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1-2s", name: "Dual Split 1 + 2+s", family: "Dual Split", description: "Byte 1 split + SNI 2nd byte split", args: ["-s", "1", "-s", "2+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1-3s", name: "Dual Split 1 + 3+s", family: "Dual Split", description: "Byte 1 split + SNI 3rd byte split", args: ["-s", "1", "-s", "3+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1-se", name: "Dual Split 1 + 0+s+e", family: "Dual Split", description: "Byte 1 split + SNI end split", args: ["-s", "1", "-s", "0+s+e"], complexity: 2),
        StrategyProfile(id: "dual-split-2-2s", name: "Dual Split 2 + 2+s", family: "Dual Split", description: "Byte 2 split + SNI 2nd byte split", args: ["-s", "2", "-s", "2+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1s-2s", name: "Dual Split 1+s + 2+s", family: "Dual Split", description: "SNI start split + SNI 2nd byte split", args: ["-s", "1+s", "-s", "2+s"], complexity: 2),

        // 3. Pure Disorders
        StrategyProfile(id: "disorder-1s", name: "Disorder 1+s", family: "Disorder", description: "Reverse packet order at SNI start", args: ["-d", "1+s"], complexity: 3),
        StrategyProfile(id: "disorder-2s", name: "Disorder 2+s", family: "Disorder", description: "Reverse packet order inside SNI", args: ["-d", "2+s"], complexity: 3),
        StrategyProfile(id: "disorder-3s", name: "Disorder 3+s", family: "Disorder", description: "Reverse packet order at SNI byte 3", args: ["-d", "3+s"], complexity: 3),
        StrategyProfile(id: "disorder-se", name: "Disorder 0+s+e", family: "Disorder", description: "Reverse packet order at SNI end", args: ["-d", "0+s+e"], complexity: 3),

        // 4. Split + Disorder Combinations
        StrategyProfile(id: "split-1-disorder-1s", name: "Split 1 + Disorder 1+s", family: "Split+Disorder", description: "Byte 1 split + SNI start disorder", args: ["-s", "1", "-d", "1+s"], complexity: 4),
        StrategyProfile(id: "split-1-disorder-2s", name: "Split 1 + Disorder 2+s", family: "Split+Disorder", description: "Byte 1 split + SNI 2nd byte disorder", args: ["-s", "1", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "split-1-disorder-3s", name: "Split 1 + Disorder 3+s", family: "Split+Disorder", description: "Byte 1 split + SNI 3rd byte disorder", args: ["-s", "1", "-d", "3+s"], complexity: 4),
        StrategyProfile(id: "split-1-disorder-se", name: "Split 1 + Disorder 0+s+e", family: "Split+Disorder", description: "Byte 1 split + SNI end disorder", args: ["-s", "1", "-d", "0+s+e"], complexity: 4),
        StrategyProfile(id: "split-1s-disorder-2s", name: "Split 1+s + Disorder 2+s", family: "Split+Disorder", description: "SNI start split + SNI disorder", args: ["-s", "1+s", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "split-2-disorder-2s", name: "Split 2 + Disorder 2+s", family: "Split+Disorder", description: "Byte 2 split + SNI disorder", args: ["-s", "2", "-d", "2+s"], complexity: 4),

        // 5. TLS Record Splits
        StrategyProfile(id: "tlsrec-1s", name: "TLS Record 1+s", family: "TLS Record", description: "TLS record layer segmentation at SNI", args: ["-r", "1+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-2s", name: "TLS Record 2+s", family: "TLS Record", description: "TLS record layer segmentation inside SNI", args: ["-r", "2+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-1s-split-1", name: "TLS Record 1+s + Split 1", family: "TLS Record", description: "TLS record split at SNI + initial byte split", args: ["-r", "1+s", "-s", "1"], complexity: 3),
        StrategyProfile(id: "tlsrec-1s-split-1s", name: "TLS Record 1+s + Split 1+s", family: "TLS Record", description: "TLS record split + SNI start split", args: ["-r", "1+s", "-s", "1+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-1s-split-2s", name: "TLS Record 1+s + Split 2+s", family: "TLS Record", description: "TLS record split + SNI byte 2 split", args: ["-r", "1+s", "-s", "2+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-2s-split-1", name: "TLS Record 2+s + Split 1", family: "TLS Record", description: "TLS record inside SNI + byte 1 split", args: ["-r", "2+s", "-s", "1"], complexity: 3),

        // 6. TLS Record + Disorder
        StrategyProfile(id: "tlsrec-1s-disorder-1s", name: "TLS Record 1+s + Disorder 1+s", family: "TLS Record", description: "TLS record split + SNI start disorder", args: ["-r", "1+s", "-d", "1+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-disorder-2s", name: "TLS Record 1+s + Disorder 2+s", family: "TLS Record", description: "TLS record split + SNI 2nd byte disorder", args: ["-r", "1+s", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-disorder-3s", name: "TLS Record 1+s + Disorder 3+s", family: "TLS Record", description: "TLS record split + SNI 3rd byte disorder", args: ["-r", "1+s", "-d", "3+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-split-1-disorder-2s", name: "TLS Record 1+s + Split 1 + Disorder 2+s", family: "TLS Record", description: "TLS record + byte 1 split + disorder 2+s", args: ["-r", "1+s", "-s", "1", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-split-1-disorder-3s", name: "TLS Record 1+s + Split 1 + Disorder 3+s", family: "TLS Record", description: "TLS record + byte 1 split + disorder 3+s", args: ["-r", "1+s", "-s", "1", "-d", "3+s"], complexity: 4),

        // 7. Fake TTL Sweeps (TTL 1, 2, 3, 4, 5, 8)
        StrategyProfile(id: "fake-ttl1-disorder-2s", name: "Fake TTL 1 + Disorder 2+s", family: "Fake TTL", description: "TTL 1 dummy injection + disorder 2+s + record 1+s", args: ["-t", "1", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl2-disorder-2s", name: "Fake TTL 2 + Disorder 2+s", family: "Fake TTL", description: "TTL 2 dummy injection + disorder 2+s + record 1+s", args: ["-t", "2", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl3-disorder-2s", name: "Fake TTL 3 + Disorder 2+s", family: "Fake TTL", description: "TTL 3 dummy injection + disorder 2+s + record 1+s", args: ["-t", "3", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl4-disorder-2s", name: "Fake TTL 4 + Disorder 2+s", family: "Fake TTL", description: "TTL 4 dummy injection + disorder 2+s + record 1+s", args: ["-t", "4", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl5-disorder-2s", name: "Fake TTL 5 + Disorder 2+s", family: "Fake TTL", description: "TTL 5 dummy injection + disorder 2+s + record 1+s", args: ["-t", "5", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl8-disorder-2s", name: "Fake TTL 8 + Disorder 2+s", family: "Fake TTL", description: "TTL 8 dummy injection + disorder 2+s + record 1+s", args: ["-t", "8", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl2-disorder-3s", name: "Fake TTL 2 + Disorder 3+s", family: "Fake TTL", description: "TTL 2 dummy injection + disorder 3+s + record 1+s", args: ["-t", "2", "-s", "1", "-d", "3+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl3-disorder-3s", name: "Fake TTL 3 + Disorder 3+s", family: "Fake TTL", description: "TTL 3 dummy injection + disorder 3+s + record 1+s", args: ["-t", "3", "-s", "1", "-d", "3+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl4-disorder-3s", name: "Fake TTL 4 + Disorder 3+s", family: "Fake TTL", description: "TTL 4 dummy injection + disorder 3+s + record 1+s", args: ["-t", "4", "-s", "1", "-d", "3+s", "-r", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl3-disorder-1s", name: "Fake TTL 3 + Disorder 1+s", family: "Fake TTL", description: "TTL 3 dummy injection + SNI start disorder", args: ["-t", "3", "-s", "1", "-d", "1+s"], complexity: 5),
        StrategyProfile(id: "fake-ttl3-tlsrec-1s", name: "Fake TTL 3 + TLS Record 1+s", family: "Fake TTL", description: "TTL 3 dummy injection + TLS record split", args: ["-t", "3", "-r", "1+s", "-s", "1"], complexity: 5),

        // 8. OOB & Disoob
        StrategyProfile(id: "oob-1s-split-1", name: "OOB 1+s + Split 1", family: "OOB", description: "OOB urgent byte at SNI start + byte 1 split", args: ["-o", "1+s", "-s", "1"], complexity: 5),
        StrategyProfile(id: "oob-2s-split-1", name: "OOB 2+s + Split 1", family: "OOB", description: "OOB urgent byte inside SNI + byte 1 split", args: ["-o", "2+s", "-s", "1"], complexity: 5),
        StrategyProfile(id: "oob-1s-disorder-2s", name: "OOB 1+s + Disorder 2+s", family: "OOB", description: "OOB urgent byte at SNI start + disorder inside SNI", args: ["-o", "1+s", "-d", "2+s"], complexity: 5),
        StrategyProfile(id: "disoob-1s-split-1", name: "Disoob 1+s + Split 1", family: "OOB", description: "Reverse order OOB urgent data at SNI start", args: ["-q", "1+s", "-s", "1"], complexity: 5),
        StrategyProfile(id: "disoob-2s-split-1", name: "Disoob 2+s + Split 1", family: "OOB", description: "Reverse order OOB urgent data inside SNI", args: ["-q", "2+s", "-s", "1"], complexity: 5),

        // 9. Fake ClientHello TLS Mod
        StrategyProfile(id: "fake-ch-rand-ttl3", name: "Fake CH (Rand) + TTL 3", family: "Fake CH", description: "Randomized fake ClientHello + TTL 3 + disorder", args: ["-Q", "rand", "-t", "3", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 6),
        StrategyProfile(id: "fake-ch-orig-ttl3", name: "Fake CH (Orig) + TTL 3", family: "Fake CH", description: "Original fake ClientHello copy + TTL 3 + disorder", args: ["-Q", "orig", "-t", "3", "-s", "1", "-d", "2+s", "-r", "1+s"], complexity: 6)
    ]

    /// Combined profile registry, deduplicated by ID
    public static var all: [StrategyProfile] {
        var seen = Set<String>()
        var list = [StrategyProfile]()
        for p in canonical + allCombinations {
            if !seen.contains(p.id) {
                seen.insert(p.id)
                list.append(p)
            }
        }
        return list
    }

    public static func find(by nameOrId: String) -> StrategyProfile? {
        let needle = nameOrId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.id.lowercased() == needle || $0.name.lowercased() == needle }
    }
}

// MARK: - Probe Result & Scoring

public struct ProbeResult {
    public let target: StrategyTarget
    public let isReachable: Bool
    public let latencyMs: Int
    public let statusCode: Int
    public let exitCode: Int32
    public let detail: String
    public let attempts: Int
}

public struct Phase1Score {
    public let profile: StrategyProfile
    public let unlockedCount: Int
    public let reachableCount: Int
    public let totalTargets: Int
    public let averageLatencyMs: Int
    public let timeouts: Int
    public let customTargetsPassed: Int
    public let totalCustomTargets: Int
    public let results: [String: ProbeResult]
}

public struct CrossReferenceScore {
    public let profile: StrategyProfile
    public let round1Results: [String: ProbeResult]
    public let round2Results: [String: ProbeResult]
    public let stabilityRate: Double // 0.0 to 1.0
    public let totalPasses: Int
    public let totalTests: Int
    public let avgLatencyMs: Int
    public let unlockedCount: Int
    public let customPassedCount: Int
}

// MARK: - Strategy Optimizer (Blockcheck Engine)

public final class StrategyOptimizer {
    public let ciadpiPath: String
    public let testPort: Int
    public let verbose: Bool
    public let quick: Bool
    public let customTargets: [StrategyTarget]

    private let physicalInterface: String?

    public static func findFreePort() -> Int {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 10885 }
        defer { close(sock) }
        var bound = false
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bound = (bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0)
            }
        }
        guard bound else { return 10885 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(sock, $0, &len)
            }
        }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        return port > 1024 ? port : 10885
    }

    public init(ciadpiPath: String? = nil, testPort: Int? = nil, verbose: Bool = false, quick: Bool = false, customTargets: [StrategyTarget] = []) {
        let config = RoutunConfig.load()
        self.ciadpiPath = ciadpiPath ?? config.ciadpiPath
        self.testPort = testPort ?? StrategyOptimizer.findFreePort()
        self.verbose = verbose
        self.quick = quick
        self.customTargets = customTargets
        self.physicalInterface = StrategyOptimizer.detectPhysicalInterface()
    }

    /// Detect active physical network interface (e.g. en0) to bypass utun10 for baseline tests
    public static func detectPhysicalInterface() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        proc.arguments = ["-rn", "-f", "inet"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if parts.count >= 4 && parts[0] == "default" {
                if let iface = parts.last, iface.hasPrefix("en") {
                    return iface
                }
            }
        }
        return "en0"
    }

    /// Perform a single HTTP/TLS probe via /usr/bin/curl
    private func probeSingle(target: StrategyTarget, socksPort: Int?, timeout: Double) -> ProbeResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        var args = [
            "-I",
            "-s",
            "-o", "/dev/null",
            "-w", "%{http_code} %{time_total}",
            "--connect-timeout", "2.5",
            "--max-time", String(format: "%.1f", max(timeout, 3.0)),
            "-A", "Mozilla/5.0 (Macintosh; Apple Mac OS X) routun-blockcheck/2.0"
        ]

        if let port = socksPort {
            args += ["--socks5", "127.0.0.1:\(port)"]
        } else if let iface = physicalInterface {
            args += ["--interface", iface]
        }

        args.append(target.urlString)
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe

        let startTime = Date()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)

            let exitCode = proc.terminationStatus
            let output = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = output.components(separatedBy: " ")

            let statusCode = parts.first.flatMap { Int($0) } ?? 0
            let isReachable = (statusCode > 0 && statusCode < 500)

            var detail = "HTTP \(statusCode)"
            if !isReachable {
                switch exitCode {
                case 28: detail = "Timeout"
                case 35: detail = "TLS Handshake Blocked (DPI)"
                case 7:  detail = "Connection Reset / Refused"
                case 6:  detail = "DNS Resolution Failed"
                default: detail = "Curl Error (\(exitCode))"
                }
            }

            return ProbeResult(
                target: target,
                isReachable: isReachable,
                latencyMs: elapsedMs,
                statusCode: statusCode,
                exitCode: exitCode,
                detail: detail,
                attempts: 1
            )
        } catch {
            return ProbeResult(
                target: target,
                isReachable: false,
                latencyMs: 0,
                statusCode: 0,
                exitCode: -1,
                detail: error.localizedDescription,
                attempts: 1
            )
        }
    }

    /// Probe a target with automatic retry (tries twice to avoid transient flukes)
    public func probe(target: StrategyTarget, socksPort: Int?, timeout: Double = 1.8, maxAttempts: Int = 2) -> ProbeResult {
        let first = probeSingle(target: target, socksPort: socksPort, timeout: timeout)
        if first.isReachable || maxAttempts <= 1 {
            return first
        }

        // Retry on failure ("try the same thing twice")
        usleep(40_000) // 40ms pause before retry
        let second = probeSingle(target: target, socksPort: socksPort, timeout: timeout)
        if second.isReachable {
            return ProbeResult(
                target: target,
                isReachable: true,
                latencyMs: second.latencyMs,
                statusCode: second.statusCode,
                exitCode: second.exitCode,
                detail: "\(second.detail) (retry ✓)",
                attempts: 2
            )
        }
        return ProbeResult(
            target: target,
            isReachable: false,
            latencyMs: second.latencyMs,
            statusCode: second.statusCode,
            exitCode: second.exitCode,
            detail: second.detail,
            attempts: 2
        )
    }

    /// Concurrently probe multiple targets against socksPort in parallel
    public func probeConcurrently(targets: [StrategyTarget], socksPort: Int?, timeout: Double = 1.8, maxAttempts: Int = 2) -> [ProbeResult] {
        var results = [ProbeResult?](repeating: nil, count: targets.count)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: targets.count) { i in
            let res = self.probe(target: targets[i], socksPort: socksPort, timeout: timeout, maxAttempts: maxAttempts)
            lock.lock()
            results[i] = res
            lock.unlock()
        }

        return results.compactMap { $0 }
    }

    /// Launch a temporary isolated ByeDPI process on the test port
    private func spawnTestCiadpi(profile: StrategyProfile, port: Int) -> Process? {
        guard FileManager.default.isExecutableFile(atPath: ciadpiPath) else { return nil }

        // Ensure port is not lingering from a previous failed instance
        if NetUtils.isPortOpen(host: "127.0.0.1", port: port, timeout: 0.05) {
            _ = ServiceManager.shared.runCommand("/usr/bin/pkill", ["-9", "-f", "ciadpi.*\(port)"])
            usleep(80_000)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ciadpiPath)
        proc.arguments = ["-i", "127.0.0.1", "-p", String(port), "-A", "torst,ssl_err"] + profile.args + ["-c", "64"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }

        // Wait up to 800ms for this specific process to start listening
        for _ in 0..<8 {
            guard proc.isRunning else { return nil }
            if NetUtils.isPortOpen(host: "127.0.0.1", port: port, timeout: 0.1) {
                return proc
            }
            usleep(100_000)
        }

        proc.terminate()
        return nil
    }

    /// Cleanly terminate a process with SIGTERM and SIGKILL fallback
    private func terminateProcess(_ proc: Process, port: Int? = nil) {
        let p = port ?? testPort
        if proc.isRunning {
            proc.terminate()
            for _ in 0..<5 {
                if !proc.isRunning { break }
                usleep(30_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
                proc.waitUntilExit()
            }
        }
        if NetUtils.isPortOpen(host: "127.0.0.1", port: p, timeout: 0.05) {
            _ = ServiceManager.shared.runCommand("/usr/bin/pkill", ["-9", "-f", "ciadpi.*\(p)"])
            usleep(50_000)
        }
    }

    /// Run the comprehensive strategy optimization and cross-referencing routine
    public func run(onProgress: ((String) -> Void)? = nil) -> StrategyProfile? {
        let emit = { (msg: String) in
            if let cb = onProgress {
                cb(msg)
            } else {
                print(msg)
                fflush(stdout)
            }
        }

        emit("\u{001B}[1mTesting network compatibility & DPI evasion...\u{001B}[0m\n")

        // 1. Sanity check: Global internet connectivity
        let refTarget = StrategyTargets.all.first { $0.isReference } ?? StrategyTargets.all[0]
        let refResult = probe(target: refTarget, socksPort: nil, timeout: 2.5, maxAttempts: 2)
        if !refResult.isReachable && refResult.exitCode == 6 {
            emit("\u{001B}[31mError:\u{001B}[0m No internet connection or DNS resolution failure detected.")
            emit("Please verify your internet connection before running strategy optimization.")
            return nil
        }

        // 2. Establish Baseline (Direct physical connection without ByeDPI)
        var seenHosts = Set<String>()
        var evalTargets = [StrategyTarget]()

        // Custom targets are prioritized at the top of the evaluation list
        for ct in customTargets {
            if !seenHosts.contains(ct.host) {
                seenHosts.insert(ct.host)
                evalTargets.append(ct)
            }
        }
        for st in StrategyTargets.all where !st.isReference {
            if !seenHosts.contains(st.host) {
                seenHosts.insert(st.host)
                evalTargets.append(st)
            }
        }

        if !customTargets.isEmpty {
            emit("Custom targets added (\(customTargets.count)): \(customTargets.map { $0.host }.joined(separator: ", "))\n")
        }

        var baselineResults = [String: ProbeResult]()
        var baselineReachableCount = 0

        // Concurrently probe baseline targets
        let directProbes = probeConcurrently(targets: evalTargets, socksPort: nil, timeout: 2.0, maxAttempts: 2)
        for res in directProbes {
            baselineResults[res.target.host] = res
            if res.isReachable {
                baselineReachableCount += 1
            }
            if verbose {
                let color = res.isReachable ? "\u{001B}[32m" : "\u{001B}[33m"
                let isCustom = customTargets.contains(where: { $0.host == res.target.host })
                let prefix = isCustom ? "[Custom]" : "[Baseline]"
                emit("  \(prefix) \(res.target.name.padding(toLength: 22, withPad: " ", startingAt: 0)): \(color)\(res.detail)\u{001B}[0m (\(res.latencyMs)ms)")
            }
        }

        let blockedTargets = evalTargets.filter { !(baselineResults[$0.host]?.isReachable ?? false) }
        emit("Baseline (Direct): \(baselineReachableCount)/\(evalTargets.count) reachable (\(blockedTargets.count) blocked by DPI)\n")

        // targetsToTest includes all blocked targets, PLUS customTargets (to ensure desync does not break them!)
        var targetsToTest = blockedTargets
        for ct in customTargets {
            if !targetsToTest.contains(where: { $0.host == ct.host }) {
                targetsToTest.append(ct)
            }
        }

        if targetsToTest.isEmpty {
            emit("\u{001B}[32mAll test targets are directly accessible on your current network without DPI bypass.\u{001B}[0m")
            emit("Keeping default profile: \u{001B}[1m\(StrategyProfiles.defaultProfile.name)\u{001B}[0m\n")
            return StrategyProfiles.defaultProfile
        }

        // 3. Stage 1: Fast Matrix Combination Evaluation
        let candidateProfiles = quick ? StrategyProfiles.canonical : StrategyProfiles.all
        let modeLabel = quick ? "canonical profiles" : "comprehensive combinations matrix"
        emit("Testing \(candidateProfiles.count) \(modeLabel):")

        let blockedSet = Set(blockedTargets.map { $0.host })
        let customSet = Set(customTargets.map { $0.host })
        var phase1Scores = [Phase1Score]()

        for (index, profile) in candidateProfiles.enumerated() {
            guard let testProc = spawnTestCiadpi(profile: profile, port: testPort) else {
                emit("  [\(index + 1)/\(candidateProfiles.count)] \(profile.id.padding(toLength: 28, withPad: " ", startingAt: 0)) \u{001B}[31mFailed to launch test instance\u{001B}[0m")
                continue
            }

            defer {
                terminateProcess(testProc)
            }

            // Concurrently test targets with automatic retry
            let probeResults = probeConcurrently(targets: targetsToTest, socksPort: testPort, timeout: 1.8, maxAttempts: 2)
            var resultMap = [String: ProbeResult]()
            var unlockedCount = 0
            var customPassed = 0
            var totalReachable = 0
            var totalLatency = 0
            var timeouts = 0

            for res in probeResults {
                resultMap[res.target.host] = res
                if res.isReachable {
                    totalReachable += 1
                    totalLatency += res.latencyMs
                    if blockedSet.contains(res.target.host) {
                        unlockedCount += 1
                    }
                    if customSet.contains(res.target.host) {
                        customPassed += 1
                    }
                } else if res.exitCode == 28 {
                    timeouts += 1
                }
            }

            if verbose {
                for res in probeResults {
                    let sym = res.isReachable ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
                    let col = res.isReachable ? "\u{001B}[32m" : "\u{001B}[31m"
                    emit("      \(sym) \(res.target.host.padding(toLength: 26, withPad: " ", startingAt: 0)): \(col)\(res.detail)\u{001B}[0m (\(res.latencyMs)ms)")
                }
            }

            let avgLatency = totalReachable > 0 ? (totalLatency / totalReachable) : 9999
            let p1Score = Phase1Score(
                profile: profile,
                unlockedCount: unlockedCount,
                reachableCount: totalReachable,
                totalTargets: targetsToTest.count,
                averageLatencyMs: avgLatency,
                timeouts: timeouts,
                customTargetsPassed: customPassed,
                totalCustomTargets: customTargets.count,
                results: resultMap
            )
            phase1Scores.append(p1Score)

            let unlockColor = (unlockedCount > 0) ? "\u{001B}[32m" : "\u{001B}[33m"
            let paddedId = profile.id.padding(toLength: 28, withPad: " ", startingAt: 0)
            var statusDetails = [String]()
            if !blockedTargets.isEmpty {
                statusDetails.append("\(unlockColor)+\(unlockedCount) unlocked\u{001B}[0m")
            }
            if !customTargets.isEmpty {
                let cColor = (customPassed == customTargets.count) ? "\u{001B}[32m" : "\u{001B}[31m"
                statusDetails.append("\(cColor)\(customPassed)/\(customTargets.count) custom ok\u{001B}[0m")
            }
            let detailStr = statusDetails.isEmpty ? "" : " (\(statusDetails.joined(separator: ", ")))"
            let statusSuffix = (totalReachable > 0)
                ? "\(totalReachable)/\(targetsToTest.count) reachable\(detailStr) (\(avgLatency)ms)"
                : "\u{001B}[31m0/\(targetsToTest.count) reachable (blocked)\u{001B}[0m"
            let idxPadded = String(format: "%2d", index + 1)
            emit("  [\(idxPadded)/\(candidateProfiles.count)] \(paddedId) \(statusSuffix)")
        }

        // Filter working profiles that unlocked at least 1 target or passed custom targets
        let workingContenders = phase1Scores
            .filter { score in
                if !customTargets.isEmpty && score.customTargetsPassed == 0 {
                    return false
                }
                return score.unlockedCount > 0 || (!customTargets.isEmpty && score.customTargetsPassed > 0)
            }
            .sorted { a, b in
                if a.customTargetsPassed != b.customTargetsPassed {
                    return a.customTargetsPassed > b.customTargetsPassed
                }
                if a.unlockedCount != b.unlockedCount {
                    return a.unlockedCount > b.unlockedCount
                }
                if a.timeouts != b.timeouts {
                    return a.timeouts < b.timeouts
                }
                return a.averageLatencyMs < b.averageLatencyMs
            }

        if workingContenders.isEmpty {
            emit("\n\u{001B}[33mWarning:\u{001B}[0m No profile was able to satisfy the DPI evasion criteria.")
            emit("Preserving default profile: \u{001B}[1m\(StrategyProfiles.defaultProfile.id)\u{001B}[0m\n")
            return StrategyProfiles.defaultProfile
        }

        // 4. Stage 2: Cross-Referencing & Multi-Round Stability Verification
        let topContenders = Array(workingContenders.prefix(4).map { $0.profile })
        
        let sampleReachable = Array(evalTargets.filter {
            !blockedSet.contains($0.host) && !customSet.contains($0.host) && (baselineResults[$0.host]?.isReachable ?? false)
        }.prefix(3))
        let crossTargets = targetsToTest + sampleReachable

        emit("\n\u{001B}[1mCross-Referencing Top Contenders (2-Round Stability Verification)...\u{001B}[0m")

        var crossScores = [CrossReferenceScore]()

        for contender in topContenders {
            guard let testProc = spawnTestCiadpi(profile: contender, port: testPort) else { continue }
            defer { terminateProcess(testProc) }

            // Round 1
            let round1Probes = probeConcurrently(targets: crossTargets, socksPort: testPort, timeout: 1.8, maxAttempts: 1)
            var r1Map = [String: ProbeResult]()
            for p in round1Probes { r1Map[p.target.host] = p }

            usleep(80_000)

            // Round 2
            let round2Probes = probeConcurrently(targets: crossTargets, socksPort: testPort, timeout: 1.8, maxAttempts: 1)
            var r2Map = [String: ProbeResult]()
            for p in round2Probes { r2Map[p.target.host] = p }

            var passes = 0
            var totalLatency = 0
            var latCount = 0
            var unblockedInBoth = 0
            var customPassedBoth = 0

            for target in blockedTargets {
                let p1 = r1Map[target.host]?.isReachable ?? false
                let p2 = r2Map[target.host]?.isReachable ?? false
                if p1 && p2 {
                    unblockedInBoth += 1
                }
            }

            for target in customTargets {
                let p1 = r1Map[target.host]?.isReachable ?? false
                let p2 = r2Map[target.host]?.isReachable ?? false
                if p1 && p2 {
                    customPassedBoth += 1
                }
            }

            for target in crossTargets {
                if let r1 = r1Map[target.host], r1.isReachable {
                    passes += 1
                    totalLatency += r1.latencyMs
                    latCount += 1
                }
                if let r2 = r2Map[target.host], r2.isReachable {
                    passes += 1
                    totalLatency += r2.latencyMs
                    latCount += 1
                }
            }

            let totalTests = crossTargets.count * 2
            let stability = Double(passes) / Double(totalTests)
            let avgLat = latCount > 0 ? (totalLatency / latCount) : 9999

            crossScores.append(CrossReferenceScore(
                profile: contender,
                round1Results: r1Map,
                round2Results: r2Map,
                stabilityRate: stability,
                totalPasses: passes,
                totalTests: totalTests,
                avgLatencyMs: avgLat,
                unlockedCount: unblockedInBoth,
                customPassedCount: customPassedBoth
            ))
        }

        printCrossReferenceMatrix(
            scores: crossScores,
            targets: crossTargets,
            blockedTargets: blockedTargets,
            customTargets: customTargets,
            emit: emit
        )

        let ranked = crossScores.sorted { a, b in
            if a.customPassedCount != b.customPassedCount {
                return a.customPassedCount > b.customPassedCount
            }
            if a.unlockedCount != b.unlockedCount {
                return a.unlockedCount > b.unlockedCount
            }
            if a.stabilityRate != b.stabilityRate {
                return a.stabilityRate > b.stabilityRate
            }
            if abs(a.avgLatencyMs - b.avgLatencyMs) > 35 {
                return a.avgLatencyMs < b.avgLatencyMs
            }
            return a.profile.complexity < b.profile.complexity
        }

        guard let winner = ranked.first else {
            emit("\nPreserving default profile: \u{001B}[1m\(StrategyProfiles.defaultProfile.name)\u{001B}[0m\n")
            return StrategyProfiles.defaultProfile
        }

        emit("\n\u{001B}[32m✓ Selected:\u{001B}[0m \u{001B}[1m\(winner.profile.id)\u{001B}[0m (\(winner.profile.name))")
        emit("  Family:      \(winner.profile.family)")
        emit("  Description: \(winner.profile.description)")
        emit("  Parameters:  \(winner.profile.args.joined(separator: " "))")
        emit("  Stability:   \(Int(winner.stabilityRate * 100))% (\(winner.totalPasses)/\(winner.totalTests) successful probes)")
        emit("  Avg Latency: \(winner.avgLatencyMs)ms\n")

        return winner.profile
    }

    /// Render a side-by-side cross-reference matrix
    private func printCrossReferenceMatrix(
        scores: [CrossReferenceScore],
        targets: [StrategyTarget],
        blockedTargets: [StrategyTarget],
        customTargets: [StrategyTarget],
        emit: (String) -> Void
    ) {
        guard !scores.isEmpty else { return }

        let targetColWidth = 24
        let scoreColWidth = 24
        let hrLen = targetColWidth + (scoreColWidth * scores.count) + 2
        let hr = String(repeating: "-", count: hrLen)

        emit(hr)
        var header = "Target".padding(toLength: targetColWidth, withPad: " ", startingAt: 0)
        for s in scores {
            let colName = s.profile.id.prefix(scoreColWidth - 2)
            header += "  " + String(colName).padding(toLength: scoreColWidth - 2, withPad: " ", startingAt: 0)
        }
        emit("\u{001B}[1m\(header)\u{001B}[0m")
        emit(hr)

        let blockedSet = Set(blockedTargets.map { $0.host })
        let customSet = Set(customTargets.map { $0.host })

        for target in targets {
            let tag: String
            if customSet.contains(target.host) {
                tag = "+"
            } else if blockedSet.contains(target.host) {
                tag = "*"
            } else {
                tag = " "
            }
            var row = "\(tag)\(target.host)".padding(toLength: targetColWidth, withPad: " ", startingAt: 0)

            for s in scores {
                let r1 = s.round1Results[target.host]
                let r2 = s.round2Results[target.host]
                let p1 = r1?.isReachable ?? false
                let p2 = r2?.isReachable ?? false

                let m1 = p1 ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
                let m2 = p2 ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
                let lat = p1 ? (r1?.latencyMs ?? 0) : (r2?.latencyMs ?? 0)
                let latStr = lat > 0 ? "\(lat)ms" : "fail"

                let colContent = "\(m1)\(m2) \(latStr)"
                // Account for ANSI escape codes when padding
                let visualLen = 3 + latStr.count // 2 symbols + 1 space + latStr
                let padNeeded = max(0, (scoreColWidth - 2) - visualLen)
                row += "  " + colContent + String(repeating: " ", count: padNeeded)
            }
            emit(row)
        }

        emit(hr)
        var stabRow = "Stability:".padding(toLength: targetColWidth, withPad: " ", startingAt: 0)
        for s in scores {
            let pct = "\(Int(s.stabilityRate * 100))% (\(s.totalPasses)/\(s.totalTests))"
            stabRow += "  " + pct.padding(toLength: scoreColWidth - 2, withPad: " ", startingAt: 0)
        }
        emit("\u{001B}[1m\(stabRow)\u{001B}[0m")

        var latRow = "Avg Latency:".padding(toLength: targetColWidth, withPad: " ", startingAt: 0)
        for s in scores {
            let latStr = "\(s.avgLatencyMs)ms"
            latRow += "  " + latStr.padding(toLength: scoreColWidth - 2, withPad: " ", startingAt: 0)
        }
        emit("\u{001B}[1m\(latRow)\u{001B}[0m")
        emit(hr)
        emit("(* = blocked on baseline network, + = custom target, ✓✓ = verified across both test rounds)")
    }

    /// Save the selected profile to routun.json
    public static func saveProfile(_ profile: StrategyProfile) -> Bool {
        var config = RoutunConfig.load()
        config.selectedProfile = profile.id
        config.ciadpiArgs = profile.fullArgs(host: config.socksHost, port: config.socksPort)

        do {
            try config.save()
            return true
        } catch {
            return false
        }
    }
}
