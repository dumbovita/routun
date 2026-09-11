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

    public init(config: RoutunConfig = RoutunConfig.load()) {
        self.config = config
    }

    public func run() {
        guard geteuid() == 0 else {
            logger.error("routun daemon requires root privileges (uid 0) to manage network TUN routing.")
            exit(1)
        }

        logger.info("Initializing routun background service supervisor...")

        applyResourceLimits()
        verifyBinariesAndConfig()
        cleanupStaleProcesses()
        cleanupStalePidFile()
        setupSignalHandlers()

        startCiadpi()
        waitForSocksPort()
        startSingbox()
        verifyTunInterface()

        writePidFile()
        logger.info("routun service active: ciadpi (PID \(ciadpiProcess?.processIdentifier ?? 0)), sing-box (PID \(singboxProcess?.processIdentifier ?? 0)).")

        dispatchMain()
    }

    private func applyResourceLimits() {
        var rlp = rlimit(rlim_cur: 10240, rlim_max: 10240)
        if setrlimit(RLIMIT_NOFILE, &rlp) != 0 {
            logger.warn("Unable to set RLIMIT_NOFILE to 10240: \(String(cString: strerror(errno)))")
        } else {
            logger.info("Configured socket file descriptor limit: RLIMIT_NOFILE = 10240.")
        }
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
    }

    private func cleanupStaleProcesses() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        var pidsToClean = [pid_t]()

        for name in ["ciadpi", "sing-box"] {
            let (code, out) = ServiceManager.shared.runCommand("/usr/bin/pgrep", ["-x", name])
            if code == 0 && !out.isEmpty {
                for line in out.components(separatedBy: .newlines) {
                    if let pid = pid_t(line.trimmingCharacters(in: .whitespaces)), pid != myPid {
                        pidsToClean.append(pid)
                    }
                }
            }
        }

        if !pidsToClean.isEmpty {
            logger.warn("Cleaning up \(pidsToClean.count) lingering unmanaged process(es) before startup...")
            for pid in pidsToClean {
                kill(pid, SIGTERM)
            }

            for _ in 0..<15 {
                let alive = pidsToClean.filter { kill($0, 0) == 0 }
                if alive.isEmpty { break }
                usleep(100_000) // 100ms
            }

            for pid in pidsToClean {
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                }
            }

            // Allow kernel virtual interfaces and sockets to release
            usleep(300_000)
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
            try proc.run()
            self.ciadpiProcess = proc
            logger.info("ByeDPI spawned successfully (PID: \(proc.processIdentifier)).")
        } catch {
            logger.error("Failed to execute ByeDPI: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func waitForSocksPort() {
        logger.info("Probing ByeDPI SOCKS5 port at \(config.socksHost):\(config.socksPort)...")
        let maxAttempts = 30
        for i in 1...maxAttempts {
            guard let proc = ciadpiProcess, proc.isRunning else {
                logger.error("ByeDPI exited prematurely before opening SOCKS5 port.")
                exit(1)
            }

            if NetUtils.isPortOpen(host: config.socksHost, port: config.socksPort, timeout: 0.1) {
                logger.info("ByeDPI port \(config.socksPort) confirmed ready (probe \(i)).")
                return
            }
            usleep(100_000) // 100ms
        }

        logger.error("Timed out waiting for ByeDPI socket on \(config.socksHost):\(config.socksPort).")
        ciadpiProcess?.terminate()
        exit(1)
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
            try proc.run()
            self.singboxProcess = proc
            logger.info("sing-box spawned successfully (PID: \(proc.processIdentifier)).")
        } catch {
            logger.error("Failed to execute sing-box: \(error.localizedDescription)")
            ciadpiProcess?.terminate()
            exit(1)
        }
    }

    private func verifyTunInterface() {
        usleep(350_000) // 350ms for utun allocation and route table hook

        guard let singbox = singboxProcess, singbox.isRunning else {
            logger.error("sing-box exited immediately after startup. Check logs for configuration or permission errors.")
            emergencyTeardown()
            return
        }

        let (exists, isUp, ip) = NetUtils.getInterfaceInfo(name: config.tunInterface)
        if exists && isUp {
            logger.info("Interface \(config.tunInterface) verified active (IP: \(ip ?? "assigned")).")
        } else {
            logger.warn("Interface \(config.tunInterface) not yet reported UP, but sing-box process is healthy.")
        }
    }

    private func writePidFile() {
        let state: [String: Any] = [
            "supervisor_pid": ProcessInfo.processInfo.processIdentifier,
            "ciadpi_pid": ciadpiProcess?.processIdentifier ?? 0,
            "singbox_pid": singboxProcess?.processIdentifier ?? 0,
            "started_at": ISO8601DateFormatter().string(from: Date()),
            "tun_interface": config.tunInterface,
            "socks_port": config.socksPort
        ]

        if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: RoutunConfig.pidFile))
        }
    }

    private func cleanupStalePidFile() {
        try? FileManager.default.removeItem(atPath: RoutunConfig.pidFile)
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

        cleanupStalePidFile()
        logger.error("Emergency teardown finished. Exiting with failure status for launchd supervisor restart.")
        exit(1)
    }

    private func handleShutdown(signalName: String) {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        logger.info("Received \(signalName). Performing graceful shutdown sequence...")

        // Step 1: Terminate sing-box first. This destroys utun10 and restores native macOS routing.
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

        cleanupStalePidFile()
        logger.info("routun service stopped cleanly.")
        exit(0)
    }

    private func terminateAndWait(process: Process, timeoutSeconds: TimeInterval, name: String) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }

        process.terminate() // sends SIGTERM

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
