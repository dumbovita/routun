import Foundation
import Testing
@testable import routun

@Suite("ByeDPI Capabilities Tests")
struct ByeDPICapabilitiesTests {
    @Test("Darwin standard capability profile reflects macOS compiler flags")
    func darwinStandardCapabilities() {
        let cap = ByeDPICapability.darwinStandard

        // Supported techniques on macOS
        #expect(cap.supportsSplit == true)
        #expect(cap.supportsDisorder == true)
        #expect(cap.supportsOOB == true)
        #expect(cap.supportsDisoob == true)
        #expect(cap.supportsTLSRecord == true)
        #expect(cap.supportsModHTTP == true)
        #expect(cap.supportsTLSMinor == true)
        #expect(cap.supportsAutoFallback == true)
        #expect(cap.supportsHostsFilter == true)
        #expect(cap.supportsIPSetFilter == true)
        #expect(cap.supportsPortFilter == true)
        #expect(cap.supportsUDPFake == true)

        // Features compiled out or inert on Darwin
        #expect(cap.supportsFakePackets == false)
        #expect(cap.supportsFakeTTL == false)
        #expect(cap.supportsFakeTLSMod == false)
        #expect(cap.supportsTCPTimeout == false)
        #expect(cap.supportsTCPMD5 == false)
    }

    @Test("Validate flags identifies inert and unsupported macOS options")
    func validateArguments() {
        let cap = ByeDPICapability.darwinStandard

        // Valid macOS strategy
        let validArgs = ["-s", "1", "-d", "3+s", "-r", "1+s", "-q", "1", "-o", "1", "-A", "torst,ssl_err"]
        let (validResult, validReasons) = cap.validate(args: validArgs)
        #expect(validResult == true)
        #expect(validReasons.isEmpty)

        // Inert fake TTL
        let (ttlResult, ttlReasons) = cap.validate(args: ["-s", "1", "-t", "3"])
        #expect(ttlResult == false)
        #expect(ttlReasons.count == 1)
        #expect(ttlReasons[0].contains("TTL (-t)"))

        // Long form TTL
        let (longTtlResult, longTtlReasons) = cap.validate(args: ["--ttl", "4"])
        #expect(longTtlResult == false)
        #expect(longTtlReasons.count == 1)

        // Inert fake TLS mod
        let (fakeTLSResult, fakeTLSReasons) = cap.validate(args: ["-Q", "rand", "-s", "1"])
        #expect(fakeTLSResult == false)
        #expect(fakeTLSReasons.count == 1)
        #expect(fakeTLSReasons[0].contains("ClientHello") || fakeTLSReasons[0].contains("-Q"))

        // Unsupported fake packets (-f)
        let (fakeResult, fakeReasons) = cap.validate(args: ["-f", "-1"])
        #expect(fakeResult == false)
        #expect(fakeReasons.count == 1)
        #expect(fakeReasons[0].contains("Fake TCP packet"))

        // Unsupported MD5 signature (-S)
        let (md5Result, md5Reasons) = cap.validate(args: ["-S"])
        #expect(md5Result == false)
        #expect(md5Reasons.count == 1)
        #expect(md5Reasons[0].contains("MD5"))

        // Unsupported timeout (-T)
        let (timeoutResult, timeoutReasons) = cap.validate(args: ["-T", "5"])
        #expect(timeoutResult == false)
        #expect(timeoutReasons.count == 1)
        #expect(timeoutReasons[0].contains("timeout"))

        // Multiple invalid flags
        let (multiResult, multiReasons) = cap.validate(args: ["-t", "3", "-Q", "orig", "-f", "1", "-T", "10"])
        #expect(multiResult == false)
        #expect(multiReasons.count == 4)
    }

    @Test("Sanitize arguments removes inert and unsupported tokens along with their values")
    func sanitizeArguments() {
        let cap = ByeDPICapability.darwinStandard

        // Stripping -t and its value
        let sanitizedTTL = cap.sanitize(args: ["-s", "1", "-t", "3", "-d", "3+s"])
        #expect(sanitizedTTL == ["-s", "1", "-d", "3+s"])

        // Stripping --ttl and its value
        let sanitizedLongTTL = cap.sanitize(args: ["--ttl", "5", "-r", "1+s"])
        #expect(sanitizedLongTTL == ["-r", "1+s"])

        // Stripping -Q and its parameter
        let sanitizedFakeTLS = cap.sanitize(args: ["-s", "1", "-Q", "msize=20", "-d", "1"])
        #expect(sanitizedFakeTLS == ["-s", "1", "-d", "1"])

        // Stripping -f and its value
        let sanitizedFake = cap.sanitize(args: ["-f", "1", "-o", "1"])
        #expect(sanitizedFake == ["-o", "1"])

        // Stripping -S (no param)
        let sanitizedMD5 = cap.sanitize(args: ["-S", "-s", "1"])
        #expect(sanitizedMD5 == ["-s", "1"])

        // Stripping -T and its value
        let sanitizedTimeout = cap.sanitize(args: ["-T", "10", "-s", "1"])
        #expect(sanitizedTimeout == ["-s", "1"])

        // Complex combined case
        let mixed = ["-i", "127.0.0.1", "-p", "1080", "-t", "3", "-s", "1", "-Q", "rand", "-d", "3+s", "-r", "1+s", "-c", "512"]
        let sanitizedMixed = cap.sanitize(args: mixed)
        #expect(sanitizedMixed == ["-i", "127.0.0.1", "-p", "1080", "-s", "1", "-d", "3+s", "-r", "1+s", "-c", "512"])

        // Already clean arguments remain unchanged
        let clean = ["-s", "1", "-d", "3+s", "-r", "1+s"]
        #expect(cap.sanitize(args: clean) == clean)
    }

    @Test("Detect returns fallback darwinStandard when executable is missing")
    func detectNonexistentBinary() {
        let cap = ByeDPICapability.detect(ciadpiPath: "/nonexistent/path/to/ciadpi")
        #expect(cap == ByeDPICapability.darwinStandard)
    }

    @Test("Detect with real binary on Darwin confirms fake support is disabled")
    func detectRealBinaryOnDarwin() {
        guard let ciadpiPath = RoutunConfig.resolveBinary(named: "ciadpi") else {
            Issue.record("ciadpi binary is required for capability detection tests but was not found.")
            return
        }

        let cap = ByeDPICapability.detect(ciadpiPath: ciadpiPath)
        #expect(cap.supportsSplit == true)
        #expect(cap.supportsDisorder == true)
        #expect(cap.supportsFakePackets == false)
        #expect(cap.supportsFakeTTL == false)
        #expect(cap.supportsFakeTLSMod == false)
        #expect(cap.supportsTCPTimeout == false)
    }
}
