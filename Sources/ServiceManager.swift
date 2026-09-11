import Foundation

public struct ServiceState {
    public let isLoaded: Bool
    public let isRunning: Bool
    public let supervisorPid: Int?
    public let ciadpiPid: Int?
    public let singboxPid: Int?
    public let startedAt: String?
}

public final class ServiceManager {
    public static let shared = ServiceManager()

    public func getStatus() -> ServiceState {
        var isLoaded = false
        var output = ""
        let candidateLabels = [
            RoutunConfig.serviceLabel,
            "sh.brew.routun",
            "homebrew.mxcl.routun",
            "com.routun.routund",
            "com.routun.daemon"
        ]
        for label in candidateLabels {
            let (code, out) = runCommand("/bin/launchctl", ["print", "system/\(label)"])
            if code == 0 {
                isLoaded = true
                output = out
                break
            }
        }
        var isRunning = false
        var supervisorPid: Int?
        var ciadpiPid: Int?
        var singboxPid: Int?
        var startedAt: String?

        if isLoaded {
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("pid = ") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count == 2, let pid = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                        supervisorPid = pid
                        isRunning = true
                    }
                }
            }
        }

        if FileManager.default.fileExists(atPath: RoutunConfig.pidFile),
           let data = try? Data(contentsOf: URL(fileURLWithPath: RoutunConfig.pidFile)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let supPid = json["supervisor_pid"] as? Int {
                supervisorPid = supPid
            }
            if let cPid = json["ciadpi_pid"] as? Int {
                ciadpiPid = cPid
            }
            if let sPid = json["singbox_pid"] as? Int {
                singboxPid = sPid
            }
            if let started = json["started_at"] as? String {
                startedAt = started
            }
            if supervisorPid != nil {
                isRunning = true
            }
        }

        return ServiceState(
            isLoaded: isLoaded,
            isRunning: isRunning,
            supervisorPid: supervisorPid,
            ciadpiPid: ciadpiPid,
            singboxPid: singboxPid,
            startedAt: startedAt
        )
    }

    public func installLaunchDaemonPlist(at path: String) {
        let binPath = RoutunConfig.executableBinaryPath
        let label = RoutunConfig.serviceLabel
        let logPath = RoutunConfig.daemonLogFile
        let errPath = RoutunConfig.daemonErrFile

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binPath)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(errPath)</string>
            <key>ProcessType</key>
            <string>Standard</string>
        </dict>
        </plist>
        """

        try? plistContent.write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o644)
    }

    public func start() -> (success: Bool, message: String) {
        let plistPath = RoutunConfig.launchDaemonPlist
        if !FileManager.default.fileExists(atPath: plistPath) {
            installLaunchDaemonPlist(at: plistPath)
        }

        // Bootstrap service into launchd system domain
        let (bCode, bOut) = runCommand("/bin/launchctl", ["bootstrap", "system", plistPath])
        let alreadyLoaded = bOut.contains("service already bootstrapped") || bOut.contains("Already loaded") || bCode == 5 || bCode == 37

        if bCode != 0 && !alreadyLoaded {
            let (lCode, lOut) = runCommand("/bin/launchctl", ["load", "-w", plistPath])
            if lCode != 0 && !lOut.contains("Already loaded") {
                return (false, "launchctl bootstrap failed: \(bOut.isEmpty ? lOut : bOut)")
            }
        }

        // Kickstart the service
        _ = runCommand("/bin/launchctl", ["kickstart", "-k", "system/\(RoutunConfig.serviceLabel)"])

        // Verify service loaded
        for _ in 0..<20 {
            let (pCode, _) = runCommand("/bin/launchctl", ["print", "system/\(RoutunConfig.serviceLabel)"])
            if pCode == 0 {
                return (true, "Service started via launchd.")
            }
            usleep(100_000) // 100ms
        }

        return (false, "Service was not registered in launchd. Check 'routun logs' or 'routun doctor'.")
    }

    public func stop() -> (success: Bool, message: String) {
        let candidateLabels = [
            RoutunConfig.serviceLabel,
            "sh.brew.routun",
            "homebrew.mxcl.routun",
            "com.routun.routund",
            "com.routun.daemon"
        ]
        for label in candidateLabels {
            _ = runCommand("/bin/launchctl", ["bootout", "system/\(label)"])
        }
        if let plist = RoutunConfig.installedPlistPath {
            _ = runCommand("/bin/launchctl", ["unload", plist])
        }

        // Stop any standalone background processes gracefully
        _ = runCommand("/usr/bin/killall", ["-TERM", "sing-box"])
        _ = runCommand("/usr/bin/killall", ["-TERM", "ciadpi"])
        _ = runCommand("/sbin/ifconfig", ["utun10", "down"])

        try? FileManager.default.removeItem(atPath: RoutunConfig.pidFile)

        // Wait until service is completely unloaded from system domain
        for _ in 0..<20 {
            let (pCode, _) = runCommand("/bin/launchctl", ["print", "system/\(RoutunConfig.serviceLabel)"])
            if pCode != 0 {
                return (true, "Service stopped via launchd.")
            }
            usleep(100_000) // 100ms
        }

        return (true, "Service stopped via launchd.")
    }

    public func restart() -> (success: Bool, message: String) {
        _ = stop()
        usleep(300_000) // 300ms buffer for kernel interface release
        let startRes = start()
        if !startRes.success {
            return (false, "Failed to restart: \(startRes.message)")
        }
        return (true, "Service restarted successfully.")
    }

    @discardableResult
    public func runCommand(_ executable: String, _ arguments: [String]) -> (code: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (proc.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
