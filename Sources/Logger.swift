import Foundation
import os

public final class RoutunLogger {
    public static let shared = RoutunLogger()
    private let osLogger = Logger(subsystem: "com.routun.routund", category: "daemon")

    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
    }

    public func warn(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }
}
