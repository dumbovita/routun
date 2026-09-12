import Foundation

public struct RoutunConfig: Codable {
    public var ciadpiPath: String
    public var singboxPath: String
    public var ciadpiArgs: [String]
    public var socksHost: String
    public var socksPort: Int
    public var tunInterface: String
    public var singboxConfig: String
    public var selectedProfile: String?

    enum CodingKeys: String, CodingKey {
        case ciadpiPath = "ciadpi_path"
        case singboxPath = "singbox_path"
        case ciadpiArgs = "ciadpi_args"
        case socksHost = "socks_host"
        case socksPort = "socks_port"
        case tunInterface = "tun_interface"
        case singboxConfig = "singbox_config"
        case selectedProfile = "selected_profile"
    }

    public func save(to path: String? = nil) throws {
        let targetPath = path ?? RoutunConfig.defaultConfigFile
        let parentDir = (targetPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: targetPath), options: .atomic)
    }

    // Dynamic prefix detection (Homebrew Apple Silicon, Homebrew Intel, or Standalone)
    public static var homebrewPrefix: String? {
        if let env = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !env.isEmpty {
            return env
        }
        let exec = Bundle.main.executablePath ?? CommandLine.arguments[0]
        if exec.contains("/Cellar/routun/") {
            let parts = exec.components(separatedBy: "/Cellar/routun/")
            if let p = parts.first, !p.isEmpty { return p }
        }
        if exec.hasPrefix("/opt/homebrew/") { return "/opt/homebrew" }
        if exec.hasPrefix("/usr/local/") { return "/usr/local" }

        let fm = FileManager.default
        if fm.isExecutableFile(atPath: "/opt/homebrew/bin/brew") { return "/opt/homebrew" }
        if fm.isExecutableFile(atPath: "/usr/local/bin/brew") { return "/usr/local" }
        return nil
    }

    public static let appSupportDir = "/Library/Application Support/routun"
    public static let installedBinaryPath = "/usr/local/bin/routun"

    // Config Directory: Homebrew etc/routun or /Library/Application Support/routun
    public static var configDir: String {
        let fm = FileManager.default
        if let prefix = homebrewPrefix {
            let brewEtc = "\(prefix)/etc/routun"
            if fm.fileExists(atPath: brewEtc) { return brewEtc }
        }
        let appSupport = "/Library/Application Support/routun"
        if fm.fileExists(atPath: appSupport) { return appSupport }
        if let prefix = homebrewPrefix {
            return "\(prefix)/etc/routun"
        }
        return appSupport
    }

    public static var defaultConfigFile: String {
        "\(configDir)/routun.json"
    }

    public static var defaultSingboxConfigFile: String {
        let fm = FileManager.default
        let inConfigDir = "\(configDir)/singbox.json"
        if fm.fileExists(atPath: inConfigDir) { return inConfigDir }
        if let prefix = homebrewPrefix {
            let inBrewEtc = "\(prefix)/etc/routun/singbox.json"
            if fm.fileExists(atPath: inBrewEtc) { return inBrewEtc }
        }
        if fm.fileExists(atPath: "/Library/Application Support/routun/singbox.json") {
            return "/Library/Application Support/routun/singbox.json"
        }
        if fm.fileExists(atPath: "config/singbox.json") {
            return "config/singbox.json"
        }
        return inConfigDir
    }

    // Service identification (detects Homebrew service or standalone)
    public static var isHomebrewService: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/sh.brew.routun.plist")
            || FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/homebrew.mxcl.routun.plist")
    }

    public static let candidatePlistPaths = [
        "/Library/LaunchDaemons/sh.brew.routun.plist",
        "/Library/LaunchDaemons/homebrew.mxcl.routun.plist",
        "/Library/LaunchDaemons/com.routun.routund.plist",
        "/Library/LaunchDaemons/com.routun.daemon.plist"
    ]

    public static var installedPlistPath: String? {
        let fm = FileManager.default
        for path in candidatePlistPaths {
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }

    public static var serviceLabel: String {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Library/LaunchDaemons/sh.brew.routun.plist") {
            return "sh.brew.routun"
        }
        if fm.fileExists(atPath: "/Library/LaunchDaemons/homebrew.mxcl.routun.plist") {
            return "homebrew.mxcl.routun"
        }
        if let plist = installedPlistPath {
            if plist.contains("sh.brew") { return "sh.brew.routun" }
            if plist.contains("homebrew") { return "homebrew.mxcl.routun" }
            if plist.contains("daemon") { return "com.routun.daemon" }
        }
        return "com.routun.routund"
    }

    public static var executableBinaryPath: String {
        if let prefix = homebrewPrefix {
            let brewOpt = "\(prefix)/opt/routun/bin/routun"
            if FileManager.default.fileExists(atPath: brewOpt) { return brewOpt }
            let brewBin = "\(prefix)/bin/routun"
            if FileManager.default.fileExists(atPath: brewBin) { return brewBin }
        }
        if FileManager.default.fileExists(atPath: installedBinaryPath) {
            return installedBinaryPath
        }
        return Bundle.main.executablePath ?? "/usr/local/bin/routun"
    }

    public static var launchDaemonPlist: String {
        if let installed = installedPlistPath {
            return installed
        }
        if isHomebrewService || (homebrewPrefix != nil && FileManager.default.fileExists(atPath: "\(homebrewPrefix!)/opt/routun")) {
            return "/Library/LaunchDaemons/sh.brew.routun.plist"
        }
        return "/Library/LaunchDaemons/com.routun.routund.plist"
    }

    // Log directory: Homebrew var/log/routun or /var/log/routun
    public static var logDir: String {
        let fm = FileManager.default
        if let prefix = homebrewPrefix {
            let brewLog = "\(prefix)/var/log/routun"
            if fm.fileExists(atPath: brewLog) { return brewLog }
        }
        if fm.fileExists(atPath: "/var/log/routun") {
            return "/var/log/routun"
        }
        if let prefix = homebrewPrefix {
            return "\(prefix)/var/log/routun"
        }
        return "/var/log/routun"
    }

    public static var daemonLogFile: String { "\(logDir)/daemon.log" }
    public static var daemonErrFile: String { "\(logDir)/daemon.err" }

    public static var pidFile: String {
        let fm = FileManager.default
        if let prefix = homebrewPrefix, fm.fileExists(atPath: "\(prefix)/var/run") {
            return "\(prefix)/var/run/routun.pid"
        }
        return "/var/run/routun.pid"
    }

    public static func defaultConfiguration() -> RoutunConfig {
        var searchDirs = [String]()
        if let prefix = homebrewPrefix {
            searchDirs.append("\(prefix)/bin")
        }
        searchDirs.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ])

        let ciadpi = findBinary(named: "ciadpi", searchPaths: searchDirs) ?? "/usr/local/bin/ciadpi"
        let singbox = findBinary(named: "sing-box", searchPaths: searchDirs) ?? "/opt/homebrew/bin/sing-box"

        return RoutunConfig(
            ciadpiPath: ciadpi,
            singboxPath: singbox,
            ciadpiArgs: ["-i", "127.0.0.1", "-p", "1080", "-A", "torst,ssl_err", "-s", "1", "-d", "3+s", "-r", "1+s", "-t", "3", "-c", "512"],
            socksHost: "127.0.0.1",
            socksPort: 1080,
            tunInterface: "utun10",
            singboxConfig: defaultSingboxConfigFile,
            selectedProfile: "default"
        )
    }

    public static func isExecutableBinary(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    public static func findBinary(named name: String, searchPaths: [String]) -> String? {
        // Check given paths (both as directory prefix and direct path)
        for path in searchPaths {
            let candidate = path.hasSuffix("/\(name)") ? path : (path.hasSuffix("/") ? "\(path)\(name)" : "\(path)/\(name)")
            if isExecutableBinary(atPath: candidate) {
                return candidate
            }
            if isExecutableBinary(atPath: path) {
                return path
            }
        }
        // Check PATH environment variable
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = String(dir) + "/" + name
                if isExecutableBinary(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    public static func load() -> RoutunConfig {
        let path = defaultConfigFile
        if FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           var config = try? JSONDecoder().decode(RoutunConfig.self, from: data) {
            let fm = FileManager.default
            if config.singboxConfig.isEmpty || !fm.fileExists(atPath: config.singboxConfig) {
                config.singboxConfig = defaultSingboxConfigFile
            }
            if config.ciadpiPath.isEmpty || !isExecutableBinary(atPath: config.ciadpiPath) {
                if let found = findBinary(named: "ciadpi", searchPaths: ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin"]) {
                    config.ciadpiPath = found
                }
            }
            if config.singboxPath.isEmpty || !isExecutableBinary(atPath: config.singboxPath) {
                if let found = findBinary(named: "sing-box", searchPaths: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]) {
                    config.singboxPath = found
                }
            }
            if !config.ciadpiArgs.contains("-A") && !config.ciadpiArgs.contains("--auto") {
                if let profileId = config.selectedProfile, let p = StrategyProfiles.find(by: profileId) {
                    config.ciadpiArgs = p.fullArgs(host: config.socksHost, port: config.socksPort)
                } else if let pIdx = config.ciadpiArgs.firstIndex(of: "-p"), pIdx + 1 < config.ciadpiArgs.count {
                    config.ciadpiArgs.insert(contentsOf: ["-A", "torst,ssl_err"], at: pIdx + 2)
                } else {
                    config.ciadpiArgs.insert(contentsOf: ["-A", "torst,ssl_err"], at: 0)
                }
            }
            return config
        }
        return defaultConfiguration()
    }
}
