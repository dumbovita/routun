import Foundation
import Darwin

public final class NetUtils {
    public static func isPortOpen(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 0.5) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        _ = host.withCString { cstr in
            inet_pton(AF_INET, cstr, &addr.sin_addr)
        }

        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectRes == 0 {
            return true
        }

        if errno != EINPROGRESS {
            return false
        }

        var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let timeoutMs = Int32(timeout * 1000)
        let pollRes = poll(&pollFd, 1, timeoutMs)

        if pollRes > 0 && (pollFd.revents & Int16(POLLOUT)) != 0 {
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0 {
                return true
            }
        }

        return false
    }

    public static func waitForPortToClose(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 0.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isPortOpen(host: host, port: port, timeout: 0.02) {
                return true
            }
            usleep(10_000)
        }
        return !isPortOpen(host: host, port: port, timeout: 0.02)
    }

    public static func getInterfaceInfo(name: String) -> (exists: Bool, isUp: Bool, ip: String?, ipv6: String?) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else {
            return (false, false, nil, nil)
        }
        defer { freeifaddrs(ifap) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        var found = false
        var isUp = false
        var ipStr: String?
        var ipv6Str: String?

        while let curr = current {
            let ifaName = String(cString: curr.pointee.ifa_name)
            if ifaName == name {
                found = true
                let flags = curr.pointee.ifa_flags
                if (flags & UInt32(IFF_UP)) != 0 {
                    isUp = true
                }
                if let addr = curr.pointee.ifa_addr {
                    if addr.pointee.sa_family == UInt8(AF_INET) {
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                            var sinAddr = sin.pointee.sin_addr
                            _ = inet_ntop(AF_INET, &sinAddr, &buffer, socklen_t(INET_ADDRSTRLEN))
                        }
                        ipStr = String(cString: buffer)
                    } else if addr.pointee.sa_family == UInt8(AF_INET6) {
                        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                            var sin6Addr = sin6.pointee.sin6_addr
                            _ = inet_ntop(AF_INET6, &sin6Addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                        }
                        let candidate = String(cString: buffer)
                        // Ignore link-local fe80:: for primary address display
                        if !candidate.hasPrefix("fe80:") || ipv6Str == nil {
                            ipv6Str = candidate
                        }
                    }
                }
            }
            current = curr.pointee.ifa_next
        }

        return (found, isUp, ipStr, ipv6Str)
    }

    public static func tunInterface(
        withIPv4Address targetAddress: String = "172.19.0.1",
        withIPv6Address targetIPv6: String = "fdfe:dcba:9876::1"
    ) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            guard name.hasPrefix("utun") else { continue }

            if address.pointee.sa_family == UInt8(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    var sinAddress = sin.pointee.sin_addr
                    _ = inet_ntop(AF_INET, &sinAddress, &buffer, socklen_t(INET_ADDRSTRLEN))
                }
                if String(cString: buffer) == targetAddress {
                    return name
                }
            } else if address.pointee.sa_family == UInt8(AF_INET6) {
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                    var sin6Address = sin6.pointee.sin6_addr
                    _ = inet_ntop(AF_INET6, &sin6Address, &buffer, socklen_t(INET6_ADDRSTRLEN))
                }
                if String(cString: buffer) == targetIPv6 {
                    return name
                }
            }
        }
        return nil
    }

    public static func isProcessAlive(pid: Int) -> Bool {
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }
}
