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
        print("  LaunchDaemon:    \(daemonStatusStr)")
        let payloadVersion = ServiceManager.shared.installedPayloadVersion() ?? "not installed"
        let updateTag = payloadVersion == version ? "" : " \(yellow)[run sudo routun install to sync]\(reset)"
        print("  Service payload: \(payloadVersion)\(updateTag)")

        if state.isRunning, let sPid = state.supervisorPid, NetUtils.isProcessAlive(pid: sPid) {
            let startedStr = state.startedAt != nil ? " since \(state.startedAt!)" : ""
            print("  Supervisor:      \(green)active (running)\(reset) [PID \(sPid)]\(startedStr)")
        } else if state.isLoaded {
            print("  Supervisor:      \(yellow)starting or restarting\(reset)")
        } else {
            print("  Supervisor:      \(red)inactive (stopped)\(reset)")
        }

        let socksOpen = NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.3)
        var ciadpiStatus = "not running"
        if let cPid = state.ciadpiPid, NetUtils.isProcessAlive(pid: cPid) {
            ciadpiStatus = "PID \(cPid) (managed)"
        }
        let portStatus = socksOpen ? "\(green)listening on \(config.socksHost):\(config.socksPort)\(reset)" : "\(red)port \(config.socksPort) closed\(reset)"
        print("  ByeDPI:          \(ciadpiStatus) (\(portStatus))")
        let activeProfile = config.selectedProfile ?? "default"
        print("  Strategy:        \(bold)\(activeProfile)\(reset) (\(StrategyProfiles.find(by: activeProfile)?.name ?? "Custom"))")

        // Routing Policy
        let policy = config.routePolicy
        let modeDesc = policy.mode == .selective ? "\(green)selective\(reset) (targeted services)" : "\(yellow)global\(reset) (all TCP 80/443)"
        print("  Routing Mode:    \(modeDesc)")
        let quicDesc = policy.quicMode == .scoped ? "scoped (bypassed services only)" : policy.quicMode.rawValue
        print("  QUIC (UDP/443):  \(quicDesc)")

        let activeGroups = ServiceGroupCatalog.builtInGroups.filter { policy.isGroupEnabled($0) }
        let groupNames = activeGroups.map(\.id).joined(separator: ", ")
        print("  Active Groups:   \(groupNames.isEmpty ? "none" : groupNames)")
        if !policy.customInclude.isEmpty {
            print("  Custom Includes: \(policy.customInclude.count) domain(s)")
        }
        if !policy.customExclude.isEmpty {
            print("  Custom Excludes: \(policy.customExclude.count) domain(s)")
        }

        let tunInterface = state.tunInterface?.isEmpty == false
            ? state.tunInterface
            : state.isLoaded ? NetUtils.tunInterface() : nil
        let tunInfo = tunInterface.map(NetUtils.getInterfaceInfo) ?? (false, false, nil, nil)
        var singboxStatus = "not running"
        if let sPid = state.singboxPid, NetUtils.isProcessAlive(pid: sPid) {
            singboxStatus = "PID \(sPid) (managed)"
        }

        var ipDescParts = [String]()
        if let ip4 = tunInfo.2 { ipDescParts.append("IPv4: \(ip4)") }
        if let ip6 = tunInfo.3 { ipDescParts.append("IPv6: \(ip6)") }
        let ipDesc = ipDescParts.isEmpty ? "active" : ipDescParts.joined(separator: ", ")

        let tunStatus = tunInfo.0 && tunInfo.1
            ? "\(green)\(tunInterface ?? "utun") UP\(reset) (\(ipDesc))"
            : "\(red)no routun TUN interface\(reset)"
        print("  sing-box:        \(singboxStatus) (\(tunStatus))")
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
        let (code, _) = ServiceManager.shared.runCommand("/usr/bin/which", ["log"])
        guard code == 0 else {
            print("\(red)Error:\(reset) /usr/bin/log utility is not available on this macOS system.")
            exit(1)
        }

        var cmdArgs = [
            "log", "show",
            "--predicate", "subsystem == \"com.routun.routund\" || process == \"routund\"",
            "--style", "compact",
            "--info"
        ]

        if errorOnly {
            cmdArgs += ["--predicate", "(subsystem == \"com.routun.routund\" || process == \"routund\") && messageType >= 16"]
        }

        if follow {
            cmdArgs[1] = "stream"
            print("\(cyan)Streaming live logs from routund (Ctrl+C to stop)...\(reset)")
        } else {
            cmdArgs += ["--last", "\(lines)m"]
            print("\(cyan)Showing routund logs from last \(lines) minutes:\(reset)")
        }

        let cArgs = cmdArgs.map { strdup($0) } + [nil]
        execvp("/usr/bin/log", cArgs)
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

        // ByeDPI & Darwin capabilities
        if fm.isExecutableFile(atPath: config.ciadpiPath) {
            let cap = ByeDPICapability.detect(ciadpiPath: config.ciadpiPath)
            print("  ByeDPI Path:    \(green)OK\(reset) (\(config.ciadpiPath))")
            print("  Darwin Engine:  \(green)Split (-s), Disorder (-d), OOB (-o), DISOOB (-q), TLS-Record (-r), Auto-Detect (-A), HTTP-Mod (-M)\(reset)")
            if !cap.supportsFakePackets {
                print("  Fake Packets:   \(cyan)Disabled on macOS build (Linux/Win only; -t/-Q are inert for TCP)\(reset)")
            }
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

        // sing-box config validation
        if fm.fileExists(atPath: config.singboxConfig) {
            if fm.isExecutableFile(atPath: config.singboxPath) {
                let (cCode, cOut) = ServiceManager.shared.runCommand(config.singboxPath, ["check", "-c", config.singboxConfig])
                if cCode == 0 {
                    print("  sing-box Conf:  \(green)VALID SYNTAX\(reset) (\(config.singboxConfig))")
                } else {
                    print("  sing-box Conf:  \(red)INVALID SYNTAX\(reset) - \(cOut)")
                }
            } else {
                print("  sing-box Conf:  \(green)PRESENT\(reset) (\(config.singboxConfig))")
            }
        } else {
            print("  sing-box Conf:  \(red)MISSING\(reset) at \(config.singboxConfig)")
        }

        // Active Route Policy
        let policy = config.routePolicy
        let (bypassed, excluded) = policy.resolveTargets()
        print("  Route Policy:   mode=\(policy.mode.rawValue), quic=\(policy.quicMode.rawValue), ipv6=\(policy.enableIPv6)")
        print("  Targets:        \(bypassed.count) bypassed domain pattern(s), \(excluded.count) explicit exclusion(s)")

        let state = ServiceManager.shared.getStatus()
        if fm.fileExists(atPath: RoutunConfig.launchDaemonPlist) {
            let loadedTag = state.isLoaded ? " [\(green)LOADED\(reset)]" : " [\(yellow)NOT LOADED\(reset)]"
            print("  LaunchDaemon:   \(green)INSTALLED\(reset) (\(RoutunConfig.launchDaemonPlist))\(loadedTag)")
        } else {
            print("  LaunchDaemon:   \(yellow)NOT INSTALLED\(reset)")
        }

        // Sockets
        let portBusy = NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.2)
        print("  Port 1080:      \(portBusy ? "\(cyan)OCCUPIED / LISTENING\(reset)" : "\(green)AVAILABLE\(reset)")")

        // TUN interface
        let activeInterface = state.tunInterface?.isEmpty == false
            ? state.tunInterface
            : state.isLoaded ? NetUtils.tunInterface() : nil
        if let activeInterface {
            let tunInfo = NetUtils.getInterfaceInfo(name: activeInterface)
            var addrs = [String]()
            if let ip = tunInfo.2 { addrs.append("IPv4: \(ip)") }
            if let ip6 = tunInfo.3 { addrs.append("IPv6: \(ip6)") }
            let addrStr = addrs.isEmpty ? "UP" : addrs.joined(separator: ", ")
            print("  Interface \(activeInterface): \(tunInfo.1 ? "\(green)UP\(reset) (\(addrStr))" : "\(yellow)DOWN\(reset)")")
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

        if state.isRunning && !isRoot {
            print("\(yellow)Notice:\(reset) The routun DPI service is currently active.")
            print("To eliminate DPI routing interference during optimization, the service will be temporarily paused.")

            if isatty(STDIN_FILENO) != 0 {
                print("Re-running with sudo...\n")
                let execPath = RoutunConfig.currentExecutablePath()
                var args = CommandLine.arguments
                args[0] = execPath
                args.insert("/usr/bin/sudo", at: 0)
                let cArgs = args.map { strdup($0) } + [nil]
                execv("/usr/bin/sudo", cArgs)
            }

            print("\(red)Error:\(reset) Please re-run with sudo: \(bold)sudo routun optimize\(reset)")
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
            let title = showAll
                ? "All Supported macOS Parameter Combinations (\(StrategyProfiles.all.count)):"
                : "Curated macOS ByeDPI Strategy Profiles (\(StrategyProfiles.canonical.count)):"

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
                print("Tip: Use '\(bold)routun profile list --all\(reset)' to inspect all \(StrategyProfiles.all.count) macOS combinations.")
            }
            print("To switch profile: \(bold)routun profile set <name>\(reset)")

        case "set":
            guard ensureRoot() else { exit(1) }
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
                    print("\nRestarting service to apply profile...")
                    restart()
                }
            } else {
                print("\(red)Error:\(reset) Could not write to \(RoutunConfig.defaultConfigFile).")
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

    public static func group(action: String?, name: String?) {
        var config = RoutunConfig.load()
        let policy = config.routePolicy

        switch action?.lowercased() {
        case "list", nil:
            print("\(bold)Built-in Service Groups (\(ServiceGroupCatalog.builtInGroups.count)):\(reset)")
            print("------------------------------------------------------------")
            for group in ServiceGroupCatalog.builtInGroups {
                let enabled = policy.isGroupEnabled(group)
                let statusTag = enabled ? "\(green)enabled \(reset)" : "\(yellow)disabled\(reset)"
                let paddedId = group.id.padding(toLength: 14, withPad: " ", startingAt: 0)
                let count = group.domainSuffixes.count
                print("  [\(statusTag)] \(bold)\(paddedId)\(reset) (\(count) suffixes) - \(group.description)")
            }
            print("------------------------------------------------------------")
            print("To enable a group:  \(bold)routun group enable <name>\(reset)")
            print("To disable a group: \(bold)routun group disable <name>\(reset)")

        case "enable":
            guard let groupId = name?.lowercased(), !groupId.isEmpty else {
                print("\(red)Error:\(reset) Please specify a group name to enable.")
                exit(1)
            }
            guard let group = ServiceGroupCatalog.find(byId: groupId) else {
                print("\(red)Error:\(reset) Unknown group '\(groupId)'. Available groups: \(ServiceGroupCatalog.builtInGroups.map(\.id).joined(separator: ", "))")
                exit(1)
            }

            config.groupPreferences[group.id] = true
            applyConfigUpdate(&config, message: "Enabled group '\(group.id)' (\(group.name)).")

        case "disable":
            guard let groupId = name?.lowercased(), !groupId.isEmpty else {
                print("\(red)Error:\(reset) Please specify a group name to disable.")
                exit(1)
            }
            guard let group = ServiceGroupCatalog.find(byId: groupId) else {
                print("\(red)Error:\(reset) Unknown group '\(groupId)'. Available groups: \(ServiceGroupCatalog.builtInGroups.map(\.id).joined(separator: ", "))")
                exit(1)
            }

            config.groupPreferences[group.id] = false
            applyConfigUpdate(&config, message: "Disabled group '\(group.id)' (\(group.name)).")

        default:
            print("\(red)Error:\(reset) Unknown group action '\(action!)'. Use 'list', 'enable <name>', or 'disable <name>'.")
            exit(1)
        }
    }

    public static func policy(action: String?, subAction: String?, value: String?) {
        var config = RoutunConfig.load()
        let policy = config.routePolicy

        switch action?.lowercased() {
        case "show", nil:
            print("\(bold)Active Route Policy:\(reset)")
            print("------------------------------------------------------------")
            print("  Routing Mode:    \(bold)\(policy.mode.rawValue)\(reset) (selective vs global)")
            print("  QUIC Mode:       \(bold)\(policy.quicMode.rawValue)\(reset) (scoped UDP/443 rejection)")
            print("  DNS Mode:        \(bold)\(policy.dnsMode.rawValue)\(reset)")
            print("  IPv6 Intercept:  \(policy.enableIPv6 ? "enabled" : "disabled")")
            let (bypassed, _) = policy.resolveTargets()
            print("  Bypassed Suffixes: \(bypassed.count) total")
            if !policy.customInclude.isEmpty {
                print("  Custom Includes: \(policy.customInclude.joined(separator: ", "))")
            }
            if !policy.customExclude.isEmpty {
                print("  Custom Excludes: \(policy.customExclude.joined(separator: ", "))")
            }
            print("------------------------------------------------------------")
            print("Usage:")
            print("  routun policy mode <selective|global>")
            print("  routun policy quic <scoped|blocked|direct>")
            print("  routun policy include <domain>")
            print("  routun policy exclude <domain>")
            print("  routun policy remove <include|exclude> <domain>")

        case "mode":
            guard let modeStr = subAction?.lowercased(), let mode = RoutingMode(rawValue: modeStr) else {
                print("\(red)Error:\(reset) Invalid mode. Choose 'selective' or 'global'.")
                exit(1)
            }
            config.routingMode = mode
            applyConfigUpdate(&config, message: "Routing mode changed to '\(mode.rawValue)'.")

        case "quic":
            guard let quicStr = subAction?.lowercased(), let quic = QUICMode(rawValue: quicStr) else {
                print("\(red)Error:\(reset) Invalid QUIC mode. Choose 'scoped', 'blocked', or 'direct'.")
                exit(1)
            }
            config.quicMode = quic
            applyConfigUpdate(&config, message: "QUIC mode changed to '\(quic.rawValue)'.")

        case "include":
            guard let raw = subAction, let domain = ServiceGroupCatalog.normalizeDomain(raw) else {
                print("\(red)Error:\(reset) Invalid domain to include.")
                exit(1)
            }
            var inc = Set(config.customInclude)
            inc.insert(domain)
            config.customInclude = Array(inc).sorted()
            applyConfigUpdate(&config, message: "Added '\(domain)' to custom inclusions.")

        case "exclude":
            guard let raw = subAction, let domain = ServiceGroupCatalog.normalizeDomain(raw) else {
                print("\(red)Error:\(reset) Invalid domain to exclude.")
                exit(1)
            }
            var exc = Set(config.customExclude)
            exc.insert(domain)
            config.customExclude = Array(exc).sorted()
            applyConfigUpdate(&config, message: "Added '\(domain)' to custom exclusions.")

        case "remove":
            let targetType = subAction?.lowercased()
            guard let raw = value, let domain = ServiceGroupCatalog.normalizeDomain(raw) else {
                print("\(red)Error:\(reset) Usage: routun policy remove <include|exclude> <domain>")
                exit(1)
            }
            if targetType == "include" {
                config.customInclude.removeAll { $0 == domain }
                applyConfigUpdate(&config, message: "Removed '\(domain)' from custom inclusions.")
            } else if targetType == "exclude" {
                config.customExclude.removeAll { $0 == domain }
                applyConfigUpdate(&config, message: "Removed '\(domain)' from custom exclusions.")
            } else {
                print("\(red)Error:\(reset) Unknown removal type '\(subAction ?? "")'. Choose 'include' or 'exclude'.")
                exit(1)
            }

        default:
            print("\(red)Error:\(reset) Unknown policy command '\(action!)'. Run 'routun policy show'.")
            exit(1)
        }
    }

    private static func applyConfigUpdate(_ config: inout RoutunConfig, message: String) {
        guard ensureRoot() else { exit(1) }
        do {
            try config.save()
            try ServiceManager.shared.syncSingboxConfig(from: config)
            print("\(green)\(message)\(reset)")

            let state = ServiceManager.shared.getStatus()
            if state.isRunning {
                print("Restarting service to apply configuration...")
                restart()
            }
        } catch {
            print("\(red)Error saving configuration:\(reset) \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func ensureRoot() -> Bool {
        if geteuid() == 0 { return true }

        if isatty(STDIN_FILENO) != 0 {
            var args = CommandLine.arguments
            let execPath = RoutunConfig.currentExecutablePath()
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
