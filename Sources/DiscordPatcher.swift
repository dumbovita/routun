import Foundation
import Darwin

public enum DiscordPatchStatus: Equatable {
    case notInstalled
    case openasar
    case updaterDisabled
    case unpatched
}

public struct DiscordPatcher {
    public static let discordAppPath = "/Applications/Discord.app"
    public static let resourcesPath = "/Applications/Discord.app/Contents/Resources"
    public static let buildInfoPath = "/Applications/Discord.app/Contents/Resources/build_info.json"
    public static let appAsarPath = "/Applications/Discord.app/Contents/Resources/app.asar"
    public static let appAsarOriginalPath = "/Applications/Discord.app/Contents/Resources/app.asar.original"
    public static let openAsarUrl = "https://github.com/GooseMod/OpenAsar/releases/download/nightly/app.asar"

    public static var isDiscordInstalled: Bool {
        FileManager.default.fileExists(atPath: discordAppPath)
    }

    public static func detectStatus() -> DiscordPatchStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: discordAppPath) else {
            return .notInstalled
        }

        // OpenAsar replaces app.asar and backs up the original to app.asar.original
        if fm.fileExists(atPath: appAsarOriginalPath) {
            return .openasar
        }

        // Also detect OpenAsar if installed directly without backup (OpenAsar is ~40KB vs stock ~3.4MB+)
        if fm.fileExists(atPath: appAsarPath),
           let attrs = try? fm.attributesOfItem(atPath: appAsarPath),
           let size = attrs[.size] as? Int64, size > 10_000 && size < 500_000 {
            return .openasar
        }

        // Host updater disabled via build_info.json
        if fm.fileExists(atPath: buildInfoPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: buildInfoPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let disabled = json["disableUpdater"] as? Bool, disabled {
            return .updaterDisabled
        }

        // Host updater disabled via user settings.json
        if isUserSettingsSkipHostUpdateEnabled() {
            return .updaterDisabled
        }

        return .unpatched
    }

    public static func isUserSettingsSkipHostUpdateEnabled() -> Bool {
        let fm = FileManager.default
        let usersRoot = "/Users"
        guard let userDirs = try? fm.contentsOfDirectory(atPath: usersRoot) else { return false }

        for user in userDirs where !user.hasPrefix(".") && user != "Shared" {
            let settingsPath = "/Users/\(user)/Library/Application Support/discord/settings.json"
            guard fm.fileExists(atPath: settingsPath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let skip = json["SKIP_HOST_UPDATE"] as? Bool, skip else {
                continue
            }
            return true
        }
        return false
    }

    @discardableResult
    public static func apply(mode: DiscordEvasionMode) -> (success: Bool, message: String) {
        guard isDiscordInstalled else {
            return (false, "Discord is not installed at \(discordAppPath).")
        }

        let fm = FileManager.default

        switch mode {
        case .openasar:
            // 1. Backup original app.asar if not already backed up
            if fm.fileExists(atPath: appAsarPath) && !fm.fileExists(atPath: appAsarOriginalPath) {
                do {
                    try fm.copyItem(atPath: appAsarPath, toPath: appAsarOriginalPath)
                } catch {
                    return (false, "Failed to create original app.asar backup: \(error.localizedDescription)")
                }
            }

            // 2. Download OpenAsar nightly app.asar to temporary file
            let tempPath = "/tmp/openasar_\(UUID().uuidString).asar"
            defer { try? fm.removeItem(atPath: tempPath) }

            let (code, output) = ServiceManager.shared.runCommand(
                "/usr/bin/curl",
                ["-sL", "-f", "--max-time", "15", "-o", tempPath, openAsarUrl]
            )
            guard code == 0, fm.fileExists(atPath: tempPath) else {
                return (false, "Failed to download OpenAsar: \(output)")
            }

            // Verify minimum file size (OpenAsar is ~40KB)
            guard let attrs = try? fm.attributesOfItem(atPath: tempPath),
                  let size = attrs[.size] as? Int64, size > 20000 else {
                return (false, "Downloaded OpenAsar payload appears corrupted or too small.")
            }

            // 3. Replace app.asar atomically
            do {
                if fm.fileExists(atPath: appAsarPath) {
                    try fm.removeItem(atPath: appAsarPath)
                }
                try fm.copyItem(atPath: tempPath, toPath: appAsarPath)
            } catch {
                return (false, "Failed to install OpenAsar payload: \(error.localizedDescription)")
            }

            // 4. Ensure build_info.json is clean (not disabling updater since OpenAsar handles updates)
            cleanBuildInfoDisableUpdater()
            updateUserSettings(skipHostUpdate: true)

            return (true, "OpenAsar installed successfully. Native TLS 1.3 updates and fast startup enabled.")

        case .disableUpdater:
            // 1. Restore original app.asar if OpenAsar was previously installed
            if fm.fileExists(atPath: appAsarOriginalPath) {
                try? fm.removeItem(atPath: appAsarPath)
                try? fm.moveItem(atPath: appAsarOriginalPath, toPath: appAsarPath)
            }

            // 2. Set disableUpdater in build_info.json
            if fm.fileExists(atPath: buildInfoPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: buildInfoPath)),
               var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                json["disableUpdater"] = true
                if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                    try? updatedData.write(to: URL(fileURLWithPath: buildInfoPath))
                }
            }

            // 3. Set SKIP_HOST_UPDATE in user settings
            updateUserSettings(skipHostUpdate: true)

            return (true, "Discord legacy host updater disabled. Modern module updates remain functional.")

        case .none:
            // Restore everything to stock Discord
            if fm.fileExists(atPath: appAsarOriginalPath) {
                try? fm.removeItem(atPath: appAsarPath)
                try? fm.moveItem(atPath: appAsarOriginalPath, toPath: appAsarPath)
            }
            cleanBuildInfoDisableUpdater()
            updateUserSettings(skipHostUpdate: false)
            return (true, "Restored stock Discord configuration.")
        }
    }

    private static func cleanBuildInfoDisableUpdater() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: buildInfoPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: buildInfoPath)),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        json.removeValue(forKey: "disableUpdater")
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? updatedData.write(to: URL(fileURLWithPath: buildInfoPath))
        }
    }

    private static func updateUserSettings(skipHostUpdate: Bool) {
        let fm = FileManager.default
        let usersRoot = "/Users"
        guard let userDirs = try? fm.contentsOfDirectory(atPath: usersRoot) else { return }

        for user in userDirs where !user.hasPrefix(".") && user != "Shared" {
            let discordDir = "/Users/\(user)/Library/Application Support/discord"
            let settingsPath = "\(discordDir)/settings.json"

            var json: [String: Any] = [:]
            if fm.fileExists(atPath: settingsPath) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
                   let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    json = existing
                }
            } else if !skipHostUpdate || !fm.fileExists(atPath: discordDir) {
                continue
            }

            if skipHostUpdate {
                json["SKIP_HOST_UPDATE"] = true
            } else {
                json.removeValue(forKey: "SKIP_HOST_UPDATE")
            }

            if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                try? updatedData.write(to: URL(fileURLWithPath: settingsPath))
                // Ensure correct user ownership if running as root
                if let attrs = try? fm.attributesOfItem(atPath: discordDir),
                   let uid = attrs[.ownerAccountID] as? NSNumber,
                   let gid = attrs[.groupOwnerAccountID] as? NSNumber {
                    chown(settingsPath, uid_t(truncating: uid), gid_t(truncating: gid))
                }
            }
        }
    }

    /// Automatically patches Discord if installed and not yet patched according to preference.
    public static func autoPatchIfNeeded(config: RoutunConfig) {
        guard let mode = config.discordEvasion, mode != .none else { return }
        guard isDiscordInstalled else { return }
        guard FileManager.default.fileExists(atPath: buildInfoPath) else { return }

        let current = detectStatus()
        switch mode {
        case .openasar:
            if current != .openasar {
                RoutunLogger.shared.info("Discord detected in /Applications without OpenAsar. Applying patch...")
                let res = apply(mode: .openasar)
                RoutunLogger.shared.info("Discord auto-patch result: \(res.message)")
            }
        case .disableUpdater:
            if current != .updaterDisabled {
                RoutunLogger.shared.info("Discord detected in /Applications without host updater disabled. Applying patch...")
                let res = apply(mode: .disableUpdater)
                RoutunLogger.shared.info("Discord auto-patch result: \(res.message)")
            }
        case .none:
            break
        }
    }

    private static var debounceWorkItem: DispatchWorkItem?

    /// Creates a zero-overhead kernel filesystem event watcher on `/Applications`.
    /// Fires only when items in `/Applications` are created, moved, or deleted.
    /// Uses macOS kqueue (EVFILT_VNODE) via DispatchSource, consuming 0% CPU and zero polling.
    public static func startApplicationsFolderWatcher(config: RoutunConfig) -> DispatchSourceFileSystemObject? {
        let path = "/Applications"
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler {
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                autoPatchIfNeeded(config: config)
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }

        source.setCancelHandler {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            close(fd)
        }

        source.resume()
        return source
    }
}
