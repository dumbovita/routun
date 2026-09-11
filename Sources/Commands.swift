import Foundation
import Darwin

public final class RoutunCommands {
    private static let green = "\u{001B}[32m"
    private static let red = "\u{001B}[31m"
    private static let yellow = "\u{001B}[33m"
    private static let bold = "\u{001B}[1m"
    private static let cyan = "\u{001B}[36m"
    private static let reset = "\u{001B}[0m"

    public static func status() {
        let config = RoutunConfig.load()
        let state = ServiceManager.shared.getStatus()

        print("\(bold)routun.service\(reset) - Transparent TUN-based network routing for macOS")
        print("------------------------------------------------------------")

        // 1. LaunchDaemon Status
        let homebrewTag = RoutunConfig.isHomebrewService ? " [Homebrew Service]" : ""
        let daemonStatusStr = state.isLoaded
            ? "\(green)● loaded\(reset) (\(RoutunConfig.launchDaemonPlist))\(homebrewTag)"
            : "\(red)○ not loaded\(reset)"
        print("  LaunchDaemon:   \(daemonStatusStr)")

        // 2. Supervisor Process
        if state.isRunning, let sPid = state.supervisorPid, kill(pid_t(sPid), 0) == 0 {
            let startedStr = state.startedAt != nil ? " since \(state.startedAt!)" : ""
            print("  Supervisor:     \(green)active (running)\(reset) [PID \(sPid)]\(startedStr)")
        } else {
            print("  Supervisor:     \(red)inactive (stopped)\(reset)")
        }

        // 3. ByeDPI (ciadpi) Process & Port
        let socksOpen = NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.3)
        var ciadpiStatus = "not running"
        if let cPid = state.ciadpiPid, kill(pid_t(cPid), 0) == 0 {
            ciadpiStatus = "PID \(cPid) (managed)"
        } else {
            let (code, out) = ServiceManager.shared.runCommand("/usr/bin/pgrep", ["-x", "ciadpi"])
            if code == 0, !out.isEmpty {
                let firstPid = out.components(separatedBy: .newlines).first ?? ""
                ciadpiStatus = "\(yellow)PID \(firstPid) (unmanaged)\(reset)"
            }
        }
        let portStatus = socksOpen ? "\(green)listening on \(config.socksHost):\(config.socksPort)\(reset)" : "\(red)port \(config.socksPort) closed\(reset)"
        print("  ByeDPI:         \(ciadpiStatus) (\(portStatus))")

        // 4. Sing-box Process & Interface
        let (tunExists, tunUp, tunIp) = NetUtils.getInterfaceInfo(name: config.tunInterface)
        var singboxStatus = "not running"
        if let sPid = state.singboxPid, kill(pid_t(sPid), 0) == 0 {
            singboxStatus = "PID \(sPid) (managed)"
        } else {
            let (code, out) = ServiceManager.shared.runCommand("/usr/bin/pgrep", ["-x", "sing-box"])
            if code == 0, !out.isEmpty {
                let firstPid = out.components(separatedBy: .newlines).first ?? ""
                singboxStatus = "\(yellow)PID \(firstPid) (unmanaged)\(reset)"
            }
        }
        let tunStatus = (tunExists && tunUp)
            ? "\(green)\(config.tunInterface) UP\(reset) (IP: \(tunIp ?? "active"))"
            : "\(red)\(config.tunInterface) DOWN\(reset)"
        print("  sing-box:       \(singboxStatus) (\(tunStatus))")

        // 5. Live DPI Bypass Verification
        let (bypassOk, bypassMsg) = NetUtils.testDPIBypass(url: "https://discord.com", timeout: 3.5)
        if bypassOk {
            print("  DPI Bypass:     \(green)Verified [OK]\(reset) (discord.com reachable: \(bypassMsg))")
        } else {
            print("  DPI Bypass:     \(yellow)Unverified [\(bypassMsg)]\(reset) (Check logs if blocked)")
        }
        print("------------------------------------------------------------")
    }

    public static func start() {
        guard ensureRoot() else { return }

        print("\(cyan)Starting routun service...\(reset)")
        let result = ServiceManager.shared.start()
        if !result.success {
            print("\(red)Error:\(reset) \(result.message)")
            exit(1)
        }

        print("Waiting for service initialization...")
        sleep(2)
        status()
    }

    public static func stop() {
        guard ensureRoot() else { return }

        print("\(cyan)Stopping routun service...\(reset)")
        let result = ServiceManager.shared.stop()
        if !result.success {
            print("\(red)Error:\(reset) \(result.message)")
            exit(1)
        }

        sleep(1)
        print("\(green)routun service stopped cleanly. Native macOS network routing restored.\(reset)")
    }

    public static func restart() {
        guard ensureRoot() else { return }

        print("\(cyan)Restarting routun service...\(reset)")
        let result = ServiceManager.shared.restart()
        if !result.success {
            print("\(red)Error:\(reset) \(result.message)")
            exit(1)
        }

        sleep(2)
        status()
    }

    public static func logs(follow: Bool, lines: Int, errorOnly: Bool) {
        let filePath = errorOnly ? RoutunConfig.daemonErrFile : RoutunConfig.daemonLogFile

        guard FileManager.default.fileExists(atPath: filePath) else {
            print("\(yellow)Log file not found at \(filePath).\(reset)")
            print("Checking Apple Unified Logging for routun entries (last 1h):")
            let (_, out) = ServiceManager.shared.runCommand("/usr/bin/log", ["show", "--predicate", "subsystem CONTAINS 'routun'", "--last", "1h"])
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print(trimmed)
            } else {
                print("No recent system logs found for routun.")
            }
            return
        }

        if follow {
            print("\(cyan)Streaming logs from \(filePath) (Press Ctrl+C to stop)...\(reset)")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            proc.arguments = ["-n", String(lines), "-f", filePath]
            proc.standardInput = FileHandle.standardInput
            proc.standardOutput = FileHandle.standardOutput
            proc.standardError = FileHandle.standardError
            try? proc.run()
            proc.waitUntilExit()
        } else {
            let (_, out) = ServiceManager.shared.runCommand("/usr/bin/tail", ["-n", String(lines), filePath])
            print(out)
        }
    }

    public static func doctor() {
        let config = RoutunConfig.load()
        let fm = FileManager.default

        print("\(bold)=== routun System Diagnostic Report ===\(reset)")

        // OS info
        let (_, osVer) = ServiceManager.shared.runCommand("/usr/bin/sw_vers", ["-productVersion"])
        let (_, arch) = ServiceManager.shared.runCommand("/usr/bin/uname", ["-m"])
        print("  System:         macOS \(osVer) (\(arch))")

        // Environment info
        if let prefix = RoutunConfig.homebrewPrefix {
            let mode = RoutunConfig.isHomebrewService ? "Homebrew Service (\(RoutunConfig.serviceLabel))" : "Homebrew Environment"
            print("  Environment:    \(green)\(mode)\(reset) [Prefix: \(prefix)]")
        } else {
            print("  Environment:    Standalone (/Library/Application Support/routun)")
        }
        print("  Config Dir:     \(RoutunConfig.configDir)")

        // Privilege check
        let isRoot = geteuid() == 0
        print("  Current User:   \(isRoot ? "\(green)root (uid 0)\(reset)" : "\(yellow)non-root (uid \(geteuid()))\(reset)")")

        // Binary: ciadpi
        if fm.isExecutableFile(atPath: config.ciadpiPath) {
            print("  ByeDPI Path:    \(green)OK\(reset) (\(config.ciadpiPath))")
        } else {
            print("  ByeDPI Path:    \(red)MISSING / NOT EXECUTABLE\(reset) (\(config.ciadpiPath))")
        }

        // Binary: sing-box
        if fm.isExecutableFile(atPath: config.singboxPath) {
            let (_, ver) = ServiceManager.shared.runCommand(config.singboxPath, ["version"])
            let firstLine = ver.components(separatedBy: .newlines).first ?? ""
            print("  sing-box Path:  \(green)OK\(reset) (\(config.singboxPath)) - \(firstLine)")
        } else {
            print("  sing-box Path:  \(red)MISSING / NOT EXECUTABLE\(reset) (\(config.singboxPath))")
        }

        // Config: singbox.json
        if fm.fileExists(atPath: config.singboxConfig) {
            if fm.isExecutableFile(atPath: config.singboxPath) {
                let (cCode, cOut) = ServiceManager.shared.runCommand(config.singboxPath, ["check", "-c", config.singboxConfig])
                if cCode == 0 {
                    print("  sing-box Conf:  \(green)VALID\(reset) (\(config.singboxConfig))")
                } else {
                    print("  sing-box Conf:  \(red)INVALID SYNTAX\(reset) - \(cOut)")
                }
            } else {
                print("  sing-box Conf:  \(green)PRESENT\(reset) (\(config.singboxConfig))")
            }
        } else if fm.fileExists(atPath: "config/singbox.json") {
            let (cCode, cOut) = ServiceManager.shared.runCommand(config.singboxPath, ["check", "-c", "config/singbox.json"])
            if cCode == 0 {
                print("  sing-box Conf:  \(yellow)NOT INSTALLED\(reset) (local config/singbox.json is \(green)VALID\(reset))")
            } else {
                print("  sing-box Conf:  \(yellow)NOT INSTALLED\(reset) (local config/singbox.json has syntax error: \(cOut))")
            }
        } else {
            print("  sing-box Conf:  \(red)MISSING\(reset) at \(config.singboxConfig)")
        }

        // LaunchDaemon plist
        let state = ServiceManager.shared.getStatus()
        if let plist = RoutunConfig.installedPlistPath {
            let loadedTag = state.isLoaded ? " [\(green)LOADED\(reset)]" : " [\(yellow)NOT LOADED\(reset)]"
            print("  LaunchDaemon:   \(green)INSTALLED\(reset) (\(plist))\(loadedTag)")
        } else if state.isLoaded {
            print("  LaunchDaemon:   \(green)LOADED IN LAUNCHD\(reset) (\(RoutunConfig.serviceLabel))")
        } else {
            print("  LaunchDaemon:   \(yellow)NOT INSTALLED\(reset)")
        }

        // Service logs & errors
        if fm.fileExists(atPath: RoutunConfig.daemonErrFile) {
            let errSize = (try? fm.attributesOfItem(atPath: RoutunConfig.daemonErrFile)[.size] as? UInt64) ?? 0
            if errSize > 0 {
                print("  Service Errors: \(yellow)\(errSize) bytes logged in \(RoutunConfig.daemonErrFile)\(reset)")
            } else {
                print("  Service Errors: \(green)None (0 errors)\(reset)")
            }
        } else {
            print("  Service Errors: \(green)None (clean log state)\(reset)")
        }

        // Sockets
        let portBusy = NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.2)
        print("  Port 1080:      \(portBusy ? "\(cyan)OCCUPIED / LISTENING\(reset)" : "\(green)AVAILABLE\(reset)")")

        // TUN interface
        let (tunExists, tunUp, tunIp) = NetUtils.getInterfaceInfo(name: config.tunInterface)
        if tunExists {
            print("  Interface \(config.tunInterface): \(tunUp ? "\(green)UP\(reset) (\(tunIp ?? ""))" : "\(yellow)DOWN\(reset)")")
        } else {
            print("  Interface \(config.tunInterface): \(yellow)INACTIVE (normal when stopped)\(reset)")
        }

        print("========================================")
    }

    public static func install() {
        guard ensureRoot() else { return }
        let scriptPath = FileManager.default.isExecutableFile(atPath: "install.sh") ? "install.sh" : "scripts/install.sh"
        if FileManager.default.isExecutableFile(atPath: scriptPath) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath]
            proc.standardInput = FileHandle.standardInput
            proc.standardOutput = FileHandle.standardOutput
            proc.standardError = FileHandle.standardError
            try? proc.run()
            proc.waitUntilExit()
            exit(proc.terminationStatus)
        } else {
            print("\(red)Error:\(reset) install.sh not found. Run from the routun repository directory.")
        }
    }

    public static func uninstall() {
        guard ensureRoot() else { return }
        print("\(cyan)Stopping and removing routun service...\(reset)")
        _ = ServiceManager.shared.stop()
        _ = ServiceManager.shared.runCommand("/usr/bin/killall", ["sing-box"])
        _ = ServiceManager.shared.runCommand("/usr/bin/killall", ["ciadpi"])
        try? FileManager.default.removeItem(atPath: RoutunConfig.launchDaemonPlist)
        try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.routun.daemon.plist")
        try? FileManager.default.removeItem(atPath: RoutunConfig.appSupportDir)
        try? FileManager.default.removeItem(atPath: RoutunConfig.logDir)
        try? FileManager.default.removeItem(atPath: RoutunConfig.pidFile)
        _ = ServiceManager.shared.runCommand("/sbin/ifconfig", ["utun10", "down"])
        try? FileManager.default.removeItem(atPath: RoutunConfig.installedBinaryPath)
        print("\(green)routun has been completely uninstalled from this system.\(reset)")
    }

    private static func ensureRoot() -> Bool {
        if geteuid() == 0 { return true }

        // If running in an interactive terminal, automatically elevate via sudo
        if isatty(STDIN_FILENO) != 0 {
            var args = CommandLine.arguments
            let execPath = Bundle.main.executablePath ?? "/usr/local/bin/routun"
            args[0] = execPath
            args.insert("/usr/bin/sudo", at: 0)
            let cArgs = args.map { strdup($0) } + [nil]
            execv("/usr/bin/sudo", cArgs)
        }

        print("\(red)Error:\(reset) This operation requires root privileges.")
        print("Please run with sudo: \(bold)sudo routun <command>\(reset)")
        return false
    }
}
