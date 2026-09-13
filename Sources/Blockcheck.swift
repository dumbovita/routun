import Foundation
import Darwin
import Dispatch

// MARK: - Strategy Target

public struct StrategyTarget: Hashable {
    public let name: String
    public let host: String
    public let port: Int
    public let path: String
    public let scheme: String
    public let isReference: Bool

    public init(name: String, host: String, port: Int = 443, path: String = "/", scheme: String? = nil, isReference: Bool = false) {
        self.name = name
        self.host = host
        self.port = port
        self.path = path
        self.scheme = scheme ?? (port == 80 ? "http" : "https")
        self.isReference = isReference
    }

    public var urlString: String {
        let defaultPort = scheme == "http" ? 80 : 443
        let portSuffix = port == defaultPort ? "" : ":\(port)"
        return "\(scheme)://\(host)\(portSuffix)\(path)"
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

        let scheme = (components.scheme ?? "https").lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }

        let port = components.port ?? (scheme == "http" ? 80 : 443)
        guard (1...65535).contains(port) else { return nil }

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let pathWithQuery = components.percentEncodedQuery.map { "\(path)?\($0)" } ?? path

        return StrategyTarget(
            name: cleanHost,
            host: cleanHost,
            port: port,
            path: pathWithQuery,
            scheme: scheme,
            isReference: false
        )
    }

    /// Parse a list of raw inputs, supporting comma-separated and space-separated strings
    public static func parseList(from rawList: [String]) -> [StrategyTarget] {
        var targets = [StrategyTarget]()
        var seen = Set<String>()
        for raw in rawList {
            let splitParts = raw.split { $0 == "," || $0.isWhitespace }
            for part in splitParts {
                if let target = parse(from: String(part)), !seen.contains(target.urlString) {
                    seen.insert(target.urlString)
                    targets.append(target)
                }
            }
        }
        return targets
    }
}

public enum StrategyTargets {
    /// Curated representative dataset combining major global platforms, restricted services, and infrastructure
    public static let all: [StrategyTarget] = [
        // Reference sanity check (unblocked connectivity baseline)
        StrategyTarget(name: "Apple", host: "apple.com", port: 443, path: "/", isReference: true),

        // Global platforms subject to censorship, DPI inspection, or judicial restrictions
        StrategyTarget(name: "Discord (Web/API)", host: "discord.com", port: 443, path: "/"),
        StrategyTarget(name: "Discord (Gateway)", host: "gateway.discord.gg", port: 443, path: "/"),
        StrategyTarget(name: "Roblox", host: "roblox.com", port: 443, path: "/"),
        StrategyTarget(name: "Wattpad", host: "wattpad.com", port: 443, path: "/"),
        StrategyTarget(name: "Pastebin", host: "pastebin.com", port: 443, path: "/"),
        StrategyTarget(name: "Internet Archive", host: "archive.org", port: 443, path: "/"),
        StrategyTarget(name: "Deutsche Welle", host: "dw.com", port: 443, path: "/"),
        StrategyTarget(name: "Tor Project", host: "torproject.org", port: 443, path: "/"),
        StrategyTarget(name: "BBC", host: "bbc.com", port: 443, path: "/"),
        StrategyTarget(name: "Chess.com", host: "chess.com", port: 443, path: "/"),
        StrategyTarget(name: "Signal", host: "signal.org", port: 443, path: "/"),

        // Infrastructure & Encrypted DNS
        StrategyTarget(name: "Cloudflare DNS", host: "cloudflare-dns.com", port: 443, path: "/"),
        StrategyTarget(name: "Cloudflare", host: "cloudflare.com", port: 443, path: "/"),

        // Major international social media & publishing services
        StrategyTarget(name: "Instagram", host: "instagram.com", port: 443, path: "/"),
        StrategyTarget(name: "X / Twitter", host: "x.com", port: 443, path: "/"),
        StrategyTarget(name: "YouTube", host: "youtube.com", port: 443, path: "/"),
        StrategyTarget(name: "Google Video CDN", host: "redirector.googlevideo.com", port: 443, path: "/"),
        StrategyTarget(name: "Twitch", host: "twitch.tv", port: 443, path: "/"),
        StrategyTarget(name: "Spotify", host: "spotify.com", port: 443, path: "/"),
        StrategyTarget(name: "Substack", host: "substack.com", port: 443, path: "/"),

        // Core daily reference & authentication endpoints
        StrategyTarget(name: "Google", host: "google.com", port: 443, path: "/"),
        StrategyTarget(name: "Wikipedia", host: "wikipedia.org", port: 443, path: "/"),
        StrategyTarget(name: "Reddit", host: "reddit.com", port: 443, path: "/"),
        StrategyTarget(name: "Microsoft Login", host: "login.microsoftonline.com", port: 443, path: "/"),
        StrategyTarget(name: "Xbox Live Auth", host: "user.auth.xboxlive.com", port: 443, path: "/")
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
    // MARK: - Canonical Curated Profiles (Darwin-Supported)
    public static let defaultProfile = StrategyProfile(
        id: "default",
        name: "Default (Balanced)",
        family: "Balanced",
        description: "Split, SNI disorder, TLS record split (known-safe fallback)",
        args: ["-s", "1", "-d", "3+s", "-r", "1+s"],
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
        description: "Reverse packet order delivery at SNI with TLS record split",
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

    public static let disorderSplitSni = StrategyProfile(
        id: "disorder-split-sni",
        name: "Disorder + Split (SNI)",
        family: "Disorder",
        description: "Disorder at byte 1 with SNI split at byte 3",
        args: ["-d", "1", "-s", "3+s"],
        complexity: 5
    )

    public static let canonical: [StrategyProfile] = [
        defaultProfile,
        simpleSplit,
        dualSplit,
        tlsrecSplit,
        disorderSni,
        oobSni,
        disorderSplitSni
    ]

    // MARK: - Exhaustive Combinations Matrix (Strictly macOS-Supported & Deduplicated)
    public static let allCombinations: [StrategyProfile] = [
        // Pure Splits
        StrategyProfile(id: "split-1", name: "Split 1", family: "Split", description: "Split at initial byte", args: ["-s", "1"], complexity: 1),
        StrategyProfile(id: "split-2", name: "Split 2", family: "Split", description: "Split at byte 2", args: ["-s", "2"], complexity: 1),
        StrategyProfile(id: "split-2s", name: "Split 2+s", family: "Split", description: "Split inside SNI", args: ["-s", "2+s"], complexity: 1),
        StrategyProfile(id: "split-3s", name: "Split 3+s", family: "Split", description: "Split at byte 3 of SNI", args: ["-s", "3+s"], complexity: 1),
        StrategyProfile(id: "split-se", name: "Split 0+s+e", family: "Split", description: "Split at end of SNI", args: ["-s", "0+s+e"], complexity: 1),
        StrategyProfile(id: "split-sm", name: "Split 0+s+m", family: "Split", description: "Split at middle of SNI", args: ["-s", "0+s+m"], complexity: 1),

        // Dual & Multi Splits
        StrategyProfile(id: "dual-split-1-1s", name: "Dual Split 1 + 1+s", family: "Dual Split", description: "Byte 1 split + SNI start split", args: ["-s", "1", "-s", "1+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1-3s", name: "Dual Split 1 + 3+s", family: "Dual Split", description: "Byte 1 split + SNI 3rd byte split", args: ["-s", "1", "-s", "3+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1-se", name: "Dual Split 1 + 0+s+e", family: "Dual Split", description: "Byte 1 split + SNI end split", args: ["-s", "1", "-s", "0+s+e"], complexity: 2),
        StrategyProfile(id: "dual-split-2-2s", name: "Dual Split 2 + 2+s", family: "Dual Split", description: "Byte 2 split + SNI 2nd byte split", args: ["-s", "2", "-s", "2+s"], complexity: 2),
        StrategyProfile(id: "dual-split-1s-2s", name: "Dual Split 1+s + 2+s", family: "Dual Split", description: "SNI start split + SNI 2nd byte split", args: ["-s", "1+s", "-s", "2+s"], complexity: 2),
        StrategyProfile(id: "multi-split", name: "Multi Split (1 + 2+s + 3+s)", family: "Dual Split", description: "Three-stage progressive split through SNI", args: ["-s", "1", "-s", "2+s", "-s", "3+s"], complexity: 3),

        // Pure Disorders
        StrategyProfile(id: "disorder-1s", name: "Disorder 1+s", family: "Disorder", description: "Reverse packet order at SNI start", args: ["-d", "1+s"], complexity: 3),
        StrategyProfile(id: "disorder-2s", name: "Disorder 2+s", family: "Disorder", description: "Reverse packet order inside SNI", args: ["-d", "2+s"], complexity: 3),
        StrategyProfile(id: "disorder-3s", name: "Disorder 3+s", family: "Disorder", description: "Reverse packet order at SNI byte 3", args: ["-d", "3+s"], complexity: 3),
        StrategyProfile(id: "disorder-se", name: "Disorder 0+s+e", family: "Disorder", description: "Reverse packet order at SNI end", args: ["-d", "0+s+e"], complexity: 3),
        StrategyProfile(id: "multi-disorder", name: "Multi-Stage Disorder", family: "Disorder", description: "Alternating multi-stage disorder and split ladder", args: ["-d", "1", "-s", "1+s", "-d", "3+s", "-s", "6+s"], complexity: 4),

        // Split + Disorder Combinations
        StrategyProfile(id: "split-1-disorder-1s", name: "Split 1 + Disorder 1+s", family: "Split+Disorder", description: "Byte 1 split + SNI start disorder", args: ["-s", "1", "-d", "1+s"], complexity: 4),
        StrategyProfile(id: "split-1-disorder-2s", name: "Split 1 + Disorder 2+s", family: "Split+Disorder", description: "Byte 1 split + SNI 2nd byte disorder", args: ["-s", "1", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "split-1-disorder-3s", name: "Split 1 + Disorder 3+s", family: "Split+Disorder", description: "Byte 1 split + SNI 3rd byte disorder", args: ["-s", "1", "-d", "3+s"], complexity: 4),
        StrategyProfile(id: "split-1-disorder-se", name: "Split 1 + Disorder 0+s+e", family: "Split+Disorder", description: "Byte 1 split + SNI end disorder", args: ["-s", "1", "-d", "0+s+e"], complexity: 4),
        StrategyProfile(id: "split-1s-disorder-2s", name: "Split 1+s + Disorder 2+s", family: "Split+Disorder", description: "SNI start split + SNI disorder", args: ["-s", "1+s", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "split-2-disorder-2s", name: "Split 2 + Disorder 2+s", family: "Split+Disorder", description: "Byte 2 split + SNI disorder", args: ["-s", "2", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "disorder-split-7-2", name: "Disorder 7 + Split 2", family: "Split+Disorder", description: "Disorder at byte 7 with early byte 2 split", args: ["-d", "7", "-s", "2"], complexity: 4),

        // TLS Record Splits
        StrategyProfile(id: "tlsrec-1s", name: "TLS Record 1+s", family: "TLS Record", description: "TLS record layer segmentation at SNI", args: ["-r", "1+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-2s", name: "TLS Record 2+s", family: "TLS Record", description: "TLS record layer segmentation inside SNI", args: ["-r", "2+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-1s-split-1s", name: "TLS Record 1+s + Split 1+s", family: "TLS Record", description: "TLS record split + SNI start split", args: ["-r", "1+s", "-s", "1+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-1s-split-2s", name: "TLS Record 1+s + Split 2+s", family: "TLS Record", description: "TLS record split + SNI byte 2 split", args: ["-r", "1+s", "-s", "2+s"], complexity: 3),
        StrategyProfile(id: "tlsrec-2s-split-1", name: "TLS Record 2+s + Split 1", family: "TLS Record", description: "TLS record inside SNI + byte 1 split", args: ["-r", "2+s", "-s", "1"], complexity: 3),

        // TLS Record + Disorder
        StrategyProfile(id: "tlsrec-1s-disorder-2s", name: "TLS Record 1+s + Disorder 2+s", family: "TLS Record", description: "TLS record split + SNI 2nd byte disorder", args: ["-r", "1+s", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-disorder-3s", name: "TLS Record 1+s + Disorder 3+s", family: "TLS Record", description: "TLS record split + SNI 3rd byte disorder", args: ["-r", "1+s", "-d", "3+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-split-1-disorder-2s", name: "TLS Record 1+s + Split 1 + Disorder 2+s", family: "TLS Record", description: "TLS record + byte 1 split + disorder 2+s", args: ["-r", "1+s", "-s", "1", "-d", "2+s"], complexity: 4),
        StrategyProfile(id: "tlsrec-1s-split-1-disorder-3s", name: "TLS Record 1+s + Split 1 + Disorder 3+s", family: "TLS Record", description: "TLS record + byte 1 split + disorder 3+s", args: ["-r", "1+s", "-s", "1", "-d", "3+s"], complexity: 4),

        // OOB & Disoob Combinations
        StrategyProfile(id: "oob-2s-split-1", name: "OOB 2+s + Split 1", family: "OOB", description: "OOB urgent byte inside SNI + byte 1 split", args: ["-o", "2+s", "-s", "1"], complexity: 5),
        StrategyProfile(id: "oob-1s-disorder-2s", name: "OOB 1+s + Disorder 2+s", family: "OOB", description: "OOB urgent byte at SNI start + disorder inside SNI", args: ["-o", "1+s", "-d", "2+s"], complexity: 5),
        StrategyProfile(id: "oob-1s-disorder-3s", name: "OOB 1+s + Disorder 3+s", family: "OOB", description: "OOB urgent byte at SNI start + disorder at SNI byte 3", args: ["-o", "1+s", "-d", "3+s"], complexity: 5),
        StrategyProfile(id: "oob-disorder-3-7", name: "OOB 3 + Disorder 7", family: "OOB", description: "Early OOB byte 3 combined with disorder 7", args: ["-o", "3", "-d", "7"], complexity: 5),
        StrategyProfile(id: "oob-split-dual", name: "OOB 1 + Dual Split 4, 6", family: "OOB", description: "Initial OOB urgent byte with subsequent splits", args: ["-o", "1", "-s", "4", "-s", "6"], complexity: 5),
        StrategyProfile(id: "disoob-1s-split-1", name: "Disoob 1+s + Split 1", family: "OOB", description: "Reverse order OOB urgent data at SNI start", args: ["-q", "1+s", "-s", "1"], complexity: 5),
        StrategyProfile(id: "disoob-2s-split-1", name: "Disoob 2+s + Split 1", family: "OOB", description: "Reverse order OOB urgent data inside SNI", args: ["-q", "2+s", "-s", "1"], complexity: 5),
        StrategyProfile(id: "disoob-tlsrec", name: "Disoob 1 + TLS Record 25+s", family: "OOB", description: "Disoob at start with deep TLS record segmentation", args: ["-q", "1", "-r", "25+s"], complexity: 5),
        StrategyProfile(id: "tlsrec-disorder-oob", name: "Disorder 1+s + OOB 2 + Split 5 + TLS Record 5", family: "OOB", description: "Composite evasion with disorder, OOB, split, and record slice", args: ["-d", "1+s", "-o", "2", "-s", "5", "-r", "5"], complexity: 5),

        // Protocol Modification (Supported on macOS)
        StrategyProfile(id: "modhttp-hcsmix-split", name: "HTTP Mix + Split 1+s", family: "HTTP Mod", description: "HTTP Header Case Mix + SNI Split", args: ["-M", "hcsmix", "-s", "1+s"], complexity: 2),
        StrategyProfile(id: "tlsminor-split", name: "TLS Minor Ver + Split 1+s", family: "TLS Mod", description: "Modify TLS ClientHello minor version + SNI Split", args: ["-m", "4", "-s", "1+s"], complexity: 2)
    ]

    /// Combined profile registry, deduplicated by ID and verified for Darwin capabilities
    public static var all: [StrategyProfile] {
        var seenIds = Set<String>()
        var seenArgs = Set<String>()
        var list = [StrategyProfile]()
        let cap = ByeDPICapability.darwinStandard

        for p in canonical + allCombinations {
            let argKey = p.args.joined(separator: " ")
            guard !seenIds.contains(p.id), !seenArgs.contains(argKey) else {
                continue
            }
            let (valid, _) = cap.validate(args: p.args)
            if valid {
                seenIds.insert(p.id)
                seenArgs.insert(argKey)
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

public enum FailureCategory: String, Codable {
    case none
    case timeout
    case tlsDpiBlock
    case dnsFailure
    case connectionReset
    case httpError
    case unknown
}

public struct ProbeResult {
    public let target: StrategyTarget
    public let isReachable: Bool
    public let latencyMs: Int
    public let statusCode: Int
    public let exitCode: Int32
    public let detail: String
    public let failureCategory: FailureCategory
    public let attempts: Int
    public let successfulAttempts: Int

    public var isReliable: Bool {
        successfulAttempts == attempts
    }

    public init(
        target: StrategyTarget,
        isReachable: Bool,
        latencyMs: Int,
        statusCode: Int,
        exitCode: Int32,
        detail: String,
        failureCategory: FailureCategory = .none,
        attempts: Int = 1,
        successfulAttempts: Int = 1
    ) {
        self.target = target
        self.isReachable = isReachable
        self.latencyMs = latencyMs
        self.statusCode = statusCode
        self.exitCode = exitCode
        self.detail = detail
        self.failureCategory = failureCategory
        self.attempts = attempts
        self.successfulAttempts = successfulAttempts
    }
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
    public let regressionCount: Int
    public let regressionHosts: [String]
}

// MARK: - Strategy Optimizer (Blockcheck Engine)

public final class StrategyOptimizer {
    public let ciadpiPath: String
    public let testPort: Int
    public let verbose: Bool
    public let quick: Bool
    public let customTargets: [StrategyTarget]

    private let physicalInterface: String?
    private let probeOverride: ((StrategyTarget, Int?, Double) -> ProbeResult)?
    private let activeProcessLock = NSLock()
    private var activeTestProcesses = [Int: Process]()

    public static func findFreePort(excluding: Set<Int> = []) -> Int {
        for _ in 0..<20 {
            let port = findFreePort()
            if !excluding.contains(port) {
                return port
            }
        }
        let fallback = (excluding.max() ?? 10885) + 1
        return fallback
    }

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

    public init(
        ciadpiPath: String? = nil,
        testPort: Int? = nil,
        verbose: Bool = false,
        quick: Bool = false,
        customTargets: [StrategyTarget] = [],
        probeOverride: ((StrategyTarget, Int?, Double) -> ProbeResult)? = nil
    ) {
        let config = RoutunConfig.load()
        self.ciadpiPath = ciadpiPath ?? config.ciadpiPath
        self.testPort = testPort ?? StrategyOptimizer.findFreePort()
        self.verbose = verbose
        self.quick = quick
        self.customTargets = customTargets
        self.physicalInterface = StrategyOptimizer.detectPhysicalInterface()
        self.probeOverride = probeOverride
    }

    public static func evaluationTargets(customTargets: [StrategyTarget]) -> [StrategyTarget] {
        var seenHosts = Set<String>()
        var targets = [StrategyTarget]()

        for target in customTargets + StrategyTargets.all where !target.isReference {
            if seenHosts.insert(target.host).inserted {
                targets.append(target)
            }
        }

        return targets
    }

    public func cancel() {
        activeProcessLock.lock()
        let processes = activeTestProcesses
        activeTestProcesses.removeAll()
        activeProcessLock.unlock()

        for (port, process) in processes {
            terminateProcess(process, port: port)
        }
    }

    /// Detect the active physical network interface for baseline tests.
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
        let (code, out) = ServiceManager.shared.runCommand("/sbin/route", ["-n", "get", "default"])
        if code == 0 {
            for line in out.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface: ") {
                    let iface = trimmed.replacingOccurrences(of: "interface: ", with: "")
                    if iface.hasPrefix("en") {
                        return iface
                    }
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
            "--connect-timeout", "3.0",
            "--max-time", String(format: "%.1f", max(timeout, 4.0)),
            "-A", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
        ]

        if let port = socksPort {
            // Use socks5-hostname so hostname resolution goes through the SOCKS proxy path
            args += ["--socks5-hostname", "127.0.0.1:\(port)"]
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

            var isReachable = false
            var category: FailureCategory = .none
            var detail = ""

            if exitCode == 0 {
                if statusCode >= 200 && statusCode < 400 {
                    isReachable = true
                    category = .none
                    detail = "HTTP \(statusCode)"
                } else if [400, 401, 404, 405, 415].contains(statusCode) {
                    // Standard application responses indicating TLS and HTTP handshake completed
                    isReachable = true
                    category = .none
                    detail = "HTTP \(statusCode)"
                } else if statusCode == 403 {
                    isReachable = false
                    category = .httpError
                    detail = "HTTP 403 (Forbidden/WAF)"
                } else if statusCode == 451 {
                    isReachable = false
                    category = .httpError
                    detail = "HTTP 451 (Unavailable For Legal Reasons)"
                } else if statusCode >= 500 {
                    isReachable = false
                    category = .httpError
                    detail = "HTTP \(statusCode) (Server Error)"
                } else {
                    isReachable = false
                    category = .unknown
                    detail = "HTTP \(statusCode)"
                }
            } else {
                switch exitCode {
                case 6:
                    category = .dnsFailure
                    detail = "DNS Resolution Failed"
                case 7:
                    category = .connectionReset
                    detail = "Connection Reset / Refused"
                case 28:
                    category = .timeout
                    detail = "Timeout"
                case 35:
                    category = .tlsDpiBlock
                    detail = "TLS Handshake Blocked (DPI)"
                case 52:
                    category = .tlsDpiBlock
                    detail = "Empty Reply (DPI Drop)"
                case 56:
                    category = .tlsDpiBlock
                    detail = "Connection Reset by Peer (DPI)"
                default:
                    category = .unknown
                    detail = "Curl Error (\(exitCode))"
                }
            }

            return ProbeResult(
                target: target,
                isReachable: isReachable,
                latencyMs: elapsedMs,
                statusCode: statusCode,
                exitCode: exitCode,
                detail: detail,
                failureCategory: category,
                attempts: 1,
                successfulAttempts: isReachable ? 1 : 0
            )
        } catch {
            return ProbeResult(
                target: target,
                isReachable: false,
                latencyMs: 0,
                statusCode: 0,
                exitCode: -1,
                detail: error.localizedDescription,
                failureCategory: .unknown,
                attempts: 1,
                successfulAttempts: 0
            )
        }
    }

    public func probe(target: StrategyTarget, socksPort: Int?, timeout: Double = 1.5, attempts: Int = 2) -> ProbeResult {
        let runProbe = probeOverride ?? { [self] target, socksPort, timeout in
            probeSingle(target: target, socksPort: socksPort, timeout: timeout)
        }
        let first = runProbe(target, socksPort, timeout)
        if attempts <= 1 {
            return first
        }
        usleep(30_000) // 30ms pause before retry
        let second = runProbe(target, socksPort, timeout)
        let successfulAttempts = first.successfulAttempts + second.successfulAttempts
        let selected = second.isReachable ? second : first.isReachable ? first : second
        let detail = successfulAttempts == 1 ? "\(selected.detail) (inconsistent: 1/2)" : selected.detail
        let category: FailureCategory = (successfulAttempts > 0) ? .none : (second.failureCategory != .none ? second.failureCategory : first.failureCategory)

        return ProbeResult(
            target: selected.target,
            isReachable: successfulAttempts > 0,
            latencyMs: selected.latencyMs,
            statusCode: selected.statusCode,
            exitCode: selected.exitCode,
            detail: detail,
            failureCategory: category,
            attempts: 2,
            successfulAttempts: successfulAttempts
        )
    }

    public func probeConcurrently(targets: [StrategyTarget], socksPort: Int?, timeout: Double = 1.5, attempts: Int = 2) -> [ProbeResult] {
        var results = [ProbeResult?](repeating: nil, count: targets.count)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: targets.count) { i in
            let res = self.probe(target: targets[i], socksPort: socksPort, timeout: timeout, attempts: attempts)
            lock.lock()
            results[i] = res
            lock.unlock()
        }

        return results.compactMap { $0 }
    }

    /// Launch a temporary isolated ByeDPI process on the test port
    private func spawnTestCiadpi(profile: StrategyProfile, port: Int) -> Process? {
        guard FileManager.default.isExecutableFile(atPath: ciadpiPath) else { return nil }

        // If port is lingering from previous test, wait up to 200ms for it to close
        if NetUtils.isPortOpen(host: "127.0.0.1", port: port, timeout: 0.02) {
            _ = NetUtils.waitForPortToClose(host: "127.0.0.1", port: port, timeout: 0.2)
            if NetUtils.isPortOpen(host: "127.0.0.1", port: port, timeout: 0.02) {
                return nil
            }
        }

        let cap = ByeDPICapability.darwinStandard
        let sanitizedArgs = cap.sanitize(args: profile.args)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ciadpiPath)
        proc.arguments = ["-i", "127.0.0.1", "-p", String(port), "-A", "torst,ssl_err"] + sanitizedArgs + ["-c", "128"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }

        // Wait up to 300ms for this specific process to start listening (checking every 15ms)
        for _ in 0..<20 {
            guard proc.isRunning else {
                proc.waitUntilExit()
                return nil
            }
            if NetUtils.isPortOpen(host: "127.0.0.1", port: port, timeout: 0.015) {
                return proc
            }
            usleep(15_000)
        }

        terminateProcess(proc, port: port)
        return nil
    }

    /// Cleanly terminate a process with SIGTERM/SIGINT and SIGKILL fallback, and wait for port release
    private func terminateProcess(_ proc: Process, port: Int? = nil) {
        if proc.isRunning {
            proc.terminate()
            kill(proc.processIdentifier, SIGINT)
            for _ in 0..<5 {
                if !proc.isRunning { break }
                usleep(20_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        proc.waitUntilExit()
        if let port = port {
            _ = NetUtils.waitForPortToClose(host: "127.0.0.1", port: port, timeout: 0.3)
        }
    }

    private func setActiveTestProcess(_ process: Process?, for port: Int) {
        activeProcessLock.lock()
        if let process {
            activeTestProcesses[port] = process
        } else {
            activeTestProcesses.removeValue(forKey: port)
        }
        activeProcessLock.unlock()
    }

    private func evaluateProfile(
        profile: StrategyProfile,
        index: Int,
        totalProfiles: Int,
        port: Int,
        evalTargets: [StrategyTarget],
        blockedTargets: [StrategyTarget],
        customTargets: [StrategyTarget],
        baselineReachableHosts: Set<String>,
        baselineReachableCount: Int,
        verbose: Bool
    ) -> (Phase1Score, String) {
        let idxPadded = String(format: "%2d", index + 1)
        let paddedId = profile.id.padding(toLength: 28, withPad: " ", startingAt: 0)

        guard let testProc = spawnTestCiadpi(profile: profile, port: port) else {
            let errLog = "  [\(idxPadded)/\(totalProfiles)] \(paddedId) \u{001B}[31mFailed to launch test instance\u{001B}[0m"
            let fallbackScore = Phase1Score(
                profile: profile,
                unlockedCount: 0,
                reachableCount: 0,
                totalTargets: evalTargets.count,
                averageLatencyMs: 9999,
                timeouts: 0,
                customTargetsPassed: 0,
                totalCustomTargets: customTargets.count,
                regressionCount: baselineReachableHosts.count,
                regressionHosts: Array(baselineReachableHosts)
            )
            return (fallbackScore, errLog)
        }

        setActiveTestProcess(testProc, for: port)
        defer {
            terminateProcess(testProc, port: port)
            setActiveTestProcess(nil, for: port)
        }

        let blockedSet = Set(blockedTargets.map { $0.host })
        let customSet = Set(customTargets.map { $0.host })

        // 1. Two-stage screening: test blocked & custom targets first
        let screenTargets = evalTargets.filter { blockedSet.contains($0.host) || customSet.contains($0.host) }
        let initialTargets = screenTargets.isEmpty ? evalTargets : screenTargets

        let initialResults = probeConcurrently(targets: initialTargets, socksPort: port, timeout: 2.0, attempts: 1)

        var unlockedCount = 0
        var customPassed = 0
        for res in initialResults {
            if res.isReachable {
                if blockedSet.contains(res.target.host) { unlockedCount += 1 }
                if customSet.contains(res.target.host) { customPassed += 1 }
            }
        }

        let isContender = (unlockedCount > 0) || (!customTargets.isEmpty && customPassed > 0)

        var allResults: [ProbeResult]
        var totalReachable = 0
        var totalLatency = 0
        var timeouts = 0
        var regressions = [String]()

        if !isContender && !blockedTargets.isEmpty {
            // Early Exit: profile unlocked 0 targets; skip remaining targets to save time and bandwidth
            allResults = initialResults
            totalReachable = baselineReachableCount - (blockedTargets.count - unlockedCount)
            timeouts = initialResults.filter { $0.exitCode == 28 }.count
            let passedInitial = initialResults.filter { $0.isReachable }
            totalLatency = passedInitial.reduce(0) { $0 + $1.latencyMs }
        } else {
            // Viable candidate: evaluate remaining targets to verify zero regressions
            let remainingTargets = evalTargets.filter { target in
                !initialTargets.contains(where: { $0.host == target.host })
            }

            let remainingResults = probeConcurrently(targets: remainingTargets, socksPort: port, timeout: 2.0, attempts: 1)
            allResults = initialResults + remainingResults

            // Transient jitter recovery: if a baseline-healthy target failed on single probe, retry once
            for i in 0..<allResults.count {
                let res = allResults[i]
                if !res.isReachable && baselineReachableHosts.contains(res.target.host) {
                    let retry = self.probe(target: res.target, socksPort: port, timeout: 3.0, attempts: 1)
                    if retry.isReachable {
                        allResults[i] = retry
                    }
                }
            }

            let candidateReachableHosts = Set(allResults.filter { $0.isReachable }.map { $0.target.host })
            regressions = Array(baselineReachableHosts.subtracting(candidateReachableHosts)).sorted()

            unlockedCount = 0
            customPassed = 0
            totalReachable = 0
            totalLatency = 0
            timeouts = 0

            for res in allResults {
                if res.isReachable {
                    totalReachable += 1
                    totalLatency += res.latencyMs
                    if blockedSet.contains(res.target.host) { unlockedCount += 1 }
                    if customSet.contains(res.target.host) { customPassed += 1 }
                } else if res.exitCode == 28 {
                    timeouts += 1
                }
            }
        }

        let passedCount = isContender ? totalReachable : (initialResults.filter { $0.isReachable }.count)
        let avgLatency = passedCount > 0 ? (totalLatency / passedCount) : 9999
        let score = Phase1Score(
            profile: profile,
            unlockedCount: unlockedCount,
            reachableCount: totalReachable,
            totalTargets: evalTargets.count,
            averageLatencyMs: avgLatency,
            timeouts: timeouts,
            customTargetsPassed: customPassed,
            totalCustomTargets: customTargets.count,
            regressionCount: regressions.count,
            regressionHosts: regressions
        )

        let unlockColor = (unlockedCount > 0) ? "\u{001B}[32m" : "\u{001B}[33m"
        var statusDetails = [String]()
        if !blockedTargets.isEmpty {
            statusDetails.append("\(unlockColor)+\(unlockedCount) unlocked\u{001B}[0m")
        }
        if regressions.count > 0 {
            statusDetails.append("\u{001B}[31m-\(regressions.count) regressed\u{001B}[0m")
        }
        if !customTargets.isEmpty {
            let cColor = (customPassed == customTargets.count) ? "\u{001B}[32m" : "\u{001B}[31m"
            statusDetails.append("\(cColor)\(customPassed)/\(customTargets.count) custom ok\u{001B}[0m")
        }
        let detailStr = statusDetails.isEmpty ? "" : " (\(statusDetails.joined(separator: ", ")))"
        let statusSuffix = (totalReachable > 0)
            ? "\(totalReachable)/\(evalTargets.count) reachable\(detailStr) (\(avgLatency)ms)"
            : "\u{001B}[31m0/\(evalTargets.count) reachable (blocked)\u{001B}[0m"

        var logOutput = "  [\(idxPadded)/\(totalProfiles)] \(paddedId) \(statusSuffix)"

        if verbose {
            for res in allResults {
                let sym = res.isReachable ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
                let col = res.isReachable ? "\u{001B}[32m" : "\u{001B}[31m"
                logOutput += "\n      \(sym) \(res.target.host.padding(toLength: 26, withPad: " ", startingAt: 0)): \(col)\(res.detail)\u{001B}[0m (\(res.latencyMs)ms)"
            }
        }

        return (score, logOutput)
    }

    /// Run the comprehensive strategy optimization routine.
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
        let refResult = probe(target: refTarget, socksPort: nil, timeout: 2.5)
        if !refResult.isReachable && refResult.exitCode == 6 {
            emit("\u{001B}[31mError:\u{001B}[0m No internet connection or DNS resolution failure detected.")
            emit("Please verify your internet connection before running strategy optimization.")
            return nil
        }

        // 2. Establish Baseline (Direct physical connection without ByeDPI)
        let evalTargets = StrategyOptimizer.evaluationTargets(customTargets: customTargets)

        if !customTargets.isEmpty {
            emit("Custom targets added (\(customTargets.count)): \(customTargets.map { $0.host }.joined(separator: ", "))\n")
        }

        var baselineResults = [String: ProbeResult]()
        var baselineReachableCount = 0

        let directProbes = probeConcurrently(targets: evalTargets, socksPort: nil, timeout: 2.0)
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

        let baselineReachableHosts = Set(evalTargets.filter { baselineResults[$0.host]?.isReachable ?? false }.map { $0.host })
        let blockedTargets = evalTargets.filter { !baselineReachableHosts.contains($0.host) }
        emit("Baseline (Direct): \(baselineReachableCount)/\(evalTargets.count) reachable (\(blockedTargets.count) blocked by DPI)\n")

        if blockedTargets.isEmpty {
            emit("\u{001B}[32mAll test targets are directly accessible on your current network without DPI bypass.\u{001B}[0m")
            emit("Keeping default profile: \u{001B}[1m\(StrategyProfiles.defaultProfile.name)\u{001B}[0m\n")
            return StrategyProfiles.defaultProfile
        }

        let candidateProfiles = quick ? StrategyProfiles.canonical : StrategyProfiles.all
        let modeLabel = quick ? "canonical profiles" : "comprehensive combinations matrix"
        emit("Testing \(candidateProfiles.count) \(modeLabel) (Full \(evalTargets.count)-target regression check):")

        let blockedSet = Set(blockedTargets.map { $0.host })
        let customSet = Set(customTargets.map { $0.host })

        // Worker allocation: 2 concurrent workers on isolated ports for optimal speed and zero port conflicts
        let workerCount = min(2, candidateProfiles.count)
        var workerPorts = [testPort]
        if workerCount > 1 {
            let p2 = StrategyOptimizer.findFreePort(excluding: Set(workerPorts))
            workerPorts.append(p2)
        }

        var phase1Scores = [Phase1Score?](repeating: nil, count: candidateProfiles.count)
        var phase1Logs = [String?](repeating: nil, count: candidateProfiles.count)

        var nextIndex = 0
        let queueLock = NSLock()
        var nextPrintIndex = 0
        let printLock = NSLock()

        func flushLogs() {
            printLock.lock()
            defer { printLock.unlock() }
            while nextPrintIndex < candidateProfiles.count, let log = phase1Logs[nextPrintIndex] {
                emit(log)
                nextPrintIndex += 1
            }
        }

        let group = DispatchGroup()
        for workerId in 0..<workerCount {
            let port = workerPorts[workerId]
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                while true {
                    queueLock.lock()
                    if nextIndex >= candidateProfiles.count {
                        queueLock.unlock()
                        break
                    }
                    let index = nextIndex
                    nextIndex += 1
                    queueLock.unlock()

                    let profile = candidateProfiles[index]
                    let (score, log) = self.evaluateProfile(
                        profile: profile,
                        index: index,
                        totalProfiles: candidateProfiles.count,
                        port: port,
                        evalTargets: evalTargets,
                        blockedTargets: blockedTargets,
                        customTargets: self.customTargets,
                        baselineReachableHosts: baselineReachableHosts,
                        baselineReachableCount: baselineReachableCount,
                        verbose: self.verbose
                    )

                    printLock.lock()
                    phase1Scores[index] = score
                    phase1Logs[index] = log
                    printLock.unlock()

                    flushLogs()
                }
            }
        }
        group.wait()

        let validScores = phase1Scores.compactMap { $0 }

        // STRICT REGRESSION FILTER:
        // A profile is only accepted if it resolves blocked links WITHOUT causing regressions on any existing links.
        let zeroRegressionContenders = validScores.filter { score in
            guard score.regressionCount == 0 else { return false }
            if !customTargets.isEmpty && score.customTargetsPassed == 0 {
                return false
            }
            return score.unlockedCount > 0 || (!customTargets.isEmpty && score.customTargetsPassed > 0)
        }

        if zeroRegressionContenders.isEmpty {
            emit("\n\u{001B}[33mWarning:\u{001B}[0m No profile satisfied DPI evasion without causing regressions on other targets.")
            emit("Preserving default profile to prevent breaking working services: \u{001B}[1m\(StrategyProfiles.defaultProfile.id)\u{001B}[0m\n")
            return StrategyProfiles.defaultProfile
        }

        let rankedContenders = zeroRegressionContenders.sorted { a, b in
            if a.customTargetsPassed != b.customTargetsPassed {
                return a.customTargetsPassed > b.customTargetsPassed
            }
            if a.unlockedCount != b.unlockedCount {
                return a.unlockedCount > b.unlockedCount
            }
            if a.reachableCount != b.reachableCount {
                return a.reachableCount > b.reachableCount
            }
            if a.timeouts != b.timeouts {
                return a.timeouts < b.timeouts
            }
            if a.averageLatencyMs != b.averageLatencyMs {
                return a.averageLatencyMs < b.averageLatencyMs
            }
            return a.profile.complexity < b.profile.complexity
        }

        // Stage 2: Thorough stability verification of top contenders across all targets with 2 attempts
        let topContenders = Array(rankedContenders.prefix(5))
        emit("\nVerifying \(topContenders.count) top zero-regression contender(s) across all \(evalTargets.count) targets for stability:")

        var verifiedScores = [Phase1Score]()
        for (idx, contender) in topContenders.enumerated() {
            guard let testProc = spawnTestCiadpi(profile: contender.profile, port: testPort) else { continue }
            setActiveTestProcess(testProc, for: testPort)

            var fullResults = probeConcurrently(targets: evalTargets, socksPort: testPort, timeout: 2.5, attempts: 2)

            // Tiebreaker probe if a baseline-reachable target succeeded 1/2 attempts
            for i in 0..<fullResults.count {
                let res = fullResults[i]
                if baselineReachableHosts.contains(res.target.host) && !res.isReliable && res.successfulAttempts > 0 {
                    let tiebreaker = self.probe(target: res.target, socksPort: testPort, timeout: 3.0, attempts: 1)
                    if tiebreaker.isReachable {
                        fullResults[i] = ProbeResult(
                            target: res.target,
                            isReachable: true,
                            latencyMs: (res.latencyMs + tiebreaker.latencyMs) / 2,
                            statusCode: tiebreaker.statusCode,
                            exitCode: tiebreaker.exitCode,
                            detail: "\(tiebreaker.detail) (recovered: 2/3)",
                            failureCategory: .none,
                            attempts: 2,
                            successfulAttempts: 2
                        )
                    }
                }
            }

            terminateProcess(testProc, port: testPort)
            setActiveTestProcess(nil, for: testPort)
            let candidateReachableHosts = Set(fullResults.filter { $0.isReliable }.map { $0.target.host })
            var totalReachable = 0
            var unlockedCount = 0
            var customPassed = 0
            var totalLatency = 0
            var timeouts = 0

            for res in fullResults {
                if res.isReliable {
                    totalReachable += 1
                    totalLatency += res.latencyMs
                    if blockedSet.contains(res.target.host) { unlockedCount += 1 }
                    if customSet.contains(res.target.host) { customPassed += 1 }
                } else if !res.isReachable && res.exitCode == 28 {
                    timeouts += 1
                }
            }

            let regressions = Array(baselineReachableHosts.subtracting(candidateReachableHosts)).sorted()
            let avgLat = totalReachable > 0 ? (totalLatency / totalReachable) : 9999
            let score = Phase1Score(
                profile: contender.profile,
                unlockedCount: unlockedCount,
                reachableCount: totalReachable,
                totalTargets: evalTargets.count,
                averageLatencyMs: avgLat,
                timeouts: timeouts,
                customTargetsPassed: customPassed,
                totalCustomTargets: customTargets.count,
                regressionCount: regressions.count,
                regressionHosts: regressions
            )
            verifiedScores.append(score)

            let paddedId = contender.profile.id.padding(toLength: 28, withPad: " ", startingAt: 0)
            let unlockColor = (unlockedCount > 0) ? "\u{001B}[32m" : "\u{001B}[33m"
            var regStatus = ""
            if !regressions.isEmpty {
                regStatus = " \u{001B}[31m(-\(regressions.count) regressed)\u{001B}[0m"
            }
            let statusSuffix = "\(totalReachable)/\(evalTargets.count) verified (\(unlockColor)+\(unlockedCount) unlocked\u{001B}[0m)\(regStatus) (\(avgLat)ms)"
            emit("  [\(idx + 1)/\(topContenders.count)] \(paddedId) \(statusSuffix)")
        }

        let ranked = verifiedScores
            .filter { $0.regressionCount == 0 }
            .sorted { a, b in
                if a.customTargetsPassed != b.customTargetsPassed {
                    return a.customTargetsPassed > b.customTargetsPassed
                }
                if a.unlockedCount != b.unlockedCount {
                    return a.unlockedCount > b.unlockedCount
                }
                if a.reachableCount != b.reachableCount {
                    return a.reachableCount > b.reachableCount
                }
                if a.timeouts != b.timeouts {
                    return a.timeouts < b.timeouts
                }
                if a.averageLatencyMs != b.averageLatencyMs {
                    return a.averageLatencyMs < b.averageLatencyMs
                }
                return a.profile.complexity < b.profile.complexity
            }

        guard let winner = ranked.first ?? rankedContenders.first else {
            emit("\n\u{001B}[33mWarning:\u{001B}[0m No profile satisfied zero-regression criteria in full verification.")
            return StrategyProfiles.defaultProfile
        }

        emit("\n\u{001B}[32m✓ Selected:\u{001B}[0m \u{001B}[1m\(winner.profile.id)\u{001B}[0m (\(winner.profile.name))")
        emit("  Family:      \(winner.profile.family)")
        emit("  Description: \(winner.profile.description)")
        emit("  Parameters:  \(winner.profile.args.joined(separator: " "))")
        emit("  Reliability: \(winner.reachableCount)/\(winner.totalTargets) targets passed both probes (0 regressions)")
        emit("  Avg Latency: \(winner.averageLatencyMs)ms\n")

        return winner.profile
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
