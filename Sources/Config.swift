import Foundation
import Darwin

public struct RoutunConfig: Codable, Equatable {
    public var ciadpiPath: String
    public var singboxPath: String
    public var ciadpiArgs: [String]
    public var socksHost: String
    public var socksPort: Int
    public var singboxConfig: String
    public var selectedProfile: String?
    public var routingMode: RoutingMode
    public var quicMode: QUICMode
    public var dnsMode: DNSMode
    public var enableIPv6: Bool
    public var groupPreferences: [String: Bool]
    public var customInclude: [String]
    public var customExclude: [String]

    enum CodingKeys: String, CodingKey {
        case ciadpiPath = "ciadpi_path"
        case singboxPath = "singbox_path"
        case ciadpiArgs = "ciadpi_args"
        case socksHost = "socks_host"
        case socksPort = "socks_port"
        case singboxConfig = "singbox_config"
        case selectedProfile = "selected_profile"
        case routingMode = "routing_mode"
        case quicMode = "quic_mode"
        case dnsMode = "dns_mode"
        case enableIPv6 = "enable_ipv6"
        case groupPreferences = "group_preferences"
        case customInclude = "custom_include"
        case customExclude = "custom_exclude"
    }

    public init(
        ciadpiPath: String,
        singboxPath: String,
        ciadpiArgs: [String],
        socksHost: String = "127.0.0.1",
        socksPort: Int = 1080,
        singboxConfig: String = RoutunConfig.defaultSingboxConfigFile,
        selectedProfile: String? = "default",
        routingMode: RoutingMode = .selective,
        quicMode: QUICMode = .scoped,
        dnsMode: DNSMode = .disabled,
        enableIPv6: Bool = false,
        groupPreferences: [String: Bool] = [:],
        customInclude: [String] = [],
        customExclude: [String] = []
    ) {
        self.ciadpiPath = ciadpiPath
        self.singboxPath = singboxPath
        self.ciadpiArgs = ciadpiArgs
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.singboxConfig = singboxConfig
        self.selectedProfile = selectedProfile
        self.routingMode = routingMode
        self.quicMode = quicMode
        self.dnsMode = dnsMode
        self.enableIPv6 = enableIPv6
        self.groupPreferences = groupPreferences
        self.customInclude = ServiceGroupCatalog.normalize(customInclude)
        self.customExclude = ServiceGroupCatalog.normalize(customExclude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ciadpiPath = try container.decodeIfPresent(String.self, forKey: .ciadpiPath) ?? ""
        self.singboxPath = try container.decodeIfPresent(String.self, forKey: .singboxPath) ?? ""
        self.ciadpiArgs = try container.decodeIfPresent([String].self, forKey: .ciadpiArgs) ?? []
        self.socksHost = try container.decodeIfPresent(String.self, forKey: .socksHost) ?? "127.0.0.1"
        self.socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? 1080
        self.singboxConfig = try container.decodeIfPresent(String.self, forKey: .singboxConfig) ?? RoutunConfig.defaultSingboxConfigFile
        self.selectedProfile = try container.decodeIfPresent(String.self, forKey: .selectedProfile)
        self.routingMode = try container.decodeIfPresent(RoutingMode.self, forKey: .routingMode) ?? .selective
        self.quicMode = try container.decodeIfPresent(QUICMode.self, forKey: .quicMode) ?? .scoped
        self.dnsMode = try container.decodeIfPresent(DNSMode.self, forKey: .dnsMode) ?? .disabled
        self.enableIPv6 = try container.decodeIfPresent(Bool.self, forKey: .enableIPv6) ?? false
        self.groupPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .groupPreferences) ?? [:]
        let rawInclude = try container.decodeIfPresent([String].self, forKey: .customInclude) ?? []
        let rawExclude = try container.decodeIfPresent([String].self, forKey: .customExclude) ?? []
        self.customInclude = ServiceGroupCatalog.normalize(rawInclude)
        self.customExclude = ServiceGroupCatalog.normalize(rawExclude)
    }

    public var routePolicy: RoutePolicy {
        get {
            RoutePolicy(
                mode: routingMode,
                quicMode: quicMode,
                dnsMode: dnsMode,
                enableIPv6: enableIPv6,
                groupPreferences: groupPreferences,
                customInclude: customInclude,
                customExclude: customExclude
            )
        }
        set {
            routingMode = newValue.mode
            quicMode = newValue.quicMode
            dnsMode = newValue.dnsMode
            enableIPv6 = newValue.enableIPv6
            groupPreferences = newValue.groupPreferences
            customInclude = newValue.customInclude
            customExclude = newValue.customExclude
        }
    }

    public static let serviceLabel = "com.routun.routund"
    public static let appSupportDir = "/Library/Application Support/routun"
    public static let serviceBinDir = "/usr/local/libexec/routun"
    public static let serviceConfigDir = "\(appSupportDir)/config"
    public static let serviceStateDir = "\(appSupportDir)/state"
    public static let daemonBinaryPath = "\(serviceBinDir)/routund"
    public static let serviceCiadpiPath = "\(serviceBinDir)/ciadpi"
    public static let serviceSingboxPath = "\(serviceBinDir)/sing-box"
    public static let defaultConfigFile = "\(serviceConfigDir)/routun.json"
    public static let defaultSingboxConfigFile = "\(serviceConfigDir)/singbox.json"
    public static let stateFile = "\(serviceStateDir)/state.json"
    public static let launchDaemonPlist = "/Library/LaunchDaemons/\(serviceLabel).plist"

    // Previous standalone releases stored these directly in Application Support.
    // They are read only during an explicit root-authorized installation migration.
    public static let legacyConfigFile = "\(appSupportDir)/routun.json"
    public static let legacySingboxConfigFile = "\(appSupportDir)/singbox.json"

    public func save(to path: String = RoutunConfig.defaultConfigFile) throws {
        let parentDir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
        if path == RoutunConfig.defaultConfigFile, chmod(path, 0o644) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public static func load() -> RoutunConfig {
        load(from: defaultConfigFile) ?? defaultConfiguration()
    }

    public static func installationConfiguration() -> RoutunConfig {
        if let installed = load(from: defaultConfigFile) {
            return installed
        }
        for path in [legacyConfigFile] + templatePaths(named: "routun.json") {
            if let config = load(from: path) {
                return config
            }
        }
        return defaultConfiguration()
    }

    /// The root daemon never honors executable or config paths from configuration.
    public static func daemonConfiguration() -> RoutunConfig {
        var config = load()
        config.ciadpiPath = serviceCiadpiPath
        config.singboxPath = serviceSingboxPath
        config.singboxConfig = defaultSingboxConfigFile
        return config
    }

    public static func singboxTemplatePath(preferredPath: String) -> String? {
        let candidates = [preferredPath, legacySingboxConfigFile] + templatePaths(named: "singbox.json")
        return candidates.first(where: { FileManager.default.isReadableFile(atPath: $0) })
    }

    public static func dependencySource(named name: String, configuredPath: String) -> String? {
        let environmentKey = name == "ciadpi" ? "ROUTUN_CIADPI_SOURCE" : "ROUTUN_SINGBOX_SOURCE"
        if let source = ProcessInfo.processInfo.environment[environmentKey], isExecutableBinary(atPath: source) {
            return source
        }
        if configuredPath != serviceCiadpiPath,
           configuredPath != serviceSingboxPath,
           isExecutableBinary(atPath: configuredPath) {
            return configuredPath
        }
        return findBinary(named: name, searchPaths: ["/opt/homebrew/bin", "/usr/local/bin"])
    }

    public static func resolveBinary(named name: String, preferredPath: String = "") -> String? {
        if !preferredPath.isEmpty && isExecutableBinary(atPath: preferredPath) {
            return preferredPath
        }
        if let source = dependencySource(named: name, configuredPath: preferredPath) {
            return source
        }
        var searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", serviceBinDir, "/usr/bin", "/bin"]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchPaths.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }
        return findBinary(named: name, searchPaths: searchPaths)
    }

    public static func currentExecutablePath() -> String {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        if executable.hasPrefix("/") {
            return URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(executable)
            .resolvingSymlinksInPath()
            .path
    }

    public static func isExecutableBinary(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    public static func findBinary(named name: String, searchPaths: [String]) -> String? {
        for path in searchPaths {
            let candidate = path.hasSuffix("/\(name)") ? path : "\(path)/\(name)"
            if isExecutableBinary(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func defaultConfiguration() -> RoutunConfig {
        RoutunConfig(
            ciadpiPath: findBinary(named: "ciadpi", searchPaths: ["/opt/homebrew/bin", "/usr/local/bin"]) ?? "",
            singboxPath: findBinary(named: "sing-box", searchPaths: ["/opt/homebrew/bin", "/usr/local/bin"]) ?? "",
            ciadpiArgs: ["-i", "127.0.0.1", "-p", "1080", "-A", "torst,ssl_err", "-s", "1", "-d", "3+s", "-r", "1+s", "-c", "512"],
            socksHost: "127.0.0.1",
            socksPort: 1080,
            singboxConfig: defaultSingboxConfigFile,
            selectedProfile: "default",
            routingMode: .selective,
            quicMode: .scoped,
            dnsMode: .disabled,
            enableIPv6: false,
            groupPreferences: [:],
            customInclude: [],
            customExclude: []
        )
    }

    public static func load(from path: String) -> RoutunConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(RoutunConfig.self, from: data)
    }

    private static func templatePaths(named name: String) -> [String] {
        let executable = URL(fileURLWithPath: currentExecutablePath()).resolvingSymlinksInPath()
        let executableDirectory = executable.deletingLastPathComponent()
        let prefix = executable.deletingLastPathComponent().deletingLastPathComponent()
        return [
            executableDirectory.appendingPathComponent("config/\(name)").path,
            prefix.appendingPathComponent("share/routun/\(name)").path,
            "/opt/homebrew/etc/routun/\(name)",
            "/usr/local/etc/routun/\(name)"
        ]
    }
}
