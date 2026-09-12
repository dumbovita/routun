#if canImport(XCTest)
import XCTest
@testable import routun

final class StrategyOptimizerTests: XCTestCase {
    func testCustomTargetPreservesSchemePortAndPath() throws {
        let target = try XCTUnwrap(StrategyTarget.parse(from: "https://gateway.discord.gg/api/v9/gateway"))

        XCTAssertEqual(target.host, "gateway.discord.gg")
        XCTAssertEqual(target.scheme, "https")
        XCTAssertEqual(target.port, 443)
        XCTAssertEqual(target.path, "/api/v9/gateway")
        XCTAssertEqual(target.urlString, "https://gateway.discord.gg/api/v9/gateway")
    }

    func testCustomTargetListSplitsWhitespaceAndKeepsDistinctEndpoints() {
        let targets = StrategyTarget.parseList(from: [
            "discord.com, https://discord.com/ https://gateway.discord.gg/ https://cloudflare.com/cdn-cgi/trace"
        ])

        XCTAssertEqual(targets.map(\.urlString), [
            "https://discord.com/",
            "https://gateway.discord.gg/",
            "https://cloudflare.com/cdn-cgi/trace"
        ])
    }

    func testEvaluationTargetsContainsEveryCuratedHost() {
        let custom = StrategyTarget(name: "GitHub", host: "github.com")
        let targets = StrategyOptimizer.evaluationTargets(customTargets: [custom])
        let curatedHosts = Set(StrategyTargets.all.filter { !$0.isReference }.map(\.host))

        XCTAssertEqual(targets.first?.host, custom.host)
        XCTAssertTrue(curatedHosts.isSubset(of: Set(targets.map(\.host))))
    }

    func testCuratedStrategyTargetsAreProperAndValid() {
        let targets = StrategyTargets.all
        XCTAssertFalse(targets.isEmpty, "Curated targets list must not be empty")

        let referenceTargets = targets.filter(\.isReference)
        XCTAssertEqual(referenceTargets.count, 1, "There should be exactly one sanity reference target")
        XCTAssertEqual(referenceTargets.first?.host, "apple.com")

        for target in targets {
            XCTAssertFalse(target.name.isEmpty, "Target name must not be empty: \(target)")
            XCTAssertFalse(target.host.isEmpty, "Target host must not be empty: \(target)")
            XCTAssertFalse(target.host.contains("*"), "Target host must not contain wildcards: \(target.host)")
            XCTAssertTrue(["http", "https"].contains(target.scheme), "Invalid scheme for \(target.urlString)")
            XCTAssertTrue((1...65535).contains(target.port), "Invalid port for \(target.urlString)")
            XCTAssertNotNil(URL(string: target.urlString), "Invalid URL string: \(target.urlString)")
        }
    }

    func testProbeAlwaysMakesTwoAttempts() {
        let target = StrategyTarget(name: "Apple", host: "apple.com")
        let sequence = ProbeSequence([true, true])
        let optimizer = StrategyOptimizer(testPort: 10885) { target, _, _ in
            sequence.result(for: target)
        }

        let result = optimizer.probe(target: target, socksPort: nil)

        XCTAssertEqual(sequence.callCount, 2)
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.successfulAttempts, 2)
        XCTAssertTrue(result.isReliable)
    }

    func testProbeMarksMixedAttemptsAsUnreliable() {
        let target = StrategyTarget(name: "Apple", host: "apple.com")
        let sequence = ProbeSequence([true, false])
        let optimizer = StrategyOptimizer(testPort: 10885) { target, _, _ in
            sequence.result(for: target)
        }

        let result = optimizer.probe(target: target, socksPort: nil)

        XCTAssertEqual(sequence.callCount, 2)
        XCTAssertTrue(result.isReachable)
        XCTAssertFalse(result.isReliable)
        XCTAssertEqual(result.successfulAttempts, 1)
    }

    func testLiveReferenceTargetIsReachable() {
        guard let refTarget = StrategyTargets.all.first(where: { $0.isReference }) else {
            XCTFail("No reference target configured")
            return
        }
        let optimizer = StrategyOptimizer()
        let result = optimizer.probe(target: refTarget, socksPort: nil, timeout: 4.0)
        XCTAssertTrue(result.isReachable, "Reference target (\(refTarget.urlString)) must be reachable on direct network: \(result.detail)")
    }
}

private final class ProbeSequence {
    private let outcomes: [Bool]
    private(set) var callCount = 0

    init(_ outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func result(for target: StrategyTarget) -> ProbeResult {
        let isReachable = outcomes[callCount]
        callCount += 1
        return ProbeResult(
            target: target,
            isReachable: isReachable,
            latencyMs: 10,
            statusCode: isReachable ? 200 : 0,
            exitCode: isReachable ? 0 : 28,
            detail: isReachable ? "HTTP 200" : "Timeout",
            attempts: 1,
            successfulAttempts: isReachable ? 1 : 0
        )
    }
}
#endif
