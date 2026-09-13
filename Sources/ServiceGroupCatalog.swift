import Foundation

/// A predefined or custom group of domains targeted for DPI bypass.
public struct ServiceGroup: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let defaultEnabled: Bool
    public let domains: [String]
    public let domainSuffixes: [String]

    public init(
        id: String,
        name: String,
        description: String,
        defaultEnabled: Bool,
        domains: [String] = [],
        domainSuffixes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.defaultEnabled = defaultEnabled
        self.domains = ServiceGroupCatalog.normalize(domains)
        self.domainSuffixes = ServiceGroupCatalog.normalize(domainSuffixes)
    }
}

/// Catalog of offline, versioned built-in service groups for macOS.
public enum ServiceGroupCatalog {
    /// Normalizes domains by converting to lowercase, removing protocols/paths/ports, and trimming whitespace.
    public static func normalizeDomain(_ raw: String) -> String? {
        var domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !domain.isEmpty else { return nil }

        // Strip scheme if present
        if let schemeRange = domain.range(of: "://") {
            domain = String(domain[schemeRange.upperBound...])
        }

        // Strip path and query if present
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }
        if let queryIndex = domain.firstIndex(of: "?") {
            domain = String(domain[..<queryIndex])
        }

        // Strip port if present
        if let colonIndex = domain.firstIndex(of: ":") {
            domain = String(domain[..<colonIndex])
        }

        guard !domain.contains("..") else { return nil }

        // Strip leading wildcards (*. or . or *)
        var changed = true
        while changed {
            changed = false
            if domain.hasPrefix("*.") {
                domain = String(domain.dropFirst(2))
                changed = true
            } else if domain.hasPrefix(".") || domain.hasPrefix("*") {
                domain = String(domain.dropFirst(1))
                changed = true
            }
        }
        while domain.hasSuffix(".") {
            domain = String(domain.dropLast(1))
        }

        // Validate basic domain structure
        guard !domain.isEmpty,
              domain.contains("."),
              !domain.contains(".."),
              !domain.contains(" "),
              !domain.contains("*"),
              domain.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" })
        else {
            return nil
        }

        return domain
    }

    /// Normalizes and deduplicates a list of domains.
    public static func normalize(_ rawList: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for item in rawList {
            if let valid = normalizeDomain(item), !seen.contains(valid) {
                seen.insert(valid)
                result.append(valid)
            }
        }
        return result.sorted()
    }

    // MARK: - Built-in Service Groups

    /// 1. General blocked sites / trackers
    public static let general = ServiceGroup(
        id: "general",
        name: "General Blocked Services",
        description: "General web services and repositories affected by regional censorship",
        defaultEnabled: true,
        domainSuffixes: [
            "rutracker.org",
            "nyaa.si",
            "rutor.org",
            "nnmclub.to",
            "archive.org",
            "torproject.org",
            "dw.com"
        ]
    )

    /// 2. Social media platforms
    public static let social = ServiceGroup(
        id: "social",
        name: "Social Networks",
        description: "Social media and messaging web platforms (Discord, Instagram, Twitter/X, Facebook, etc.)",
        defaultEnabled: true,
        domainSuffixes: [
            "discord.com",
            "discord.gg",
            "discord.media",
            "discordapp.com",
            "discordapp.net",
            "discordcdn.com",
            "discord.dev",
            "discord.new",
            "discord.gift",
            "discordstatus.com",
            "dis.gd",
            "facebook.com",
            "fb.com",
            "fb.me",
            "fbcdn.net",
            "instagram.com",
            "cdninstagram.com",
            "messenger.com",
            "meta.com",
            "snapchat.com",
            "snap.com",
            "linkedin.com",
            "x.com",
            "twitter.com",
            "twimg.com",
            "soundcloud.com",
            "medium.com",
            "proton.me",
            "protonmail.com",
            "protonvpn.com"
        ]
    )

    /// 3. Türkiye specific ISP block list
    public static let turkiye = ServiceGroup(
        id: "turkiye",
        name: "Türkiye Regional Blocks",
        description: "Services and domains blocked by Turkish administrative and court orders (Roblox, Discord, Wattpad, etc.)",
        defaultEnabled: true,
        domainSuffixes: [
            // Gaming & Community
            "roblox.com",
            "rbxcdn.com",
            "rbx.com",
            "rblx.org",
            "robloxlabs.com",
            "discord.com",
            "discord.gg",
            "discord.media",
            "discordapp.com",
            "discordapp.net",
            "discordcdn.com",
            "discord.dev",
            "discord.new",
            "discord.gift",
            "discordstatus.com",
            "dis.gd",
            // Publishing & Paste
            "wattpad.com",
            "pastebin.com",
            // File sharing & Leaks
            "4shared.com",
            "wikileaks.org",
            // URL shorteners commonly restricted
            "bitly.com",
            "cutt.ly",
            "t2m.io"
        ]
    )

    /// 4. YouTube service-level endpoints
    public static let youtube = ServiceGroup(
        id: "youtube",
        name: "YouTube & Media",
        description: "YouTube video playback, thumbnails, and service infrastructure",
        defaultEnabled: true,
        domainSuffixes: [
            "youtube.com",
            "youtu.be",
            "ytimg.com",
            "ggpht.com",
            "googlevideo.com",
            "youtubei.googleapis.com"
        ]
    )

    /// 5. Telegram web and API endpoints
    public static let telegram = ServiceGroup(
        id: "telegram",
        name: "Telegram",
        description: "Telegram Web, official domains, and instant preview services",
        defaultEnabled: false,
        domainSuffixes: [
            "telegram.org",
            "telegram.me",
            "telegram.dog",
            "telegra.ph",
            "telesco.pe",
            "t.me"
        ]
    )

    /// 6. Cloudflare infrastructure & ECH
    public static let cloudflare = ServiceGroup(
        id: "cloudflare",
        name: "Cloudflare & ECH",
        description: "Cloudflare network edges and Encrypted ClientHello endpoints",
        defaultEnabled: true,
        domainSuffixes: [
            "cloudflare.com",
            "cloudflare.net",
            "cloudflarecn.net",
            "cloudflare-ech.com"
        ]
    )

    /// The curated 6 built-in groups bundled with Routun
    public static let builtInGroups: [ServiceGroup] = [
        general,
        social,
        turkiye,
        youtube,
        telegram,
        cloudflare
    ]

    public static func find(byId id: String) -> ServiceGroup? {
        let needle = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return builtInGroups.first { $0.id.lowercased() == needle }
    }
}
