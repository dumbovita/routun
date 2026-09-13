import Darwin
import Foundation

public struct ServiceState {
    public let isLoaded: Bool
    public let isRunning: Bool
    public let supervisorPid: Int?
    public let ciadpiPid: Int?
    public let singboxPid: Int?
    public let startedAt: String?
    public let tunInterface: String?
}

public final class ServiceManager {
    public static let shared = ServiceManager()

    private let legacyLabels = ["sh.brew.routun", "homebrew.mxcl.routun", "com.routun.daemon"]
    private let legacyPlists = [
        "/Library/LaunchDaemons/sh.brew.routun.plist",
        "/Library/LaunchDaemons/homebrew.mxcl.routun.plist",
        "/Library/LaunchDaemons/com.routun.daemon.plist"
    ]

    public func getStatus() -> ServiceState {
        let (code, _) = runCommand("/bin/launchctl", ["print", "system/\(RoutunConfig.serviceLabel)"])
        guard code == 0 else {
            return ServiceState(isLoaded: false, isRunning: false, supervisorPid: nil, ciadpiPid: nil, singboxPid: nil, startedAt: nil, tunInterface: nil)
        }

        let state = readState()
        let supervisorPid = state?["supervisor_pid"] as? Int
        return ServiceState(
            isLoaded: true,
            isRunning: supervisorPid.map(NetUtils.isProcessAlive) ?? false,
            supervisorPid: supervisorPid,
            ciadpiPid: state?["ciadpi_pid"] as? Int,
            singboxPid: state?["singbox_pid"] as? Int,
            startedAt: state?["started_at"] as? String,
            tunInterface: state?["tun_interface"] as? String
        )
    }

    public func installedPayloadVersion() -> String? {
        guard RoutunConfig.isExecutableBinary(atPath: RoutunConfig.daemonBinaryPath) else { return nil }
        let (code, output) = runCommand(RoutunConfig.daemonBinaryPath, ["version"])
        guard code == 0 else { return nil }
        return output.split(separator: " ").last.map(String.init)
    }

    public func syncSingboxConfig(from configuration: RoutunConfig) throws {
        let data = try SingBoxConfigBuilder.buildJsonData(
            policy: configuration.routePolicy,
            socksHost: configuration.socksHost,
            socksPort: configuration.socksPort
        )
        let targetPath = configuration.singboxConfig.isEmpty ? RoutunConfig.defaultSingboxConfigFile : configuration.singboxConfig
        let parentDir = (targetPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: targetPath), options: .atomic)
        _ = chmod(targetPath, 0o644)
    }

    public func installAndStart() -> (success: Bool, message: String) {
        let configuration = RoutunConfig.installationConfiguration()
        guard let ciadpiSource = RoutunConfig.dependencySource(named: "ciadpi", configuredPath: configuration.ciadpiPath) else {
            return (false, "ByeDPI (ciadpi) was not found. Install it first, then run sudo routun install.")
        }
        guard let singboxSource = RoutunConfig.dependencySource(named: "sing-box", configuredPath: configuration.singboxPath) else {
            return (false, "sing-box was not found. Install it first, then run sudo routun install.")
        }

        do {
            try prepareServiceDirectories()
            try installFile(from: RoutunConfig.currentExecutablePath(), to: RoutunConfig.daemonBinaryPath, mode: 0o755)
            try installFile(from: ciadpiSource, to: RoutunConfig.serviceCiadpiPath, mode: 0o755)
            try installFile(from: singboxSource, to: RoutunConfig.serviceSingboxPath, mode: 0o755)

            var installedConfig = configuration
            installedConfig.ciadpiPath = RoutunConfig.serviceCiadpiPath
            installedConfig.singboxPath = RoutunConfig.serviceSingboxPath
            installedConfig.singboxConfig = RoutunConfig.defaultSingboxConfigFile

            // Generate typed sing-box configuration from active policy
            try syncSingboxConfig(from: installedConfig)
            try secureRegularFile(at: RoutunConfig.defaultSingboxConfigFile, mode: 0o644)

            try installedConfig.save()
            try secureRegularFile(at: RoutunConfig.defaultConfigFile, mode: 0o644)

            let (checkCode, checkOutput) = runCommand(
                RoutunConfig.serviceSingboxPath,
                ["check", "-c", RoutunConfig.defaultSingboxConfigFile]
            )
            guard checkCode == 0 else {
                return (false, "sing-box rejected the generated configuration: \(checkOutput)")
            }

            try writeLaunchDaemonPlist()
            removeLegacyServices()
        } catch {
            return (false, error.localizedDescription)
        }

        if getStatus().isLoaded {
            let stopped = stop()
            if !stopped.success { return stopped }
        }
        return start()
    }

    public func start() -> (success: Bool, message: String) {
        guard FileManager.default.fileExists(atPath: RoutunConfig.launchDaemonPlist),
              RoutunConfig.isExecutableBinary(atPath: RoutunConfig.daemonBinaryPath) else {
            return (false, "The service payload is not installed. Run sudo routun install first.")
        }

        if getStatus().isLoaded {
            return (true, "Service is already loaded.")
        }

        let (code, output) = runCommand("/bin/launchctl", ["bootstrap", "system", RoutunConfig.launchDaemonPlist])
        guard code == 0 else {
            return (false, "launchctl bootstrap failed: \(output)")
        }
        return (true, "Service registered with launchd.")
    }

    public func stop() -> (success: Bool, message: String) {
        guard getStatus().isLoaded else {
            try? FileManager.default.removeItem(atPath: RoutunConfig.stateFile)
            return (true, "Service is not loaded.")
        }

        let (code, output) = runCommand("/bin/launchctl", ["bootout", "system/\(RoutunConfig.serviceLabel)"])
        guard code == 0 else {
            return (false, "launchctl bootout failed: \(output)")
        }
        try? FileManager.default.removeItem(atPath: RoutunConfig.stateFile)
        return (true, "Service stopped.")
    }

    public func restart() -> (success: Bool, message: String) {
        guard getStatus().isLoaded else { return start() }

        let (code, output) = runCommand("/bin/launchctl", ["kickstart", "-k", "system/\(RoutunConfig.serviceLabel)"])
        guard code == 0 else {
            return (false, "launchctl kickstart failed: \(output)")
        }
        return (true, "Service restarted.")
    }

    public func uninstall() -> (success: Bool, message: String) {
        let stopped = stop()
        guard stopped.success else { return stopped }
        removeLegacyServices()

        do {
            try removeIfPresent(RoutunConfig.launchDaemonPlist)
            try removeIfPresent(RoutunConfig.serviceBinDir)
            try removeIfPresent(RoutunConfig.appSupportDir)
            if isRootOwnedRegularFile(at: "/usr/local/bin/routun") {
                try removeIfPresent("/usr/local/bin/routun")
            }
        } catch {
            return (false, error.localizedDescription)
        }
        return (true, "Service payload and configuration removed. If installed with Homebrew, run brew uninstall routun separately.")
    }

    @discardableResult
    public func terminateRecordedChildren() -> Int {
        guard let state = readState() else { return 0 }
        let children = [
            (state["singbox_pid"] as? Int, "sing-box", "-TERM"),
            (state["ciadpi_pid"] as? Int, "ciadpi", "-HUP")
        ]

        return children.reduce(into: 0) { count, child in
            guard let pid = child.0, pid > 0 else { return }
            let (code, command) = runCommand("/bin/ps", ["-p", String(pid), "-o", "command="])
            guard code == 0 else { return }
            let exec = command.split(separator: " ").first.map(String.init) ?? ""
            guard exec.hasSuffix("/\(child.1)") || exec == child.1 else { return }

            _ = runCommand("/bin/kill", [child.2, String(pid)])

            // Wait up to 1 second for the process to exit
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline && NetUtils.isProcessAlive(pid: pid) {
                usleep(20_000)
            }
            if NetUtils.isProcessAlive(pid: pid) {
                let (checkCode, checkCommand) = runCommand("/bin/ps", ["-p", String(pid), "-o", "command="])
                let checkExec = checkCommand.split(separator: " ").first.map(String.init) ?? ""
                if checkCode == 0 && (checkExec.hasSuffix("/\(child.1)") || checkExec == child.1) {
                    _ = runCommand("/bin/kill", ["-9", String(pid)])
                    let killDeadline = Date().addingTimeInterval(0.5)
                    while Date() < killDeadline && NetUtils.isProcessAlive(pid: pid) {
                        usleep(20_000)
                    }
                }
            }
            if !NetUtils.isProcessAlive(pid: pid) {
                count += 1
            }
        }
    }

    @discardableResult
    public func runCommand(_ executable: String, _ arguments: [String]) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    static func launchDaemonPlistData() throws -> Data {
        let plist: [String: Any] = [
            "Label": RoutunConfig.serviceLabel,
            "ProgramArguments": [RoutunConfig.daemonBinaryPath, "daemon"],
            "KeepAlive": ["SuccessfulExit": false],
            "Umask": 0o022
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private func prepareServiceDirectories() throws {
        for path in ["/usr/local/libexec", RoutunConfig.serviceBinDir, RoutunConfig.appSupportDir, RoutunConfig.serviceConfigDir, RoutunConfig.serviceStateDir] {
            try secureDirectory(at: path)
        }
    }

    private func writeLaunchDaemonPlist() throws {
        try ServiceManager.launchDaemonPlistData().write(to: URL(fileURLWithPath: RoutunConfig.launchDaemonPlist), options: .atomic)
        try secureRegularFile(at: RoutunConfig.launchDaemonPlist, mode: 0o644)
    }

    private func installFile(from source: String, to destination: String, mode: mode_t) throws {
        let resolvedSource = URL(fileURLWithPath: source).resolvingSymlinksInPath().path
        guard isRegularFile(at: resolvedSource) else {
            throw ServiceError("Expected a regular file at \(source).")
        }

        let temporary = (destination as NSString).deletingLastPathComponent + "/.\((destination as NSString).lastPathComponent).new"
        try removeIfPresent(temporary)
        try FileManager.default.copyItem(atPath: resolvedSource, toPath: temporary)
        do {
            try secureRegularFile(at: temporary, mode: mode)
            guard rename(temporary, destination) == 0 else {
                throw ServiceError("Could not activate \(destination): \(String(cString: strerror(errno))).")
            }
        } catch {
            try? removeIfPresent(temporary)
            throw error
        }
    }

    private func secureDirectory(at path: String) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, isDirectoryPath(path) else {
                throw ServiceError("Refusing to use non-directory path \(path).")
            }
        } else {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        guard chown(path, 0, 0) == 0, chmod(path, 0o755) == 0 else {
            throw ServiceError("Could not secure \(path): \(String(cString: strerror(errno))).")
        }
    }

    private func secureRegularFile(at path: String, mode: mode_t) throws {
        guard isRegularFile(at: path) else {
            throw ServiceError("Refusing to use non-regular file \(path).")
        }
        guard chown(path, 0, 0) == 0, chmod(path, mode) == 0 else {
            throw ServiceError("Could not secure \(path): \(String(cString: strerror(errno))).")
        }
    }

    private func isDirectoryPath(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private func isRegularFile(at path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    private func isRootOwnedRegularFile(at path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_uid == 0
    }

    private func readState() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: RoutunConfig.stateFile)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func removeLegacyServices() {
        for label in legacyLabels {
            _ = runCommand("/bin/launchctl", ["bootout", "system/\(label)"])
            if let uid = legacyGUIUserID() {
                _ = runCommand("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
            }
        }
        for plist in legacyPlists {
            try? removeIfPresent(plist)
        }
    }

    private func legacyGUIUserID() -> uid_t? {
        if let value = ProcessInfo.processInfo.environment["SUDO_UID"], let uid = uid_t(value) {
            return uid
        }

        var info = stat()
        guard stat("/dev/console", &info) == 0, info.st_uid != 0 else { return nil }
        return info.st_uid
    }

    private func removeIfPresent(_ path: String) throws {
        var info = stat()
        if lstat(path, &info) == 0 {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}

private struct ServiceError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
