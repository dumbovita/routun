import Foundation

public enum RoutingMode: String, Codable, CaseIterable {
    /// Only route selected service groups and custom included domains through ByeDPI (default)
    case selective
    /// Route all outbound public TCP web traffic (ports 80, 443) through ByeDPI
    case global
}

public enum QUICMode: String, Codable, CaseIterable {
    /// Reject UDP/443 only for bypassed domains, forcing graceful TCP fallback without breaking HTTP/3 elsewhere (default)
    case scoped
    /// Globally reject all outbound UDP/443 (legacy fallback behavior)
    case blocked
    /// Allow UDP/443 direct without interception
    case direct
}

public enum DNSMode: String, Codable, CaseIterable {
    /// Let system DNS handle name resolution (default)
    case disabled
    /// Route public DNS queries through sing-box DoH while keeping local/VPN domains direct
    case doh
}

/// Represents the active user policy for selective DPI bypass routing.
public struct RoutePolicy: Codable, Equatable {
    public var mode: RoutingMode
    public var quicMode: QUICMode
    public var dnsMode: DNSMode
    public var enableIPv6: Bool
    public var groupPreferences: [String: Bool]
    public var customInclude: [String]
    public var customExclude: [String]

    public init(
        mode: RoutingMode = .selective,
        quicMode: QUICMode = .scoped,
        dnsMode: DNSMode = .disabled,
        enableIPv6: Bool = true,
        groupPreferences: [String: Bool] = [:],
        customInclude: [String] = [],
        customExclude: [String] = []
    ) {
        self.mode = mode
        self.quicMode = quicMode
        self.dnsMode = dnsMode
        self.enableIPv6 = enableIPv6
        self.groupPreferences = groupPreferences
        self.customInclude = ServiceGroupCatalog.normalize(customInclude)
        self.customExclude = ServiceGroupCatalog.normalize(customExclude)
    }

    /// Check if a specific service group is enabled according to user preferences or defaults
    public func isGroupEnabled(_ group: ServiceGroup) -> Bool {
        if let userPref = groupPreferences[group.id] {
            return userPref
        }
        return group.defaultEnabled
    }

    /// Mutate group status
    public mutating func setGroupEnabled(_ groupId: String, enabled: Bool) {
        groupPreferences[groupId] = enabled
    }

    /// Resolve effective domain and suffix target lists according to precedence:
    /// 1. Exclusions (custom exclude)
    /// 2. Inclusions (custom include + enabled groups)
    public func resolveTargets(catalog: [ServiceGroup] = ServiceGroupCatalog.builtInGroups) -> (
        bypassedSuffixes: [String],
        excludedSuffixes: [String]
    ) {
        let excludedSet = Set(ServiceGroupCatalog.normalize(customExclude))
        var candidateBypassed = Set<String>()

        // Add custom inclusions
        for inc in ServiceGroupCatalog.normalize(customInclude) {
            if !excludedSet.contains(inc) {
                candidateBypassed.insert(inc)
            }
        }

        // Add enabled group suffixes
        for group in catalog where isGroupEnabled(group) {
            for suffix in group.domainSuffixes {
                if !excludedSet.contains(suffix) {
                    candidateBypassed.insert(suffix)
                }
            }
            for domain in group.domains {
                if !excludedSet.contains(domain) {
                    candidateBypassed.insert(domain)
                }
            }
        }

        return (
            bypassedSuffixes: candidateBypassed.sorted(),
            excludedSuffixes: excludedSet.sorted()
        )
    }
}
