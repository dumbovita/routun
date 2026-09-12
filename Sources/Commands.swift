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

        let daemonStatusStr = state.isLoaded
            ? "\(green)● loaded\(reset) (\(RoutunConfig.launchDaemonPlist))"
            : "\(red)○ not loaded\(reset)"
        print("  LaunchDaemon:   \(daemonStatusStr)")
        let payloadVersion = ServiceManager.shared.installedPayloadVersion() ?? "not installed"
        let updateTag = payloadVersion == version ? "" : " \(yellow)[run sudo routun install to sync]\(reset)"
        print("  Service payload: \(payloadVersion)\(updateTag)")

        if state.isRunning, let sPid = state.supervisorPid, NetUtils.isProcessAlive(pid: sPid) {
            let startedStr = state.startedAt != nil ? " since \(state.startedAt!)" : ""
            print("  Supervisor:     \(green)active (running)\(reset) [PID \(sPid)]\(startedStr)")
        } else if state.isLoaded {
            print("  Supervisor:     \(yellow)starting or restarting\(reset)")
        } else {
            print("  Supervisor:     \(red)inactive (stopped)\(reset)")
        }

        let socksOpen = NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.3)
        var ciadpiStatus = "not running"
        if let cPid = state.ciadpiPid, NetUtils.isProcessAlive(pid: cPid) {
            ciadpiStatus = "PID \(cPid) (managed)"
        }
        let portStatus = socksOpen ? "\(green)listening on \(config.socksHost):\(config.socksPort)\(reset)" : "\(red)port \(config.socksPort) closed\(reset)"
        print("  ByeDPI:         \(ciadpiStatus) (\(portStatus))")
        let activeProfile = config.selectedProfile ?? "default"
        print("  Strategy:       \(bold)\(activeProfile)\(reset) (\(StrategyProfiles.find(by: activeProfile)?.name ?? "Custom"))")

        let tunInterface = state.tunInterface?.isEmpty == false
            ? state.tunInterface
            : state.isLoaded ? NetUtils.tunInterface() : nil
        let tunInfo = tunInterface.map(NetUtils.getInterfaceInfo) ?? (false, false, nil)
        var singboxStatus = "not running"
        if let sPid = state.singboxPid, NetUtils.isProcessAlive(pid: sPid) {
            singboxStatus = "PID \(sPid) (managed)"
        }
        let tunStatus = tunInfo.0 && tunInfo.1
            ? "\(green)\(tunInterface ?? "utun") UP\(reset) (IP: \(tunInfo.2 ?? "active"))"
            : "\(red)no routun TUN interface\(reset)"
        print("  sing-box:       \(singboxStatus) (\(tunStatus))")
        print("------------------------------------------------------------")
    }

    public static func start() {
        guard ensureRoot() else { exit(1) }

        print("\(cyan)Starting routun service...\(reset)")
        let result = ServiceManager.shared.start()
        if !result.success {
            print("\(red)Error:\(reset) \(result.message)")
            exit(1)
        }

        print("\(green)\(result.message)\(reset)")
    }

    public static func stop() {
        guard ensureRoot() else { exit(1) }

        print("\(cyan)Stopping routun service...\(reset)")
        let result = ServiceManager.shared.stop()
        if !result.success {
            print("\(red)Error:\(reset) \(result.message)")
            exit(1)
        }

        print("\(green)\(result.message)\(reset)")
    }

    public static func restart() {
        guard ensureRoot() else { exit(1) }

        print("\(cyan)Restarting routun service...\(reset)")
        let result = ServiceManager.shared.restart()
        if !result.success {
            print("\(red)Error:\(reset) \(result.message)")
            exit(1)
        }

        print("\(green)\(result.message)\(reset)")
    }

    public static func logs(follow: Bool, lines: Int, errorOnly: Bool) {
        let predicate = errorOnly
            ? "subsystem == 'com.routun.routund' AND messageType == error"
            : "subsystem == 'com.routun.routund'"
        if follow {
            print("\(cyan)Streaming unified routun logs (Press Ctrl+C to stop)...\(reset)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = ["stream", "--style", "compact", "--predicate", predicate]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("\(red)Error:\(reset) Could not start log stream: \(error.localizedDescription)")
            }
        } else {
            let (code, output) = ServiceManager.shared.runCommand("/usr/bin/log", ["show", "--style", "compact", "--predicate", predicate, "--last", "1h"])
            guard code == 0 else {
                print("\(red)Error:\(reset) Could not read unified logs: \(output)")
                return
            }
            let recent = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(max(1, lines))
            print(recent.joined(separator: "\n"))
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

        print("  Service root:   \(RoutunConfig.appSupportDir)")
        print("  Config Dir:     \(RoutunConfig.serviceConfigDir)")

        // Privilege check
        let isRoot = geteuid() == 0
        print("  Current User:   \(isRoot ? "\(green)root (uid 0)\(reset)" : "\(yellow)non-root (uid \(geteuid()))\(reset)")")

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
        } else {
            print("  sing-box Conf:  \(red)MISSING\(reset) at \(config.singboxConfig)")
        }

        let state = ServiceManager.shared.getStatus()
        if fm.fileExists(atPath: RoutunConfig.launchDaemonPlist) {
            let loadedTag = state.isLoaded ? " [\(green)LOADED\(reset)]" : " [\(yellow)NOT LOADED\(reset)]"
            print("  LaunchDaemon:   \(green)INSTALLED\(reset) (\(RoutunConfig.launchDaemonPlist))\(loadedTag)")
        } else {
            print("  LaunchDaemon:   \(yellow)NOT INSTALLED\(reset)")
        }
        print("  Logs:           Apple Unified Logging (routun logs)")

        // Sockets
        let portBusy = NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.2)
        print("  Port 1080:      \(portBusy ? "\(cyan)OCCUPIED / LISTENING\(reset)" : "\(green)AVAILABLE\(reset)")")

        // TUN interface
        let activeInterface = state.tunInterface?.isEmpty == false
            ? state.tunInterface
            : state.isLoaded ? NetUtils.tunInterface() : nil
        if let activeInterface {
            let tunInfo = NetUtils.getInterfaceInfo(name: activeInterface)
            print("  Interface \(activeInterface): \(tunInfo.isUp ? "\(green)UP\(reset) (\(tunInfo.ip ?? ""))" : "\(yellow)DOWN\(reset)")")
        } else {
            print("  TUN Interface:  \(yellow)INACTIVE (normal when stopped)\(reset)")
        }

        print("========================================")
    }

    public static func install() {
        guard ensureRoot() else { exit(1) }
        print("\(cyan)Installing the protected routun service payload...\(reset)")
        let result = ServiceManager.shared.installAndStart()
        if result.success {
            print("\(green)\(result.message)\(reset)")
        } else {
            print("\(red)Error installing service:\(reset) \(result.message)")
            exit(1)
        }
    }

    public static func uninstall() {
        guard ensureRoot() else { exit(1) }
        print("\(cyan)Stopping and removing routun service...\(reset)")
        let result = ServiceManager.shared.uninstall()
        if result.success {
            print("\(green)\(result.message)\(reset)")
        } else {
            print("\(red)Error uninstalling service:\(reset) \(result.message)")
            exit(1)
        }
    }

    public static func optimize(verbose: Bool = false, quick: Bool = false, customTargets: [String] = []) {
        let config = RoutunConfig.load()
        guard FileManager.default.isExecutableFile(atPath: config.ciadpiPath) else {
            print("\(red)Error:\(reset) ByeDPI (ciadpi) binary not found at \(config.ciadpiPath).")
            print("Please ensure ciadpi is installed before running optimization.")
            exit(1)
        }

        let state = ServiceManager.shared.getStatus()
        let isRoot = (geteuid() == 0)

        // If the service is running but we are not root, escalate via sudo
        // so that the service can be paused during testing and restarted cleanly with the new profile.
        if state.isRunning && !isRoot {
            print("\(yellow)Notice:\(reset) The routun DPI service is currently active.")
            print("To eliminate DPI routing interference during optimization, the service will be temporarily paused.")
            print("Re-running with sudo...\n")

            let execPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
            var args = ["sudo", execPath]
            if CommandLine.arguments.count > 1 {
                args.append(contentsOf: CommandLine.arguments.dropFirst())
            }
            let cArgs = args.map { strdup($0) } + [nil]
            execvp("/usr/bin/sudo", cArgs)

            // If execvp returns, it failed to elevate
            print("\(red)Error:\(reset) Privilege escalation failed. Please run:")
            print("  \(bold)sudo routun optimize\(reset)")
            exit(1)
        }

        let wasRunning = state.isRunning
        var didStopService = false

        if wasRunning && isRoot {
            print("\(yellow)Temporarily pausing routun service to eliminate DPI routing interference...\(reset)")
            let stopRes = ServiceManager.shared.stop()
            if stopRes.success {
                didStopService = true
            }
        }

        // Setup signal handlers to guarantee service restoration on Ctrl+C (SIGINT) or kill (SIGTERM)
        var restored = false
        let restoreService = { (reason: String) in
            guard didStopService && !restored else { return }
            restored = true
            print("\n\(yellow)\(reason) Restoring routun service...\(reset)")
            let res = ServiceManager.shared.start()
            if res.success {
                print("\(green)routun service restored successfully.\(reset)")
            } else {
                print("\(red)Failed to restore service: \(res.message)\(reset)")
            }
        }

        let parsedCustom = StrategyTarget.parseList(from: customTargets)
        let optimizer = StrategyOptimizer(
            ciadpiPath: config.ciadpiPath,
            verbose: verbose,
            quick: quick,
            customTargets: parsedCustom
        )

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigQueue = DispatchQueue(label: "routun.signal.handler")
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: sigQueue)
        sigintSource.setEventHandler {
            optimizer.cancel()
            restoreService("Optimization interrupted by user.")
            exit(130)
        }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: sigQueue)
        sigtermSource.setEventHandler {
            optimizer.cancel()
            restoreService("Optimization terminated.")
            exit(143)
        }
        sigtermSource.resume()

        defer {
            sigintSource.cancel()
            sigtermSource.cancel()
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }

        guard let selected = optimizer.run() else {
            print("\(yellow)Optimization completed without selecting a new profile. Preserving existing configuration.\(reset)")
            if didStopService && !restored {
                restored = true
                print("\(yellow)Restoring routun service with existing configuration...\(reset)")
                _ = ServiceManager.shared.start()
            }
            return
        }

        if StrategyOptimizer.saveProfile(selected) {
            print("\(green)Saved strategy profile '\(selected.id)' to \(RoutunConfig.defaultConfigFile).\(reset)")
        } else {
            print("\(yellow)Warning: Could not save profile to \(RoutunConfig.defaultConfigFile). Run with sudo to persist.\(reset)")
        }

        if didStopService && !restored {
            restored = true
            print("\n\(green)Starting routun service with newly selected profile '\(selected.id)'...\(reset)")
            let startRes = ServiceManager.shared.start()
            if startRes.success {
                print("\(green)routun service is running with profile '\(selected.id)'.\(reset)")
            } else {
                print("\(red)Failed to restart service: \(startRes.message)\(reset)")
            }
        } else if wasRunning {
            if isRoot {
                print("\nRestarting service to apply '\(selected.id)'...")
                restart()
            } else {
                print("\nTo apply '\(selected.id)', restart the service: \(bold)sudo routun restart\(reset)")
            }
        }
    }

    public static func profile(action: String?, name: String?) {
        let config = RoutunConfig.load()
        let activeProfileId = config.selectedProfile ?? "default"

        switch action?.lowercased() {
        case "list":
            let showAll = (name == "--all" || name == "-a")
            let profilesToList = showAll ? StrategyProfiles.all : StrategyProfiles.canonical
            let title = showAll ? "All Supported Parameter Combinations (\(StrategyProfiles.all.count)):" : "Curated ByeDPI Strategy Profiles:"

            print("\(bold)\(title)\(reset)")
            print("------------------------------------------------------------")
            for p in profilesToList {
                let isCurrent = (p.id == activeProfileId)
                let marker = isCurrent ? "\(green)* (active)\(reset)" : "          "
                let namePadded = p.id.padding(toLength: 26, withPad: " ", startingAt: 0)
                print("  \(marker) \(bold)\(namePadded)\(reset) [\(p.family)] - \(p.description)")
                print("                            Args: \(p.args.joined(separator: " "))")
            }
            print("------------------------------------------------------------")
            if !showAll {
                print("Tip: Use '\(bold)routun profile list --all\(reset)' to inspect all \(StrategyProfiles.all.count) combinations.")
            }
            print("To switch profile: \(bold)routun profile set <name>\(reset)")

        case "set":
            guard let targetName = name, !targetName.isEmpty else {
                print("\(red)Error:\(reset) Please specify a profile name. Run '\(bold)routun profile list\(reset)' to view options.")
                exit(1)
            }
            guard let p = StrategyProfiles.find(by: targetName) else {
                print("\(red)Error:\(reset) Unknown profile '\(targetName)'.")
                print("Run '\(bold)routun profile list\(reset)' to see all supported profiles.")
                exit(1)
            }

            if StrategyOptimizer.saveProfile(p) {
                print("\(green)Switched active strategy profile to '\(p.id)' (\(p.name)).\(reset)")
                print("  Parameters: \(p.args.joined(separator: " "))")
                print("  Saved to:   \(RoutunConfig.defaultConfigFile)")

                let state = ServiceManager.shared.getStatus()
                if state.isRunning {
                    if geteuid() == 0 {
                        print("\nRestarting service...")
                        restart()
                    } else {
                        print("\nTo apply changes, restart the service: \(bold)sudo routun restart\(reset)")
                    }
                }
            } else {
                print("\(red)Error:\(reset) Could not write to \(RoutunConfig.defaultConfigFile). Run with sudo if permission denied.")
                exit(1)
            }

        case "show", nil:
            let p = StrategyProfiles.find(by: activeProfileId) ?? StrategyProfiles.defaultProfile
            print("\(bold)Active Strategy Profile:\(reset) \(green)\(p.id)\(reset) (\(p.name))")
            print("  Description: \(p.description)")
            print("  Parameters:  \(config.ciadpiArgs.joined(separator: " "))")
            print("  Config File: \(RoutunConfig.defaultConfigFile)")
            print("\nUse '\(bold)routun profile list\(reset)' to view all profiles or '\(bold)routun optimize\(reset)' to auto-detect.")

        default:
            print("\(red)Error:\(reset) Unknown profile action '\(action!)'. Use 'list', 'set <name>', or 'show'.")
            exit(1)
        }
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
