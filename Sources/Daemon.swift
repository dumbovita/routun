import Foundation
import Darwin
import os

public final class RoutunDaemon {
    private let config: RoutunConfig
    private let logger = RoutunLogger.shared
    private var ciadpiProcess: Process?
    private var singboxProcess: Process?
    private var isShuttingDown = false
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?
    private var appWatcher: DispatchSourceFileSystemObject?

    public init(config: RoutunConfig = RoutunConfig.daemonConfiguration()) {
        self.config = config
    }

    public func run() {
        guard geteuid() == 0 else {
            logger.error("routun daemon requires root privileges (uid 0) to manage network TUN routing.")
            exit(1)
        }

        logger.info("Initializing routun background service supervisor...")

        do {
            try ServiceManager.shared.syncSingboxConfig(from: config)
        } catch {
            logger.error("Failed to synchronize sing-box configuration: \(error.localizedDescription)")
            exit(1)
        }

        verifyBinariesAndConfig()
        cleanupStaleProcesses()
        cleanupStaleStateFile()
        setupSignalHandlers()

        startCiadpi()
        waitForSocksPort()
        startSingbox()
        verifyTunInterface()

        DiscordPatcher.autoPatchIfNeeded(config: config)
        appWatcher = DiscordPatcher.startApplicationsFolderWatcher(config: config)

        writePidFile()
        logger.info("routun service active: ciadpi (PID \(ciadpiProcess?.processIdentifier ?? 0)), sing-box (PID \(singboxProcess?.processIdentifier ?? 0)).")

        dispatchMain()
    }

    private func verifyBinariesAndConfig() {
        let fm = FileManager.default

        guard fm.isExecutableFile(atPath: config.ciadpiPath) else {
            logger.error("ByeDPI binary missing or not executable at: \(config.ciadpiPath)")
            exit(1)
        }

        guard fm.isExecutableFile(atPath: config.singboxPath) else {
            logger.error("sing-box binary missing or not executable at: \(config.singboxPath)")
            exit(1)
        }

        guard fm.fileExists(atPath: config.singboxConfig) else {
            logger.error("sing-box configuration file missing at: \(config.singboxConfig)")
            exit(1)
        }

        let cap = ByeDPICapability.detect(ciadpiPath: config.ciadpiPath)
        let (profileValid, reasons) = cap.validate(args: config.ciadpiArgs)
        if !profileValid {
            logger.warn("ByeDPI configuration contains flags that may be unsupported or inert on macOS: \(reasons.joined(separator: " "))")
        }

        let (checkCode, checkOutput) = ServiceManager.shared.runCommand(
            config.singboxPath,
            ["check", "-c", config.singboxConfig]
        )
        guard checkCode == 0 else {
            logger.error("sing-box configuration check failed: \(checkOutput)")
            exit(1)
        }
    }

    private func cleanupStaleProcesses() {
        let terminated = ServiceManager.shared.terminateRecordedChildren()
        if terminated > 0 {
            logger.warn("Stopped \(terminated) child process(es) recorded by the previous routun service.")
            if !NetUtils.waitForPortToClose(host: config.socksHost, port: config.socksPort, timeout: 1.0) {
                logger.warn("Port \(config.socksPort) remained occupied after terminating previous children.")
            }
        }
    }

    private func setupSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler { [weak self] in
            self?.handleShutdown(signalName: "SIGTERM")
        }
        termSource.resume()
        self.sigtermSource = termSource

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            self?.handleShutdown(signalName: "SIGINT")
        }
        intSource.resume()
        self.sigintSource = intSource
    }

    private func startCiadpi() {
        logger.info("Starting ByeDPI (ciadpi): \(config.ciadpiArgs.joined(separator: " "))")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.ciadpiPath)
        proc.arguments = config.ciadpiArgs

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.handleChildExit(process: p, name: "ByeDPI")
            }
        }

        do {
            try runChild(proc)
            self.ciadpiProcess = proc
            logger.info("ByeDPI spawned successfully (PID: \(proc.processIdentifier)).")
        } catch {
            logger.error("Failed to execute ByeDPI: \(error.localizedDescription)")
            emergencyTeardown()
        }
    }

    private func waitForSocksPort() {
        logger.info("Probing ByeDPI SOCKS5 port at \(config.socksHost):\(config.socksPort)...")
        let maxAttempts = 30
        for i in 1...maxAttempts {
            guard let proc = ciadpiProcess, proc.isRunning else {
                logger.error("ByeDPI exited prematurely before opening SOCKS5 port.")
                emergencyTeardown()
                return
            }

            if NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.1) {
                if proc.isRunning {
                    logger.info("ByeDPI port \(config.socksPort) confirmed ready (probe \(i)).")
                    return
                }
                logger.error("ByeDPI exited while its SOCKS5 port was being verified.")
                emergencyTeardown()
                return
            }
            usleep(100_000) // 100ms
        }

        logger.error("Timed out waiting for ByeDPI socket on \(config.socksHost):\(config.socksPort).")
        emergencyTeardown()
    }

    private func startSingbox() {
        logger.info("Starting sing-box with config: \(config.singboxConfig)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.singboxPath)
        proc.arguments = ["run", "-c", config.singboxConfig]

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.handleChildExit(process: p, name: "sing-box")
            }
        }

        do {
            try runChild(proc)
            self.singboxProcess = proc
            logger.info("sing-box spawned successfully (PID: \(proc.processIdentifier)).")
        } catch {
            logger.error("Failed to execute sing-box: \(error.localizedDescription)")
            emergencyTeardown()
        }
    }

    private func verifyTunInterface() {
        guard let singbox = singboxProcess, singbox.isRunning else {
            logger.error("sing-box exited immediately after startup. Check logs for configuration or permission errors.")
            emergencyTeardown()
            return
        }

        logger.info("Waiting for routun TUN interface to become active...")
        var activeInterface: String? = nil
        var activeIp: String? = nil
        var activeIPv6: String? = nil

        for _ in 1...50 {
            guard let sb = singboxProcess, sb.isRunning else {
                logger.error("sing-box terminated while waiting for TUN interface.")
                emergencyTeardown()
                return
            }

            if let interface = NetUtils.tunInterface() {
                let (_, isUp, ip, ipv6) = NetUtils.getInterfaceInfo(name: interface)
                if isUp {
                    activeInterface = interface
                    activeIp = ip
                    activeIPv6 = ipv6
                    break
                }
            }
            usleep(100_000) // 100ms
        }

        guard let interface = activeInterface else {
            logger.error("Timed out waiting for routun TUN interface to report UP. Emergency teardown initiated.")
            emergencyTeardown()
            return
        }

        let ipv4Desc = activeIp != nil ? "IPv4: \(activeIp!)" : "IPv4 active"
        let ipv6Desc = activeIPv6 != nil ? ", IPv6: \(activeIPv6!)" : ""
        logger.info("TUN interface \(interface) confirmed UP (\(ipv4Desc)\(ipv6Desc)).")
    }

    private func runChild(_ process: Process) throws {
        signal(SIGTERM, SIG_DFL)
        signal(SIGINT, SIG_DFL)
        defer {
            signal(SIGTERM, SIG_IGN)
            signal(SIGINT, SIG_IGN)
        }
        try process.run()
    }

    private func writePidFile() {
        let tunInterface = NetUtils.tunInterface() ?? ""
        let (_, _, ip, ipv6) = tunInterface.isEmpty ? (false, false, nil, nil) : NetUtils.getInterfaceInfo(name: tunInterface)
        let state: [String: Any] = [
            "supervisor_pid": ProcessInfo.processInfo.processIdentifier,
            "ciadpi_pid": ciadpiProcess?.processIdentifier ?? 0,
            "singbox_pid": singboxProcess?.processIdentifier ?? 0,
            "started_at": ISO8601DateFormatter().string(from: Date()),
            "tun_interface": tunInterface,
            "tun_ipv4": ip ?? "",
            "tun_ipv6": ipv6 ?? "",
            "socks_port": config.socksPort,
            "routing_mode": config.routingMode.rawValue,
            "quic_mode": config.quicMode.rawValue
        ]

        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            do {
                try data.write(to: URL(fileURLWithPath: RoutunConfig.stateFile), options: .atomic)
                chmod(RoutunConfig.stateFile, 0o644)
            } catch {
                logger.warn("Could not write service state: \(error.localizedDescription)")
            }
        }
    }

    private func cleanupStaleStateFile() {
        try? FileManager.default.removeItem(atPath: RoutunConfig.stateFile)
    }

    private func handleChildExit(process: Process, name: String) {
        guard !isShuttingDown else { return }
        logger.error("\(name) exited unexpectedly with status \(process.terminationStatus).")
        emergencyTeardown()
    }

    private func emergencyTeardown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        logger.warn("Initiating emergency teardown to prevent network blackholing...")

        if let singbox = singboxProcess {
            terminateAndWait(process: singbox, timeoutSeconds: 2.0, name: "sing-box")
        }
        if let ciadpi = ciadpiProcess {
            terminateAndWait(process: ciadpi, timeoutSeconds: 1.0, name: "ByeDPI")
        }

        cleanupStaleStateFile()
        logger.error("Emergency teardown finished. Exiting with failure status for launchd supervisor restart.")
        exit(1)
    }

    private func handleShutdown(signalName: String) {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        logger.info("Received \(signalName). Performing graceful shutdown sequence...")

        appWatcher?.cancel()
        appWatcher = nil

        // Terminate sing-box first so its TUN routes are removed before ByeDPI exits.
        if let singbox = singboxProcess {
            logger.info("Stopping sing-box to restore default network routes...")
            terminateAndWait(process: singbox, timeoutSeconds: 3.0, name: "sing-box")
            logger.info("sing-box stopped. Native routing restored.")
        }

        // Step 2: Terminate ciadpi now that network traffic is no longer directed to localhost:1080.
        if let ciadpi = ciadpiProcess {
            logger.info("Stopping ByeDPI...")
            terminateAndWait(process: ciadpi, timeoutSeconds: 1.5, name: "ByeDPI")
            logger.info("ByeDPI stopped.")
        }

        cleanupStaleStateFile()
        logger.info("routun service stopped cleanly.")
        exit(0)
    }

    private func terminateAndWait(process: Process, timeoutSeconds: TimeInterval, name: String) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }

        process.terminate() // sends SIGTERM
        if name == "ByeDPI" {
            kill(pid, SIGHUP)
        }

        let deadlineNs = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutSeconds * 1_000_000_000)
        var status: Int32 = 0

        while true {
            let res = waitpid(pid, &status, WNOHANG)
            if res == pid || res == -1 {
                return
            }
            if DispatchTime.now().uptimeNanoseconds > deadlineNs {
                logger.warn("\(name) (PID \(pid)) did not exit within \(timeoutSeconds)s; sending SIGKILL.")
                kill(pid, SIGKILL)
                waitpid(pid, &status, 0)
                return
            }
            usleep(20_000) // 20ms
        }
    }
}
