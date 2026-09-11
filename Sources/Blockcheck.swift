import Foundation
import Darwin

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
}

public enum StrategyTargets {
    /// Centralized, curated list of representative endpoints for testing DPI evasion
    public static let all: [StrategyTarget] = [
        // Reference sanity check (unblocked connectivity baseline)
        StrategyTarget(name: "Apple (Reference)", host: "apple.com", port: 443, path: "/", isReference: true),

        // Primary VoIP & Messaging DPI Targets
        StrategyTarget(name: "Discord (Web/API)", host: "discord.com", port: 443, path: "/"),
        StrategyTarget(name: "Discord (Gateway)", host: "gateway.discord.gg", port: 443, path: "/"),

        // Social Media & TLS SNI Blocking
        StrategyTarget(name: "X / Twitter", host: "x.com", port: 443, path: "/"),
        StrategyTarget(name: "Instagram", host: "instagram.com", port: 443, path: "/"),
        StrategyTarget(name: "Facebook", host: "facebook.com", port: 443, path: "/"),

        // Video & CDN Media Streaming
        StrategyTarget(name: "YouTube", host: "youtube.com", port: 443, path: "/"),
        StrategyTarget(name: "Google Video CDN", host: "redirector.googlevideo.com", port: 443, path: "/"),

        // Content Platforms & News
        StrategyTarget(name: "Medium", host: "medium.com", port: 443, path: "/"),
        StrategyTarget(name: "Meduza", host: "meduza.io", port: 443, path: "/"),
        StrategyTarget(name: "RuTracker", host: "rutracker.org", port: 443, path: "/"),
        StrategyTarget(name: "Tor Project", host: "torproject.org", port: 443, path: "/")
    ]
}

// MARK: - Strategy Profile

public struct StrategyProfile: Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let args: [String]
    public let complexity: Int

    public init(id: String, name: String, description: String, args: [String], complexity: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.args = args
        self.complexity = complexity
    }

    /// Complete ByeDPI command line arguments with binding and listen port
    public func fullArgs(host: String = "127.0.0.1", port: Int = 1080, maxConn: Int = 512) -> [String] {
        return ["-i", host, "-p", String(port)] + args + ["-c", String(maxConn)]
    }
}

public enum StrategyProfiles {
    public static let defaultProfile = StrategyProfile(
        id: "default",
        name: "Default (Balanced)",
        description: "Split, SNI disorder, TLS record split (known-safe fallback)",
        args: ["-s", "1", "-d", "3+s", "-r", "1+s", "-t", "3"],
        complexity: 0
    )

    public static let simpleSplit = StrategyProfile(
        id: "simple-split",
        name: "Minimal Split",
        description: "Lightweight single split at SNI start with minimal overhead",
        args: ["-s", "1+s"],
        complexity: 1
    )

    public static let dualSplit = StrategyProfile(
        id: "dual-split",
        name: "Dual Split",
        description: "Two-stage split at initial byte and within SNI",
        args: ["-s", "1", "-s", "2+s"],
        complexity: 2
    )

    public static let tlsrecSplit = StrategyProfile(
        id: "tlsrec-split",
        name: "TLS Record Split",
        description: "TLS record layer segmentation at SNI",
        args: ["-r", "1+s", "-s", "1"],
        complexity: 3
    )

    public static let disorderSni = StrategyProfile(
        id: "disorder-sni",
        name: "SNI Disorder",
        description: "Reverse packet order delivery at SNI",
        args: ["-d", "1+s", "-r", "1+s"],
        complexity: 4
    )

    public static let oobSni = StrategyProfile(
        id: "oob-sni",
        name: "OOB Byte Injection",
        description: "Out-of-band urgent byte into SNI to choke DPI parsers",
        args: ["-o", "1+s", "-s", "1"],
        complexity: 5
    )

    public static let fakeDisorder = StrategyProfile(
        id: "fake-disorder",
        name: "Fake TTL + Disorder",
        description: "Low-TTL dummy packet injection + SNI disorder",
        args: ["-t", "3", "-s", "1", "-d", "2+s", "-r", "1+s"],
        complexity: 6
    )

    /// Curated, supported strategy profiles list
    public static let all: [StrategyProfile] = [
        defaultProfile,
        simpleSplit,
        dualSplit,
        tlsrecSplit,
        disorderSni,
        oobSni,
        fakeDisorder
    ]

    public static func find(by nameOrId: String) -> StrategyProfile? {
        let needle = nameOrId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.id.lowercased() == needle || $0.name.lowercased() == needle }
    }
}

// MARK: - Probe Result & Score

public struct ProbeResult {
    public let target: StrategyTarget
    public let isReachable: Bool
    public let latencyMs: Int
    public let statusCode: Int
    public let exitCode: Int32
    public let detail: String
}

public struct ProfileScore {
    public let profile: StrategyProfile
    public let unlockedCount: Int
    public let reachableCount: Int
    public let totalTargets: Int
    public let averageLatencyMs: Int
    public let timeouts: Int
    public let results: [String: ProbeResult]

    public var summary: String {
        return "\(reachableCount)/\(totalTargets) reachable (+\(unlockedCount) unlocked) (\(averageLatencyMs)ms)"
    }
}

// MARK: - Strategy Optimizer (Blockcheck)

public final class StrategyOptimizer {
    public let ciadpiPath: String
    public let testPort: Int
    public let verbose: Bool

    private let physicalInterface: String?

    public init(ciadpiPath: String? = nil, testPort: Int = 1085, verbose: Bool = false) {
        let config = RoutunConfig.load()
        self.ciadpiPath = ciadpiPath ?? config.ciadpiPath
        self.testPort = testPort
        self.verbose = verbose
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
    public func probe(target: StrategyTarget, socksPort: Int?, timeout: Double = 2.5) -> ProbeResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        var args = [
            "-s",
            "-o", "/dev/null",
            "-w", "%{http_code} %{time_total}",
            "--connect-timeout", "2",
            "--max-time", String(format: "%.1f", timeout),
            "-A", "Mozilla/5.0 (Macintosh; Apple Mac OS X) routun-blockcheck/1.0"
        ]

        if let port = socksPort {
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
            let isReachable = (exitCode == 0) && (statusCode > 0 && statusCode < 500)

            var detail = "HTTP \(statusCode)"
            if exitCode != 0 {
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
                detail: detail
            )
        } catch {
            return ProbeResult(
                target: target,
                isReachable: false,
                latencyMs: 0,
                statusCode: 0,
                exitCode: -1,
                detail: error.localizedDescription
            )
        }
    }

    /// Launch a temporary isolated ByeDPI process on the test port
    private func spawnTestCiadpi(profile: StrategyProfile, port: Int) -> Process? {
        guard FileManager.default.isExecutableFile(atPath: ciadpiPath) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ciadpiPath)
        proc.arguments = ["-i", "127.0.0.1", "-p", String(port)] + profile.args + ["-c", "64"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }

        // Wait up to 800ms for the test port to start listening
        for _ in 0..<8 {
            if NetUtils.isPortOpen(host: "127.0.0.1", port: port, timeout: 0.1) {
                return proc
            }
            usleep(100_000)
        }

        proc.terminate()
        return nil
    }

    /// Cleanly terminate a process with SIGTERM and SIGKILL fallback
    private func terminateProcess(_ proc: Process) {
        if proc.isRunning {
            proc.terminate()
            for _ in 0..<5 {
                if !proc.isRunning { return }
                usleep(50_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
                proc.waitUntilExit()
            }
        }
    }

    /// Run full optimization routine and return the best strategy profile
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
        let refResult = probe(target: refTarget, socksPort: nil, timeout: 3.0)
        if !refResult.isReachable && refResult.exitCode == 6 {
            emit("\u{001B}[31mError:\u{001B}[0m No internet connection or DNS resolution failure detected.")
            emit("Please verify your internet connection before running strategy optimization.")
            return nil
        }

        // 2. Establish Baseline (Direct physical connection without ByeDPI)
        let evalTargets = StrategyTargets.all.filter { !$0.isReference }
        var baselineResults = [String: ProbeResult]()
        var baselineReachableCount = 0

        for target in evalTargets {
            let res = probe(target: target, socksPort: nil, timeout: 2.0)
            baselineResults[target.host] = res
            if res.isReachable {
                baselineReachableCount += 1
            }
            if verbose {
                let color = res.isReachable ? "\u{001B}[32m" : "\u{001B}[33m"
                emit("  [Baseline] \(target.name.padding(toLength: 22, withPad: " ", startingAt: 0)): \(color)\(res.detail)\u{001B}[0m (\(res.latencyMs)ms)")
            }
        }

        let blockedTargets = evalTargets.filter { !(baselineResults[$0.host]?.isReachable ?? false) }
        emit("Baseline (Direct): \(baselineReachableCount)/\(evalTargets.count) reachable (\(blockedTargets.count) blocked by DPI)\n")

        if blockedTargets.isEmpty {
            emit("\u{001B}[32mAll test targets are directly accessible on your current network without DPI bypass.\u{001B}[0m")
            emit("Keeping default profile: \u{001B}[1m\(StrategyProfiles.defaultProfile.name)\u{001B}[0m\n")
            return StrategyProfiles.defaultProfile
        }

        // 3. Test Each Strategy Profile on an Ephemeral Port
        emit("Testing supported bypass profiles:")
        var scores = [ProfileScore]()

        for (index, profile) in StrategyProfiles.all.enumerated() {
            guard let testProc = spawnTestCiadpi(profile: profile, port: testPort) else {
                emit("  [\(index + 1)/\(StrategyProfiles.all.count)] \(profile.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \u{001B}[31mFailed to launch test instance\u{001B}[0m")
                continue
            }

            defer {
                terminateProcess(testProc)
            }

            var profileResults = [String: ProbeResult]()
            var unlockedCount = 0
            var reachableCount = 0
            var totalLatency = 0
            var timeouts = 0

            // Test blocked targets first
            for target in blockedTargets {
                let res = probe(target: target, socksPort: testPort, timeout: 2.5)
                profileResults[target.host] = res
                if res.isReachable {
                    unlockedCount += 1
                    reachableCount += 1
                    totalLatency += res.latencyMs
                } else if res.exitCode == 28 {
                    timeouts += 1
                }
            }

            // Test a sample of baseline-reachable targets to verify no regression
            let sampleReachable = evalTargets.filter { baselineResults[$0.host]?.isReachable ?? false }.prefix(3)
            for target in sampleReachable {
                let res = probe(target: target, socksPort: testPort, timeout: 2.5)
                profileResults[target.host] = res
                if res.isReachable {
                    reachableCount += 1
                    totalLatency += res.latencyMs
                }
            }

            let effectiveTested = blockedTargets.count + sampleReachable.count
            let avgLatency = reachableCount > 0 ? (totalLatency / reachableCount) : 9999

            let score = ProfileScore(
                profile: profile,
                unlockedCount: unlockedCount,
                reachableCount: reachableCount,
                totalTargets: effectiveTested,
                averageLatencyMs: avgLatency,
                timeouts: timeouts,
                results: profileResults
            )
            scores.append(score)

            let unlockColor = (unlockedCount > 0) ? "\u{001B}[32m" : "\u{001B}[33m"
            let paddedId = profile.id.padding(toLength: 16, withPad: " ", startingAt: 0)
            let progressStr = "  [\(index + 1)/\(StrategyProfiles.all.count)] \(paddedId) \(reachableCount)/\(effectiveTested) reachable (\(unlockColor)+\(unlockedCount) unlocked\u{001B}[0m) (\(avgLatency)ms)"
            emit(progressStr)
        }

        // 4. Deterministic Ranking & Selection
        // Prioritize:
        // 1. unlockedCount (descending)
        // 2. reachableCount (descending)
        // 3. timeouts (ascending)
        // 4. averageLatencyMs (ascending)
        // 5. complexity (ascending: default/simpler strategies win ties)
        let ranked = scores.sorted { a, b in
            if a.unlockedCount != b.unlockedCount {
                return a.unlockedCount > b.unlockedCount
            }
            if a.reachableCount != b.reachableCount {
                return a.reachableCount > b.reachableCount
            }
            if a.timeouts != b.timeouts {
                return a.timeouts < b.timeouts
            }
            if abs(a.averageLatencyMs - b.averageLatencyMs) > 40 {
                return a.averageLatencyMs < b.averageLatencyMs
            }
            return a.profile.complexity < b.profile.complexity
        }

        guard let winner = ranked.first else {
            emit("\nNo profile succeeded. Preserving default profile.")
            return StrategyProfiles.defaultProfile
        }

        emit("\n\u{001B}[32m✓ Selected:\u{001B}[0m \u{001B}[1m\(winner.profile.id)\u{001B}[0m (\(winner.profile.name))")
        emit("  Description: \(winner.profile.description)")
        emit("  Parameters:  \(winner.profile.args.joined(separator: " "))\n")

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
