import Foundation

/// Darwin-specific capability model for ByeDPI (ciadpi).
///
/// Upstream ByeDPI compiles fake TCP packet generation (`FAKE_SUPPORT`) and
/// TCP timeout support (`TIMEOUT_SUPPORT`) exclusively for Linux and Windows:
/// `#if defined(__linux__) || defined(_WIN32)`.
///
/// On macOS (Darwin):
/// - `-s` (split), `-d` (disorder), `-o` (OOB), `-q` (DISOOB), `-r` (TLS record split),
///   `-A` (auto fallback), `-M` (HTTP mod), `-m` (TLS minor), `-K` (proto), `-b`, `-c`
///   are fully compiled, supported, and functional.
/// - `-t` (TTL) and `-Q` (fake TLS ClientHello mod) are accepted by the CLI option parser,
///   but the underlying TCP fake-generation code is compiled out. They are therefore inert
///   in TCP interception on Darwin.
/// - `-f` (fake TCP packet) and `-S` (TCP MD5 signature) are not compiled on Darwin.
public struct ByeDPICapability: Codable, Equatable {
    public let supportsSplit: Bool
    public let supportsDisorder: Bool
    public let supportsOOB: Bool
    public let supportsDisoob: Bool
    public let supportsTLSRecord: Bool
    public let supportsModHTTP: Bool
    public let supportsTLSMinor: Bool
    public let supportsAutoFallback: Bool
    public let supportsHostsFilter: Bool
    public let supportsIPSetFilter: Bool
    public let supportsPortFilter: Bool
    public let supportsFakePackets: Bool
    public let supportsFakeTTL: Bool
    public let supportsFakeTLSMod: Bool
    public let supportsTCPTimeout: Bool
    public let supportsTCPMD5: Bool
    public let supportsUDPFake: Bool

    /// Standard capabilities for the pinned Darwin / macOS build of ByeDPI
    public static let darwinStandard = ByeDPICapability(
        supportsSplit: true,
        supportsDisorder: true,
        supportsOOB: true,
        supportsDisoob: true,
        supportsTLSRecord: true,
        supportsModHTTP: true,
        supportsTLSMinor: true,
        supportsAutoFallback: true,
        supportsHostsFilter: true,
        supportsIPSetFilter: true,
        supportsPortFilter: true,
        supportsFakePackets: false,   // Compiled out on Darwin
        supportsFakeTTL: false,       // Inert for TCP on Darwin
        supportsFakeTLSMod: false,    // Inert for TCP on Darwin
        supportsTCPTimeout: false,    // Compiled out on Darwin
        supportsTCPMD5: false,        // Linux only
        supportsUDPFake: true
    )

    /// Inspect a ciadpi binary at the specified path and return detected capabilities
    public static func detect(ciadpiPath: String) -> ByeDPICapability {
        guard FileManager.default.isExecutableFile(atPath: ciadpiPath) else {
            return darwinStandard
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ciadpiPath)
        proc.arguments = ["-h"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let helpText = String(data: data, encoding: .utf8) ?? ""

            #if os(macOS)
            // On Darwin, FAKE_SUPPORT and TIMEOUT_SUPPORT are omitted in upstream params.h
            let hasFake = false
            let hasFakeTTL = false
            let hasFakeTLSMod = false
            let hasTimeout = false
            let hasTCPMD5 = false
            #else
            let hasFake = helpText.contains("--fake")
            let hasFakeTTL = helpText.contains("-t, --ttl")
            let hasFakeTLSMod = helpText.contains("-Q, --fake-tls-mod")
            let hasTimeout = helpText.contains("-T, --timeout")
            let hasTCPMD5 = helpText.contains("-S, --md5sig")
            #endif

            return ByeDPICapability(
                supportsSplit: helpText.contains("-s, --split"),
                supportsDisorder: helpText.contains("-d, --disorder"),
                supportsOOB: helpText.contains("-o, --oob"),
                supportsDisoob: helpText.contains("-q, --disoob"),
                supportsTLSRecord: helpText.contains("-r, --tlsrec"),
                supportsModHTTP: helpText.contains("-M, --mod-http"),
                supportsTLSMinor: helpText.contains("-m, --tlsminor"),
                supportsAutoFallback: helpText.contains("-A, --auto"),
                supportsHostsFilter: helpText.contains("-H, --hosts"),
                supportsIPSetFilter: helpText.contains("-j, --ipset"),
                supportsPortFilter: helpText.contains("-V, --pf"),
                supportsFakePackets: hasFake,
                supportsFakeTTL: hasFakeTTL,
                supportsFakeTLSMod: hasFakeTLSMod,
                supportsTCPTimeout: hasTimeout,
                supportsTCPMD5: hasTCPMD5,
                supportsUDPFake: helpText.contains("-a, --udp-fake")
            )
        } catch {
            return darwinStandard
        }
    }

    /// Check if a strategy profile contains arguments unsupported or inert on this platform
    public func validate(args: [String]) -> (isValid: Bool, reasons: [String]) {
        var reasons = [String]()
        var i = 0

        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-f", "--fake":
                if !supportsFakePackets {
                    reasons.append("Fake TCP packet generation (-f) is not supported on macOS ByeDPI.")
                }
            case "-t", "--ttl":
                if !supportsFakeTTL {
                    reasons.append("Fake packet TTL (-t) is inert on macOS ByeDPI because fake packets are disabled.")
                }
            case "-Q", "--fake-tls-mod":
                if !supportsFakeTLSMod {
                    reasons.append("Fake TLS ClientHello modification (-Q) is inert on macOS ByeDPI.")
                }
            case "-S", "--md5sig":
                if !supportsTCPMD5 {
                    reasons.append("TCP MD5 signature (-S) is supported on Linux only.")
                }
            case "-T", "--timeout":
                if !supportsTCPTimeout {
                    reasons.append("TCP connection timeout (-T) is not supported on macOS ByeDPI.")
                }
            default:
                break
            }
            i += 1
        }

        return (reasons.isEmpty, reasons)
    }

    /// Sanitize arguments by removing inert or unsupported flags for macOS
    public func sanitize(args: [String]) -> [String] {
        var sanitized = [String]()
        var skipNext = false

        for (index, token) in args.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }

            switch token {
            case "-t", "--ttl", "-Q", "--fake-tls-mod":
                // Both take 1 argument: -t <ttl>, -Q <rand|orig|msize=N>
                if !supportsFakeTTL || !supportsFakeTLSMod {
                    if index + 1 < args.count && !args[index + 1].hasPrefix("-") {
                        skipNext = true
                    }
                    continue
                }
            case "-f", "--fake":
                if !supportsFakePackets {
                    if index + 1 < args.count && !args[index + 1].hasPrefix("-") {
                        skipNext = true
                    }
                    continue
                }
            case "-S", "--md5sig":
                if !supportsTCPMD5 {
                    continue
                }
            case "-T", "--timeout":
                if !supportsTCPTimeout {
                    if index + 1 < args.count && !args[index + 1].hasPrefix("-") {
                        skipNext = true
                    }
                    continue
                }
            default:
                break
            }

            sanitized.append(token)
        }

        return sanitized
    }
}
