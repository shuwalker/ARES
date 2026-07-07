import Foundation

/// Utility to find available network ports dynamically.
public final class PortManager: Sendable {
    
    /// Finds the first available port starting from the given port number.
    public static func findOpenPort(startingAt port: UInt16) -> UInt16 {
        for p in port...65535 {
            if isPortAvailable(port: p) {
                return p
            }
        }
        return port // Fallback if all are taken (highly unlikely)
    }
    
    private static func isPortAvailable(port: UInt16) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout.size(ofValue: address))
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return bindResult >= 0
    }
}
