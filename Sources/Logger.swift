import Foundation
import os

public final class RoutunLogger {
    public static let shared = RoutunLogger()
    private let osLogger = Logger(subsystem: "com.routun.routund", category: "daemon")

    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        writeConsole(level: "INFO", message: message)
    }

    public func warn(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        writeConsole(level: "WARN", message: message)
    }

    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        writeConsole(level: "ERROR", message: message)
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }

    private func writeConsole(level: String, message: String) {
        var now = time(nil)
        var tmStruct = tm()
        localtime_r(&now, &tmStruct)
        var buffer = [CChar](repeating: 0, count: 32)
        strftime(&buffer, buffer.count, "%Y-%m-%d %H:%M:%S", &tmStruct)
        let timeStr = String(cString: buffer)

        let line = "[\(timeStr)] [\(level)] \(message)\n"
        fputs(line, stderr)
        fflush(stderr)
    }
}
