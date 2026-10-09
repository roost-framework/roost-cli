import Foundation

#if os(Linux)
let streamSocket = Int32(SOCK_STREAM.rawValue)
#else
let streamSocket = SOCK_STREAM
#endif

enum Platform {
    /// A TCP connection to 127.0.0.1:`port`, or nil when nothing accepts one. The caller closes it.
    static func connectLoopback(_ port: Int) -> Int32? {
        let fd = socket(AF_INET, streamSocket, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        if connected { return fd }
        close(fd)
        return nil
    }

    /// The pinned Tailwind CSS release. Unpinned downloads broke new projects at v4.
    static let tailwindVersion = "v4.3.3"

    /// Returns the Tailwind CSS binary name for the current OS and architecture.
    static var tailwindBinaryName: String {
        #if os(macOS)
            #if arch(arm64)
                return "tailwindcss-macos-arm64"
            #else
                return "tailwindcss-macos-x64"
            #endif
        #else
            #if arch(arm64)
                return "tailwindcss-linux-arm64"
            #else
                return "tailwindcss-linux-x64"
            #endif
        #endif
    }
}
