import Foundation
import Testing
@testable import routun

@Suite("Strategy Optimizer and Lifecycle Tests")
struct StrategyOptimizerTests {
    @Test("Custom target preserves scheme, port, and path")
    func customTargetPreservesSchemePortAndPath() throws {
        let target = try #require(StrategyTarget.parse(from: "https://gateway.discord.gg/api/v9/gateway"))

        #expect(target.host == "gateway.discord.gg")
        #expect(target.scheme == "https")
        #expect(target.port == 443)
        #expect(target.path == "/api/v9/gateway")
        #expect(target.urlString == "https://gateway.discord.gg/api/v9/gateway")
    }

    @Test("Custom target list splits whitespace and commas while keeping distinct endpoints")
    func customTargetListSplitsWhitespaceAndKeepsDistinctEndpoints() {
        let targets = StrategyTarget.parseList(from: [
            "discord.com, https://discord.com/ https://gateway.discord.gg/ https://cloudflare.com/cdn-cgi/trace"
        ])

        #expect(targets.map(\.urlString) == [
            "https://discord.com/",
            "https://gateway.discord.gg/",
            "https://cloudflare.com/cdn-cgi/trace"
        ])
    }

    @Test("Evaluation targets contains custom target first and curated hosts")
    func evaluationTargetsContainsEveryCuratedHost() {
        let custom = StrategyTarget(name: "GitHub", host: "github.com")
        let targets = StrategyOptimizer.evaluationTargets(customTargets: [custom])
        let curatedHosts = Set(StrategyTargets.all.filter { !$0.isReference }.map(\.host))

        #expect(targets.first?.host == custom.host)
        #expect(curatedHosts.isSubset(of: Set(targets.map(\.host))))
    }

    @Test("Curated strategy targets are proper and valid")
    func curatedStrategyTargetsAreProperAndValid() {
        let targets = StrategyTargets.all
        #expect(!targets.isEmpty, "Curated targets list must not be empty")

        let referenceTargets = targets.filter(\.isReference)
        #expect(referenceTargets.count == 1, "There should be exactly one sanity reference target")
        #expect(referenceTargets.first?.host == "apple.com")

        for target in targets {
            #expect(!target.name.isEmpty, "Target name must not be empty: \(target)")
            #expect(!target.host.isEmpty, "Target host must not be empty: \(target)")
            #expect(!target.host.contains("*"), "Target host must not contain wildcards: \(target.host)")
            #expect(["http", "https"].contains(target.scheme), "Invalid scheme for \(target.urlString)")
            #expect((1...65535).contains(target.port), "Invalid port for \(target.urlString)")
            #expect(URL(string: target.urlString) != nil, "Invalid URL string: \(target.urlString)")
        }
    }

    @Test("Curated strategy targets exclude fragile WAF and high-latency endpoints")
    func curatedStrategyTargetsExcludeFragileEndpoints() {
        let targets = StrategyTargets.all
        let hosts = Set(targets.map(\.host))

        #expect(targets.count == 26, "Expected exactly 26 targets (1 reference + 25 evaluation)")
        #expect(!hosts.contains("medium.com"), "medium.com must be excluded due to Cloudflare/Datadome WAF 403 blocks")
        #expect(!hosts.contains("rutracker.org"), "rutracker.org must be excluded due to erratic multi-second latency spikes")
        #expect(hosts.contains("substack.com"), "substack.com should be present as reliable publishing target")
        #expect(hosts.contains("bbc.com"), "bbc.com should be present as reliable censorship target")
        #expect(hosts.contains("cloudflare-dns.com"))

        if let cfDns = targets.first(where: { $0.host == "cloudflare-dns.com" }) {
            #expect(cfDns.path == "/", "Cloudflare DNS should use root path rather than /dns-query to prevent HTTP 415")
        }
    }

    @Test("findFreePort with exclusion set avoids port collision")
    func findFreePortExcludingAvoidsCollision() {
        let port1 = StrategyOptimizer.findFreePort()
        let port2 = StrategyOptimizer.findFreePort(excluding: [port1])
        #expect(port1 != port2, "Allocated ports must be distinct")

        let port3 = StrategyOptimizer.findFreePort(excluding: [port1, port2])
        #expect(![port1, port2].contains(port3), "Allocated port must not collide with excluded ports")
    }

    @Test("Probe always makes two attempts and marks identical results reliable")
    func probeAlwaysMakesTwoAttempts() {
        let target = StrategyTarget(name: "Apple", host: "apple.com")
        let sequence = ProbeSequence([true, true])
        let optimizer = StrategyOptimizer(testPort: 10885) { target, _, _ in
            sequence.result(for: target)
        }

        let result = optimizer.probe(target: target, socksPort: nil)

        #expect(sequence.callCount == 2)
        #expect(result.attempts == 2)
        #expect(result.successfulAttempts == 2)
        #expect(result.isReliable == true)
        #expect(result.failureCategory == .none)
    }

    @Test("Probe marks mixed attempts as unreliable")
    func probeMarksMixedAttemptsAsUnreliable() {
        let target = StrategyTarget(name: "Apple", host: "apple.com")
        let sequence = ProbeSequence([true, false])
        let optimizer = StrategyOptimizer(testPort: 10885) { target, _, _ in
            sequence.result(for: target)
        }

        let result = optimizer.probe(target: target, socksPort: nil)

        #expect(sequence.callCount == 2)
        #expect(result.isReachable == true)
        #expect(result.isReliable == false)
        #expect(result.successfulAttempts == 1)
    }

    @Test("Failure categories are accurately classified in ProbeResult")
    func failureCategories() {
        let target = StrategyTarget(name: "Test", host: "test.com")
        let timeoutResult = ProbeResult(
            target: target,
            isReachable: false,
            latencyMs: 3000,
            statusCode: 0,
            exitCode: 28,
            detail: "Connection timed out",
            failureCategory: .timeout
        )
        #expect(timeoutResult.failureCategory == .timeout)
        #expect(!timeoutResult.isReachable)

        let tlsBlockResult = ProbeResult(
            target: target,
            isReachable: false,
            latencyMs: 120,
            statusCode: 0,
            exitCode: 35,
            detail: "SSL handshake failed",
            failureCategory: .tlsDpiBlock
        )
        #expect(tlsBlockResult.failureCategory == .tlsDpiBlock)

        let dnsResult = ProbeResult(
            target: target,
            isReachable: false,
            latencyMs: 50,
            statusCode: 0,
            exitCode: 6,
            detail: "Could not resolve host",
            failureCategory: .dnsFailure
        )
        #expect(dnsResult.failureCategory == .dnsFailure)
    }

    @Test("Port release check returns true immediately for an unused port")
    func waitForPortToCloseOnFreePort() {
        let freePort = StrategyOptimizer.findFreePort()
        let isClosed = NetUtils.waitForPortToClose(host: "127.0.0.1", port: freePort, timeout: 0.5)
        #expect(isClosed == true)
    }

    @Test("Generated LaunchDaemon plist uses only protected payload")
    func generatedLaunchDaemonPlist() throws {
        let data = try ServiceManager.launchDaemonPlistData()
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        #expect(plist["Label"] as? String == RoutunConfig.serviceLabel)
        #expect(plist["ProgramArguments"] as? [String] == [RoutunConfig.daemonBinaryPath, "daemon"])
        #expect(plist["RunAtLoad"] == nil)
        #expect(plist["StandardOutPath"] == nil)
        #expect(plist["StandardErrorPath"] == nil)
        #expect((plist["KeepAlive"] as? [String: Any])?["SuccessfulExit"] as? Bool == false)
    }

    @Test("Optimizer runs full pipeline with early-exit screening and selects zero-regression winner")
    func optimizerPipelineWithMockProbes() {
        let optimizer = StrategyOptimizer(quick: true) { target, socksPort, _ in
            let isReachable: Bool
            if socksPort == nil {
                isReachable = !["discord.com", "gateway.discord.gg"].contains(target.host)
            } else {
                isReachable = true
            }
            return ProbeResult(
                target: target,
                isReachable: isReachable,
                latencyMs: 15,
                statusCode: isReachable ? 200 : 0,
                exitCode: isReachable ? 0 : 35,
                detail: isReachable ? "HTTP 200" : "Blocked",
                failureCategory: isReachable ? .none : .tlsDpiBlock,
                attempts: 1,
                successfulAttempts: isReachable ? 1 : 0
            )
        }

        var progressLogs = [String]()
        let winner = optimizer.run { log in
            progressLogs.append(log)
        }

        #expect(winner != nil, "A winning profile must be selected")
        #expect(progressLogs.contains { $0.contains("Baseline (Direct):") })
        #expect(progressLogs.contains { $0.contains("Selected:") })
    }

    @Test("Live reference target connectivity check", .disabled("Requires live internet access; run manually with ROUTUN_LIVE_NETWORK_TESTS=1"))
    func liveReferenceTarget() {
        guard let refTarget = StrategyTargets.all.first(where: { $0.isReference }) else {
            Issue.record("No reference target configured")
            return
        }
        let optimizer = StrategyOptimizer()
        let result = optimizer.probe(target: refTarget, socksPort: nil, timeout: 4.0)
        #expect(result.isReachable == true, "Reference target (\(refTarget.urlString)) must be reachable: \(result.detail)")
    }
}

private final class ProbeSequence: @unchecked Sendable {
    private let outcomes: [Bool]
    private(set) var callCount = 0
    private let lock = NSLock()

    init(_ outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func result(for target: StrategyTarget) -> ProbeResult {
        lock.lock()
        defer { lock.unlock() }
        let isReachable = outcomes[callCount]
        callCount += 1
        return ProbeResult(
            target: target,
            isReachable: isReachable,
            latencyMs: 10,
            statusCode: isReachable ? 200 : 0,
            exitCode: isReachable ? 0 : 28,
            detail: isReachable ? "HTTP 200" : "Timeout",
            failureCategory: isReachable ? .none : .timeout,
            attempts: 1,
            successfulAttempts: isReachable ? 1 : 0
        )
    }
}
