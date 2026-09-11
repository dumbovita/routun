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

    public static func getInterfaceInfo(name: String) -> (exists: Bool, isUp: Bool, ip: String?) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else {
            return (false, false, nil)
        }
        defer { freeifaddrs(ifap) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        var found = false
        var isUp = false
        var ipStr: String?

        while let curr = current {
            let ifaName = String(cString: curr.pointee.ifa_name)
            if ifaName == name {
                found = true
                let flags = curr.pointee.ifa_flags
                if (flags & UInt32(IFF_UP)) != 0 {
                    isUp = true
                }
                if let addr = curr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                        var sinAddr = sin.pointee.sin_addr
                        _ = inet_ntop(AF_INET, &sinAddr, &buffer, socklen_t(INET_ADDRSTRLEN))
                    }
                    ipStr = String(cString: buffer)
                }
            }
            current = curr.pointee.ifa_next
        }

        return (found, isUp, ipStr)
    }

    public static func testDPIBypass(url: String = "https://discord.com", timeout: TimeInterval = 3.5) -> (success: Bool, message: String) {
        guard let requestURL = URL(string: url) else {
            return (false, "Invalid URL")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0 (Macintosh; Apple Mac OS X) routun/1.0", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let semaphore = DispatchSemaphore(value: 0)
        var resultSuccess = false
        var resultMessage = ""

        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                resultMessage = error.localizedDescription
                resultSuccess = false
            } else if let httpResponse = response as? HTTPURLResponse {
                resultSuccess = (200...399).contains(httpResponse.statusCode)
                resultMessage = "HTTP \(httpResponse.statusCode)"
            } else {
                resultSuccess = false
                resultMessage = "No response"
            }
            semaphore.signal()
        }

        task.resume()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            return (false, "Connection timed out (\(timeout)s)")
        }

        return (resultSuccess, resultMessage)
    }
}
