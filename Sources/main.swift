import Foundation

let version = "1.0.0"

func printUsage() {
    print("""
    routun - Transparent TUN-based network routing for macOS (v\(version))

    Usage:
      routun <command> [options]

    Commands:
      status          Show live service status, child PIDs, ports, TUN, and DPI health
      start           Start the routun LaunchDaemon background service (requires sudo)
      stop            Stop the routun LaunchDaemon background service (requires sudo)
      restart         Restart the service and cleanly refresh network routing (requires sudo)
      logs            Display service logs (supports -f/--follow, -n <lines>, -e/--error)
      doctor          Run full system and environment diagnostic checks
      install         Install executable, configs, and LaunchDaemon (requires sudo)
      uninstall       Uninstall service, configs, and revert system routing (requires sudo)
      daemon          Internal: run supervisor daemon in foreground (managed by launchd)
      version         Show routun version
      help            Show this help message

    Examples:
      routun status
      sudo routun start
      sudo routun stop
      sudo routun restart
      routun logs -f
      routun doctor
      sudo routun uninstall
    """)
}

let args = CommandLine.arguments

guard args.count > 1 else {
    RoutunCommands.status()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "status":
    RoutunCommands.status()

case "start":
    RoutunCommands.start()

case "stop":
    RoutunCommands.stop()

case "restart":
    RoutunCommands.restart()

case "logs", "log":
    var follow = false
    var lines = 50
    var errorOnly = false

    var i = 2
    while i < args.count {
        let arg = args[i]
        if arg == "-f" || arg == "--follow" {
            follow = true
        } else if arg == "-e" || arg == "--error" {
            errorOnly = true
        } else if arg == "-n" || arg == "--lines" {
            if i + 1 < args.count, let n = Int(args[i + 1]) {
                lines = n
                i += 1
            }
        }
        i += 1
    }
    RoutunCommands.logs(follow: follow, lines: lines, errorOnly: errorOnly)

case "doctor", "check":
    RoutunCommands.doctor()

case "install":
    RoutunCommands.install()

case "uninstall":
    RoutunCommands.uninstall()

case "daemon":
    let daemon = RoutunDaemon()
    daemon.run()

case "version", "-v", "--version":
    print("routun version \(version) (arm64-apple-macos)")

case "help", "-h", "--help":
    printUsage()

default:
    print("Unknown command: \(args[1])\n")
    printUsage()
    exit(1)
}
